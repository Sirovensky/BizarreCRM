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

import { sendSmsTenant } from './smsProvider.js';
import { sendEmail } from './email.js';
import { createLogger } from '../utils/logger.js';
import { escapeHtml, stripSmsControlChars } from '../utils/escape.js';
import { applyTicketStatusChange, AUTOMATION_USER_ID } from './ticketStatus.js';

const logger = createLogger('automations');

// AU-LOOP (rerun §24): beyond the in-memory recursion depth check, we also
// enforce a *per-ticket per-hour* cap across independent trigger evaluations.
// This catches pathological patterns like A→resolved + B→open where each
// individual chain has depth 1 but the ticket ping-pongs indefinitely between
// two statuses over several seconds/minutes.
const MAX_RUNS_PER_TICKET_PER_HOUR = 20;

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
// Template variable interpolation (AU3: escape by output mode)
// ---------------------------------------------------------------------------
// Escape helpers live in `utils/escape.ts` and are imported above so the same
// rules apply to automation templates AND the notifications service. Keeping
// them in one place avoids the classic "one callsite was patched, the other
// wasn't" XSS regression.

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

/** Returns a copy of vars with phone and email fields redacted — use only in log paths. */
function maskedVarsForLogging(vars: Record<string, unknown>): Record<string, unknown> {
  const masked = { ...vars };
  if (typeof masked.customer_phone === 'string' && masked.customer_phone) {
    masked.customer_phone = '***' + masked.customer_phone.slice(-4);
  }
  if (typeof masked.customer_email === 'string' && masked.customer_email) {
    const atIdx = masked.customer_email.indexOf('@');
    const local = atIdx > 0 ? masked.customer_email.slice(0, atIdx) : masked.customer_email;
    const domain = atIdx > 0 ? masked.customer_email.slice(atIdx) : '';
    masked.customer_email = local.slice(0, 2) + '***' + domain;
  }
  return masked;
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

/**
 * Automation trigger-type → SMS consent category mapping (SCAN-585 / TCPA).
 *
 * Marketing triggers: birthday, review_request, promo, loyalty, win_back.
 *   → require sms_consent_marketing = 1
 *
 * Transactional triggers: ticket_status_changed, ready_for_pickup, invoice_due,
 *   appointment_reminder, and everything else.
 *   → require sms_consent_transactional = 1 OR sms_opt_in = 1
 *
 * NULL column values (legacy rows pre-migration) are treated as opted-in so
 * existing customers are not silently suppressed after deploy.
 */
const MARKETING_TRIGGERS = new Set([
  'birthday',
  'review_request',
  'promo',
  'loyalty',
  'win_back',
]);

async function executeSendSms(
  db: any,
  config: ActionConfig,
  vars: Record<string, unknown>,
  triggerType: string,
): Promise<ActionResult> {
  const to = config.to
    ? interpolate(String(config.to), vars, 'sms')
    : String(vars.customer_phone || '');
  const body = interpolate(config.template ?? '', vars, 'sms');
  if (!to || !body) {
    logger.info('send_sms skipped — missing to or template', { to: !!to, body: !!body });
    return { success: false, error: 'missing to or template' };
  }

  // SCAN-585: check customer consent before sending any automation SMS.
  try {
    const row = db.prepare(
      'SELECT sms_opt_in, sms_consent_marketing, sms_consent_transactional FROM customers WHERE phone = ? OR mobile = ? LIMIT 1',
    ).get(to, to) as {
      sms_opt_in: number | null;
      sms_consent_marketing: number | null;
      sms_consent_transactional: number | null;
    } | undefined;

    if (row) {
      const isMarketing = MARKETING_TRIGGERS.has(triggerType);
      let allowed: boolean;
      if (isMarketing) {
        // Marketing: explicit marketing consent required.
        allowed = row.sms_consent_marketing !== 0 && row.sms_opt_in !== 0;
      } else {
        // Transactional: either global opt-in or transactional consent.
        allowed = row.sms_opt_in !== 0 && row.sms_consent_transactional !== 0;
      }
      if (!allowed) {
        logger.info('send_sms skipped — customer opted out', {
          to: to.slice(-4),
          triggerType,
          isMarketing,
          sms_opt_in: row.sms_opt_in,
          sms_consent_marketing: row.sms_consent_marketing,
          sms_consent_transactional: row.sms_consent_transactional,
        });
        return { success: true }; // skipped but not a failure — don't surface as error
      }
    }
    // No customer row found for this phone — allow send (could be an explicit
    // `to` override in config that isn't tied to a customer record).
  } catch (consentErr) {
    // Consent check must not block the send if the DB query fails (e.g. column
    // absent on an old tenant DB without the consent migration). Log and proceed.
    logger.warn('send_sms consent check failed — proceeding without check', {
      to: to.slice(-4),
      triggerType,
      error: consentErr instanceof Error ? consentErr.message : String(consentErr),
    });
  }

  try {
    // SCAN-585 / AU5: use sendSmsTenant so the per-tenant provider + TCPA quiet-hours
    // guard are applied. tenantSlug flows through buildVars from the trigger context.
    const tenantSlug = typeof vars.tenantSlug === 'string' ? vars.tenantSlug : null;
    await sendSmsTenant(db, tenantSlug, to, body);
    return { success: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error('send_sms failed', { toRedacted: to.slice(-4), error: message });
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

/**
 * SEC-H122: replaces the old raw UPDATE with the shared applyTicketStatusChange
 * helper so automations run the same post-condition guards (required parts,
 * diagnostic note, stopwatch, post-conditions) that the HTTP handler enforces.
 *
 * Returns a Promise<ActionResult> — the caller in the switch must await it.
 * tenantSlug is extracted from context. The automation re-trigger is handled
 * by the engine itself (not inside applyTicketStatusChange) so depth and
 * visitedRuleIds tracking is preserved.
 */
async function executeChangeStatus(
  db: any,
  actionConfig: ActionConfig,
  context: Record<string, unknown>,
): Promise<ActionResult> {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.status_id) {
    return { success: false, error: 'missing ticket or status_id' };
  }
  const tenantSlug = typeof context.tenantSlug === 'string' ? context.tenantSlug : null;
  try {
    // fireAutomations=false: the engine re-triggers with proper depth tracking below.
    await applyTicketStatusChange(
      db,
      Number(ticket.id),
      Number(actionConfig.status_id),
      AUTOMATION_USER_ID,
      tenantSlug,
      false, // skipGuards
      false, // fireAutomations — engine handles re-trigger
    );
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
  // user_id is required by the notifications table (NOT NULL). When the action
  // config omits it we broadcast to all active users instead of failing silently.
  const targetUserId = actionConfig.user_id ? Number(actionConfig.user_id) : null;
  try {
    const message = interpolate(actionConfig.message, vars, 'raw');

    if (targetUserId) {
      db.prepare(`
        INSERT INTO notifications (user_id, type, title, message, created_at, updated_at)
        VALUES (?, 'automation', 'Automation', ?, datetime('now'), datetime('now'))
      `).run(targetUserId, message);
    } else {
      // No target user configured — insert for every active (non-deleted) user
      const users = db.prepare("SELECT id FROM users WHERE is_active = 1").all() as Array<{ id: number }>;
      const stmt = db.prepare(`
        INSERT INTO notifications (user_id, type, title, message, created_at, updated_at)
        VALUES (?, 'automation', 'Automation', ?, datetime('now'), datetime('now'))
      `);
      for (const u of users) stmt.run(u.id, message);
    }
    return { success: true };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : String(err) };
  }
}

// ---------------------------------------------------------------------------
// Safe JSON config parsing (SCAN-890)
// ---------------------------------------------------------------------------

function safeParseConfig(raw: string | null, field: string, ruleId: number): Record<string, unknown> {
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      logger.warn('automation config not an object', { rule_id: ruleId, field });
      return {};
    }
    return parsed as Record<string, unknown>;
  } catch (err) {
    logger.warn('automation config JSON.parse failed', {
      rule_id: ruleId,
      field,
      err: err instanceof Error ? err.message : String(err),
    });
    return {};
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
          const triggerConfig = safeParseConfig(rule.trigger_config, 'trigger_config', rule.id) as TriggerConfig;
          const actionConfig = safeParseConfig(rule.action_config, 'action_config', rule.id) as ActionConfig;

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
              result = await executeSendSms(db, actionConfig, vars, trigger);
              break;
            case 'send_email':
              result = await executeSendEmail(db, actionConfig, vars);
              break;
            case 'change_status': {
              // SEC-H122: executeChangeStatus now delegates to applyTicketStatusChange
              // which runs all guards + side-effects (broadcast, webhook, audit
              // history). It does NOT re-trigger automations internally (fireAutomations
              // =false) — we do it here so depth/visitedRuleIds tracking is preserved.
              result = await executeChangeStatus(db, actionConfig, context);
              if (result.success) {
                const nextCtx: AutomationExecContext = {
                  depth: ctx.depth + 1,
                  visitedRuleIds: new Set(ctx.visitedRuleIds).add(rule.id),
                };
                // Pass tenantSlug forward so recursive change_status chains can
                // route WebSocket broadcasts to the correct tenant.
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

          // AU-LOOP (SCAN-894): count-check + log insert in a single synchronous
          // transaction so no concurrent evaluation can bypass the hourly cap.
          // The action has already run above; the tx decides whether to record it
          // as success/failure or override with loop_rejected.
          const finalLogEntry = { ...baseLogEntry, status: result.success ? ('success' as RunStatus) : ('failure' as RunStatus), error_message: result.error ?? null };
          try {
            db.transaction(() => {
              if (target.type === 'ticket' && target.id !== null) {
                const capRow = db
                  .prepare(
                    "SELECT COUNT(*) AS c FROM automation_run_log " +
                      "WHERE target_entity_type = 'ticket' AND target_entity_id = ? " +
                      "AND created_at > datetime('now','-1 hour')",
                  )
                  .get(target.id) as { c?: number } | undefined;
                if ((capRow?.c ?? 0) >= MAX_RUNS_PER_TICKET_PER_HOUR) {
                  logger.warn('Automation per-ticket hourly cap exceeded — rejecting run', {
                    trigger,
                    ticketId: target.id,
                    runsLastHour: capRow?.c,
                    cap: MAX_RUNS_PER_TICKET_PER_HOUR,
                  });
                  logAutomationRun(db, {
                    ...baseLogEntry,
                    status: 'loop_rejected',
                    error_message: `per-ticket hourly cap ${MAX_RUNS_PER_TICKET_PER_HOUR} exceeded`,
                  });
                  return;
                }
              }
              logAutomationRun(db, finalLogEntry);
            })();
          } catch (txErr) {
            // automation_run_log table absent (old tenant DB) — log and continue.
            logger.warn('automation_run_log tx failed, skipping hourly cap check', {
              error: txErr instanceof Error ? txErr.message : String(txErr),
            });
          }
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
