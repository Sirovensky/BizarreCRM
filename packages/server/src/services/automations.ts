/**
 * Automation trigger engine.
 *
 * Evaluates active automation rules when triggers fire, executing configured actions.
 * Each rule runs independently — one failure does not block others.
 *
 * SECURITY / AUDIT NOTES (criticalaudit.md section 24):
 *   - The `db` parameter is ALWAYS a per-tenant SQLite handle. Tenant isolation is
 *     enforced at the DB connection layer (see tenantDb.ts + routes/*.ts middleware),
 *     not by a `tenant_id` WHERE filter. This means the automations table itself has
 *     no tenant_id column, and `SELECT * FROM automations` is safe as long as every
 *     caller passes the correct tenant DB. See AU1 in criticalaudit.md.
 *   - `change_status` actions can form loops (A→B + B→A). We cap recursion depth at
 *     MAX_CHAIN_DEPTH using an execution context, rejecting further runs beyond that.
 *   - Template interpolation HTML-escapes values for email bodies and strips control
 *     chars for SMS bodies. Without this, `{customer_name}` → `<script>…</script>`
 *     would flow straight into email HTML.
 *   - Every execution attempt is recorded in automation_run_log (migration 081),
 *     including success, failure, skipped (conditions not met), and loop_rejected.
 */

import { sendSms } from './smsProvider.js';
import { sendEmail } from './email.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('automations');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AutomationRow {
  id: number;
  name: string;
  trigger_type: string;
  trigger_config: string; // JSON
  action_type: string;
  action_config: string;  // JSON
  is_active: number;
}

interface TriggerConfig {
  from_status_id?: number;
  to_status_id?: number;
  [key: string]: unknown;
}

interface ActionConfig {
  template?: string;
  to?: string;
  subject?: string;
  body?: string;
  status_id?: number;
  user_id?: number;
  type?: string;
  content?: string;
  message?: string;
  [key: string]: unknown;
}

/**
 * Execution context passed through a single automation chain. Tracks the depth of
 * change_status → ticket_status_changed → change_status recursion so we can reject
 * infinite loops (AU2).
 */
interface AutomationExecContext {
  depth: number;
  /** Set of automation IDs already fired in this chain (belt + suspenders). */
  visitedRuleIds: Set<number>;
}

const MAX_CHAIN_DEPTH = 5;

// ---------------------------------------------------------------------------
// HTML escape / SMS sanitize helpers (AU3)
// ---------------------------------------------------------------------------

const HTML_ESCAPES: Readonly<Record<string, string>> = Object.freeze({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#x27;',
});

