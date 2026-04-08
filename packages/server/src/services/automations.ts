/**
 * Automation trigger engine.
 *
 * Evaluates active automation rules when triggers fire, executing configured actions.
 * Each rule runs independently — one failure does not block others.
 */

import { sendSms } from './smsProvider.js';
import { sendEmail } from './email.js';

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

// ---------------------------------------------------------------------------
// Template variable interpolation
// ---------------------------------------------------------------------------

function interpolate(template: string, context: Record<string, unknown>): string {
  return template.replace(/\{(\w+)\}/g, (_match, key: string) => {
    const val = context[key];
    return val !== undefined && val !== null ? String(val) : '';
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
// Action executors
// ---------------------------------------------------------------------------

async function executeSendSms(config: ActionConfig, vars: Record<string, unknown>): Promise<void> {
  const to = config.to ? interpolate(String(config.to), vars) : String(vars.customer_phone || '');
  const body = interpolate(config.template ?? '', vars);
  if (!to || !body) {
    console.log('[Automations] send_sms skipped — missing to or template');
    return;
  }
  await sendSms(to, body);
}

async function executeSendEmail(db: any, config: ActionConfig, vars: Record<string, unknown>): Promise<void> {
  const to = String(vars.customer_email || '');
  const subject = interpolate(config.subject ?? '', vars);
  const html = interpolate(config.body ?? '', vars);
  if (!to || !subject) {
    console.log('[Automations] send_email skipped — missing to or subject');
    return;
  }
  await sendEmail(db, { to, subject, html });
}

function executeChangeStatus(db: any, actionConfig: ActionConfig, context: Record<string, unknown>): void {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.status_id) return;
  db.prepare('UPDATE tickets SET status_id = ?, updated_at = datetime(\'now\') WHERE id = ?')
    .run(actionConfig.status_id, ticket.id);
}

function executeAssignTo(db: any, actionConfig: ActionConfig, context: Record<string, unknown>): void {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.user_id) return;
  db.prepare('UPDATE tickets SET assigned_to = ?, updated_at = datetime(\'now\') WHERE id = ?')
    .run(actionConfig.user_id, ticket.id);
}

function executeAddNote(db: any, actionConfig: ActionConfig, vars: Record<string, unknown>, context: Record<string, unknown>): void {
  const ticket = context.ticket as Record<string, unknown> | undefined;
  if (!ticket?.id || !actionConfig.content) return;
  const noteType = actionConfig.type === 'diagnostic' ? 'diagnostic' : 'internal';
  const content = interpolate(actionConfig.content, vars);
  db.prepare(`
    INSERT INTO ticket_notes (ticket_id, type, content, created_by, created_at)
    VALUES (?, ?, ?, 'system', datetime('now'))
  `).run(ticket.id, noteType, content);
}

function executeCreateNotification(db: any, actionConfig: ActionConfig, vars: Record<string, unknown>): void {
  if (!actionConfig.message) return;
  const message = interpolate(actionConfig.message, vars);
  db.prepare(`
    INSERT INTO notifications (type, title, message, created_at)
    VALUES ('automation', 'Automation', ?, datetime('now'))
  `).run(message);
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/**
 * Run all active automations matching the given trigger type.
 * Executes asynchronously — caller should not await this.
 */
export function runAutomations(db: any, trigger: string, context: Record<string, unknown>): void {
  // Run async so we don't block the response
  (async () => {
    try {
      const rules = db.prepare(
        'SELECT * FROM automations WHERE trigger_type = ? AND is_active = 1 ORDER BY sort_order ASC'
      ).all(trigger) as AutomationRow[];

      if (rules.length === 0) return;

      const vars = buildVars(context);
      console.log(`[Automations] Trigger "${trigger}" — ${rules.length} rule(s) to evaluate`);

      for (const rule of rules) {
        try {
          const triggerConfig: TriggerConfig = rule.trigger_config ? JSON.parse(rule.trigger_config) : {};
          const actionConfig: ActionConfig = rule.action_config ? JSON.parse(rule.action_config) : {};

          if (!matchesTrigger(triggerConfig, context)) {
            continue;
          }

          console.log(`[Automations] Executing rule "${rule.name}" (${rule.action_type})`);

          switch (rule.action_type) {
            case 'send_sms':
              await executeSendSms(actionConfig, vars);
              break;
            case 'send_email':
              await executeSendEmail(db, actionConfig, vars);
              break;
            case 'change_status':
              executeChangeStatus(db, actionConfig, context);
              break;
            case 'assign_to':
              executeAssignTo(db, actionConfig, context);
              break;
            case 'add_note':
              executeAddNote(db, actionConfig, vars, context);
              break;
            case 'create_notification':
              executeCreateNotification(db, actionConfig, vars);
              break;
            default:
              console.log(`[Automations] Unknown action_type "${rule.action_type}" in rule "${rule.name}"`);
          }
        } catch (err) {
          console.error(`[Automations] Rule "${rule.name}" (id=${rule.id}) failed:`, err);
        }
      }
    } catch (err) {
      console.error('[Automations] Failed to query rules:', err);
    }
  })();
}