function escapeHtml(input: string): string {
  return input.replace(/[&<>"']/g, (ch) => HTML_ESCAPES[ch] ?? ch);
}

/** Remove control chars (0x00-0x1F, 0x7F) that could break SMS provider payloads. */
function stripSmsControlChars(input: string): string {
  // eslint-disable-next-line no-control-regex
  return input.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}

// ---------------------------------------------------------------------------
// Template variable interpolation (AU3: escape by output mode)
// ---------------------------------------------------------------------------

type EscapeMode = 'html' | 'sms' | 'raw';

function interpolate(
  template: string,
  context: Record<string, unknown>,
  mode: EscapeMode = 'raw',
): string {
  return template.replace(/\{(\w+)\}/g, (_match, key: string) => {
    const val = context[key];
    if (val === undefined || val === null) return '';
    const str = String(val);
    if (mode === 'html') return escapeHtml(str);
    if (mode === 'sms') return stripSmsControlChars(str);
    return str;
  });
}

/** Build a flat variable map from the trigger context for template interpolation. */
function buildVars(context: Record<string, unknown>): Record<string, unknown> {
  const vars: Record<string, unknown> = {};
  const ticket = context.ticket as Record<string, unknown> | undefined;
  const customer = context.customer as Record<string, unknown> | undefined;
  const invoice = context.invoice as Record<string, unknown> | undefined;

  if (ticket) {
    vars.ticket_id = ticket.order_id ?? ticket.id;
    vars.ticket_total = ticket.total;
    vars.ticket_status = ticket.status_name ?? (ticket.status as any)?.name ?? '';
    // First device name
    const devices = ticket.devices as Array<Record<string, unknown>> | undefined;
    vars.device_name = devices?.[0]?.device_name ?? '';
  }

  if (customer) {
    vars.customer_name = [customer.first_name, customer.last_name].filter(Boolean).join(' ');
    vars.customer_phone = customer.phone ?? customer.mobile ?? '';
    vars.customer_email = customer.email ?? '';
  }

  if (invoice) {
    vars.invoice_id = invoice.order_id ?? invoice.id;
    vars.invoice_total = invoice.total;
  }

  // Pass through any flat keys from context
  for (const [k, v] of Object.entries(context)) {
    if (typeof v === 'string' || typeof v === 'number') {
      vars[k] = v;
    }
  }

  return vars;
}

// ---------------------------------------------------------------------------
// Condition matching
// ---------------------------------------------------------------------------

function matchesTrigger(triggerConfig: TriggerConfig, context: Record<string, unknown>): boolean {
  // ticket_status_changed: optional from_status_id / to_status_id filters
  if (triggerConfig.from_status_id !== undefined) {
    if (Number(context.from_status_id) !== Number(triggerConfig.from_status_id)) return false;
  }
  if (triggerConfig.to_status_id !== undefined) {
    if (Number(context.to_status_id) !== Number(triggerConfig.to_status_id)) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Run log (AU6) — every attempt gets recorded
// ---------------------------------------------------------------------------

type RunStatus = 'success' | 'failure' | 'skipped' | 'loop_rejected';

interface RunLogEntry {
  automation_id: number;
  automation_name: string;
  trigger_event: string;
  action_type: string | null;
  target_entity_type: string | null;
  target_entity_id: number | null;
  status: RunStatus;
  error_message: string | null;
  depth: number;
}

function extractTarget(context: Record<string, unknown>): { type: string | null; id: number | null } {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (ticket?.id !== undefined) return { type: 'ticket', id: Number(ticket.id) };
  const invoice = context.invoice as Record<string, unknown> | undefined;
  if (invoice?.id !== undefined) return { type: 'invoice', id: Number(invoice.id) };
  const customer = context.customer as Record<string, unknown> | undefined;
  if (customer?.id !== undefined) return { type: 'customer', id: Number(customer.id) };
  return { type: null, id: null };
}

function logAutomationRun(db: any, entry: RunLogEntry): void {
  try {
    db.prepare(`
      INSERT INTO automation_run_log
        (automation_id, automation_name, trigger_event, action_type,
         target_entity_type, target_entity_id, status, error_message, depth, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    `).run(
      entry.automation_id,
      entry.automation_name,
      entry.trigger_event,
      entry.action_type,
      entry.target_entity_type,
      entry.target_entity_id,
      entry.status,
      entry.error_message,
      entry.depth,
    );
  } catch (err) {
    // The run log itself must never break the automation engine. If the table is
    // missing (old tenant DB without migration 081), fall back to structured log.
    logger.error('Failed to write automation_run_log row', {
      automationId: entry.automation_id,
      trigger: entry.trigger_event,
      status: entry.status,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

// ---------------------------------------------------------------------------
// Action executors
// ---------------------------------------------------------------------------

interface ActionResult {
  success: boolean;
  error?: string;
}

async function executeSendSms(
  config: ActionConfig,
  vars: Record<string, unknown>,
): Promise<ActionResult> {
  const to = config.to
    ? interpolate(String(config.to), vars, 'sms')
    : String(vars.customer_phone || '');
  const body = interpolate(config.template ?? '', vars, 'sms');
  if (!to || !body) {
    logger.info('send_sms skipped — missing to or template', { to: !!to, body: !!body });
    return { success: false, error: 'missing to or template' };
  }
  try {
    // AU5: await the send + propagate the error to the caller so it can be logged.
    await sendSms(to, body);
    return { success: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error('send_sms failed', { to, error: message });
    return { success: false, error: message };
  }
}

async function executeSendEmail(
  db: any,
  config: ActionConfig,
  vars: Record<string, unknown>,
): Promise<ActionResult> {
  const to = String(vars.customer_email || '');
  const subject = interpolate(config.subject ?? '', vars, 'html');
  const html = interpolate(config.body ?? '', vars, 'html');
  if (!to || !subject) {
    logger.info('send_email skipped — missing to or subject', { to: !!to, subject: !!subject });
    return { success: false, error: 'missing to or subject' };
  }
  // L5: sendEmail returns boolean. Propagate failure instead of pretending success.
  const sent = await sendEmail(db, { to, subject, html });
  if (!sent) {
    logger.error('send_email failed (SMTP not configured or transport error)', { to, subject });
    return { success: false, error: 'email transport failed' };
  }
  return { success: true };
}

function executeChangeStatus(
  db: any,
  actionConfig: ActionConfig,
  context: Record<string, unknown>,
): ActionResult {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.status_id) {
    return { success: false, error: 'missing ticket or status_id' };
  }
  try {
    db.prepare("UPDATE tickets SET status_id = ?, updated_at = datetime('now') WHERE id = ?")
      .run(actionConfig.status_id, ticket.id);
    return { success: true };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : String(err) };
  }
}

function executeAssignTo(
  db: any,
  actionConfig: ActionConfig,
  context: Record<string, unknown>,
): ActionResult {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.user_id) {
    return { success: false, error: 'missing ticket or user_id' };
  }
  try {
    db.prepare("UPDATE tickets SET assigned_to = ?, updated_at = datetime('now') WHERE id = ?")
      .run(actionConfig.user_id, ticket.id);
    return { success: true };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : String(err) };
  }
}

function executeAddNote(
  db: any,
  actionConfig: ActionConfig,
  vars: Record<string, unknown>,
  context: Record<string, unknown>,
): ActionResult {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.content) {
    return { success: false, error: 'missing ticket or content' };
  }
  try {
    const noteType = actionConfig.type === 'diagnostic' ? 'diagnostic' : 'internal';
    const content = interpolate(actionConfig.content, vars, 'raw');
    db.prepare(`
      INSERT INTO ticket_notes (ticket_id, type, content, created_by, created_at)
      VALUES (?, ?, ?, 'system', datetime('now'))
    `).run(ticket.id, noteType, content);
    return { success: true };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : String(err) };
  }
}

function executeCreateNotification(
  db: any,
  actionConfig: ActionConfig,
  vars: Record<string, unknown>,
): ActionResult {
  if (!actionConfig.message) {
    return { success: false, error: 'missing message' };
  }
  try {
    const message = interpolate(actionConfig.message, vars, 'raw');
    db.prepare(`
      INSERT INTO notifications (type, title, message, created_at)
      VALUES ('automation', 'Automation', ?, datetime('now'))
    `).run(message);
    return { success: true };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : String(err) };
  }
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/**
 * Run all active automations matching the given trigger type.
 *
 * Executes asynchronously — caller should not await this. Tenant isolation is
 * assumed at the `db` handle layer (see file-level SECURITY notes).
 *
 * The optional fourth arg carries recursion state for change_status chains.
 * External callers should NOT pass it — it is only used by the engine itself
 * when re-entering from a change_status action.
 */
export function runAutomations(
  db: any,
  trigger: string,
  context: Record<string, unknown>,
  execContext?: AutomationExecContext,
): void {
  // Run async so we don't block the response
  (async () => {
    const ctx: AutomationExecContext = execContext ?? {
      depth: 0,
      visitedRuleIds: new Set<number>(),
    };

    try {
      // AU1: no tenant_id filter needed — `db` is already the per-tenant handle.
      // If the multi-tenant architecture ever flattens to one shared DB, this query
      // MUST gain a WHERE tenant_id = ? clause; see SECURITY note at top of file.
      const rules = db
        .prepare(
          'SELECT * FROM automations WHERE trigger_type = ? AND is_active = 1 ORDER BY sort_order ASC',
        )
        .all(trigger) as AutomationRow[];

      if (rules.length === 0) return;

      const vars = buildVars(context);
      logger.info('Trigger evaluated', {
        trigger,
        ruleCount: rules.length,
        depth: ctx.depth,
      });

      for (const rule of rules) {
        const target = extractTarget(context);
        const baseLogEntry = {
          automation_id: rule.id,
          automation_name: rule.name,
          trigger_event: trigger,
          action_type: rule.action_type ?? null,
          target_entity_type: target.type,
          target_entity_id: target.id,
          depth: ctx.depth,
        };

        try {
          const triggerConfig: TriggerConfig = rule.trigger_config ? JSON.parse(rule.trigger_config) : {};
          const actionConfig: ActionConfig = rule.action_config ? JSON.parse(rule.action_config) : {};

          if (!matchesTrigger(triggerConfig, context)) {
            logAutomationRun(db, { ...baseLogEntry, status: 'skipped', error_message: 'trigger filter not matched' });
            continue;
          }

          // AU2: loop detection for change_status chains.
          if (rule.action_type === 'change_status') {
            if (ctx.depth >= MAX_CHAIN_DEPTH) {
              logger.warn('Automation chain rejected — max depth reached', {
                ruleId: rule.id,
                ruleName: rule.name,
                depth: ctx.depth,
                maxDepth: MAX_CHAIN_DEPTH,
              });
              logAutomationRun(db, {
                ...baseLogEntry,
                status: 'loop_rejected',
                error_message: `max chain depth ${MAX_CHAIN_DEPTH} reached`,
              });
              continue;
            }
            if (ctx.visitedRuleIds.has(rule.id)) {
              logger.warn('Automation chain rejected — rule already fired in this chain', {
                ruleId: rule.id,
                ruleName: rule.name,
                depth: ctx.depth,
              });
              logAutomationRun(db, {
                ...baseLogEntry,
                status: 'loop_rejected',
                error_message: 'rule already fired in chain',
              });
              continue;
            }
          }

          logger.info('Executing rule', {
            ruleId: rule.id,
            ruleName: rule.name,
            actionType: rule.action_type,
            depth: ctx.depth,
          });

          let result: ActionResult;
          switch (rule.action_type) {
            case 'send_sms':
              result = await executeSendSms(actionConfig, vars);
              break;
            case 'send_email':
              result = await executeSendEmail(db, actionConfig, vars);
              break;
            case 'change_status': {
              result = executeChangeStatus(db, actionConfig, context);
              // Re-fire ticket_status_changed trigger with incremented depth so
              // downstream automations can react, but loops get caught above.
              if (result.success) {
                const nextCtx: AutomationExecContext = {
                  depth: ctx.depth + 1,
                  visitedRuleIds: new Set(ctx.visitedRuleIds).add(rule.id),
                };
                // Fire-and-forget re-entry; any errors caught by the inner try.
                runAutomations(
                  db,
                  'ticket_status_changed',
                  {
                    ...context,
                    from_status_id: (context.ticket as any)?.status_id,
                    to_status_id: actionConfig.status_id,
                  },
                  nextCtx,
                );
              }
              break;
            }
            case 'assign_to':
              result = executeAssignTo(db, actionConfig, context);
              break;
            case 'add_note':
              result = executeAddNote(db, actionConfig, vars, context);
              break;
            case 'create_notification':
              result = executeCreateNotification(db, actionConfig, vars);
              break;
            default:
              logger.warn('Unknown action_type', { ruleId: rule.id, ruleName: rule.name, actionType: rule.action_type });
              result = { success: false, error: `unknown action_type: ${rule.action_type}` };
          }

          logAutomationRun(db, {
            ...baseLogEntry,
            status: result.success ? 'success' : 'failure',
            error_message: result.error ?? null,
          });
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          logger.error('Rule failed', { ruleId: rule.id, ruleName: rule.name, error: message });
          logAutomationRun(db, {
            ...baseLogEntry,
            status: 'failure',
            error_message: message,
          });
        }
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error('Failed to query automation rules', { trigger, error: message });
    }
  })();
}
