import { Router, type Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';
import { config } from '../config.js';
import { isFeatureAllowed } from '@bizarre-crm/shared';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { validateId } from '../utils/validate.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';

const router = Router();

// SCAN-1110 [HIGH]: POST + PUT previously accepted ANY string for
// `trigger_type` / `action_type`. A typo (`sms_send` vs `send_sms`,
// `ticket_status_change` vs `ticket_status_changed`) stored a dead rule
// that the UI displayed as active but the engine silently never fired.
// Source the allowlists from the engine's own switch cases so the routes
// can only persist values the runner actually dispatches on.
//   — `trigger_type`: every string passed as the second arg to
//     `runAutomations(db, <trigger>, ...)` across the codebase
//   — `action_type`: every `case` arm inside `services/automations.ts`
//     action executor switch (lines 597-642 at last audit)
const ALLOWED_TRIGGERS: ReadonlySet<string> = new Set([
  'ticket_created',
  'ticket_status_changed',
  'ticket_assigned',
  'customer_created',
  'invoice_created',
]);
const ALLOWED_ACTIONS: ReadonlySet<string> = new Set([
  'send_sms',
  'send_email',
  'change_status',
  'assign_to',
  'add_note',
  'create_notification',
]);

function assertTriggerType(v: unknown): asserts v is string {
  if (typeof v !== 'string' || !ALLOWED_TRIGGERS.has(v)) {
    throw new AppError(
      `Invalid trigger_type. Must be one of: ${[...ALLOWED_TRIGGERS].join(', ')}`,
      400,
    );
  }
}
function assertActionType(v: unknown): asserts v is string {
  if (typeof v !== 'string' || !ALLOWED_ACTIONS.has(v)) {
    throw new AppError(
      `Invalid action_type. Must be one of: ${[...ALLOWED_ACTIONS].join(', ')}`,
      400,
    );
  }
}

// SEC (PL5): Every write route here must verify the actor is an admin,
// regardless of whatever middleware the router is mounted under. Relying on
// the mount point means a future routing refactor can silently expose these
// endpoints to non-admins. Do the check inline at each handler entrypoint.
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
}

// SCAN-725: dry-run reads customer PII — restrict to manager+ so plain techs
// cannot enumerate the customer directory via repeated dry-run calls.
function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

// POST-ENRICH AUDIT §23.3 (PL5 defense-in-depth): the router is mounted
// behind `requireFeature('automations')` in index.ts, but the prior audit
// flagged that as brittle — a future re-ordering of middleware could quietly
// expose this file to a Free-tier tenant. Mirror the check inside each write
// handler so the feature gate survives any routing refactor. Reads are left
// open so a Free tenant can still see what automations *would* unlock.
function requireAutomationsFeature(req: Request): void {
  if (!config.multiTenant) return;
  const plan = req.tenantPlan;
  if (!plan || !isFeatureAllowed(plan, 'automations')) {
    throw new AppError('automations require Pro', 402);
  }
}

// ---------------------------------------------------------------------------
// GET / – List all automation rules
// ---------------------------------------------------------------------------
// SCAN-584: action_config may contain SMS/email template bodies. Gate this
// behind requireAdmin so technician-role users cannot enumerate automation
// rules or harvest template content.
router.get(
  '/',
  asyncHandler(async (_req, res) => {
    requireAdmin(_req);
    const adb = _req.asyncDb;
    const automations = await adb.all(`
      SELECT * FROM automations ORDER BY sort_order ASC, created_at DESC
    `);

    // Parse JSON config fields
    const parsed = automations.map((a: any) => ({
      ...a,
      trigger_config: safeParseJson(a.trigger_config, {}),
      action_config: safeParseJson(a.action_config, {}),
    }));

    res.json({ success: true, data: parsed });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create automation rule
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    requireAutomationsFeature(req);
    requireAdmin(req);
    const adb = req.asyncDb;
    const { name, trigger_type, trigger_config, action_type, action_config, sort_order } = req.body;

    if (!name) throw new AppError('name is required');
    if (!trigger_type) throw new AppError('trigger_type is required');
    if (!action_type) throw new AppError('action_type is required');
    assertTriggerType(trigger_type);
    assertActionType(action_type);

    const result = await adb.run(`
      INSERT INTO automations (name, trigger_type, trigger_config, action_type, action_config, sort_order)
      VALUES (?, ?, ?, ?, ?, ?)
    `,
      name,
      trigger_type,
      JSON.stringify(trigger_config ?? {}),
      action_type,
      JSON.stringify(action_config ?? {}),
      sort_order ?? 0,
    );

    const automation = await adb.get('SELECT * FROM automations WHERE id = ?', result.lastInsertRowid) as any;
    audit(req.db, 'automation_created', req.user!.id, req.ip || 'unknown', { automation_id: Number(result.lastInsertRowid), name, trigger_type, action_type });

    res.status(201).json({
      success: true,
      data: {
        ...automation,
        trigger_config: safeParseJson(automation.trigger_config, {}),
        action_config: safeParseJson(automation.action_config, {}),
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update automation rule
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAutomationsFeature(req);
    requireAdmin(req);
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const existing = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    if (!existing) throw new AppError('Automation not found', 404);

    const { name, trigger_type, trigger_config, action_type, action_config, sort_order } = req.body;
    // SCAN-1110: validate supplied values. Undefined skips update so leave them
    // alone — assertions run only when the field is actually present in body.
    if (trigger_type !== undefined) assertTriggerType(trigger_type);
    if (action_type !== undefined) assertActionType(action_type);

    await adb.run(`
      UPDATE automations SET
        name = ?, trigger_type = ?, trigger_config = ?, action_type = ?, action_config = ?,
        sort_order = ?, updated_at = datetime('now')
      WHERE id = ?
    `,
      name !== undefined ? name : existing.name,
      trigger_type !== undefined ? trigger_type : existing.trigger_type,
      trigger_config !== undefined ? JSON.stringify(trigger_config) : existing.trigger_config,
      action_type !== undefined ? action_type : existing.action_type,
      action_config !== undefined ? JSON.stringify(action_config) : existing.action_config,
      sort_order !== undefined ? sort_order : existing.sort_order,
      id,
    );

    const updated = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    audit(req.db, 'automation_updated', req.user!.id, req.ip || 'unknown', { automation_id: id });

    res.json({
      success: true,
      data: {
        ...updated,
        trigger_config: safeParseJson(updated.trigger_config, {}),
        action_config: safeParseJson(updated.action_config, {}),
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id – Delete automation rule
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAutomationsFeature(req);
    requireAdmin(req);
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const existing = await adb.get('SELECT id FROM automations WHERE id = ?', id);
    if (!existing) throw new AppError('Automation not found', 404);

    await adb.run('DELETE FROM automations WHERE id = ?', id);
    audit(req.db, 'automation_deleted', req.user!.id, req.ip || 'unknown', { automation_id: id });
    res.json({ success: true, data: { message: 'Automation deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id/toggle – Toggle is_active
// ---------------------------------------------------------------------------
router.patch(
  '/:id/toggle',
  asyncHandler(async (req, res) => {
    requireAutomationsFeature(req);
    requireAdmin(req);
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const existing = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    if (!existing) throw new AppError('Automation not found', 404);

    const newActive = existing.is_active ? 0 : 1;
    await adb.run("UPDATE automations SET is_active = ?, updated_at = datetime('now') WHERE id = ?",
      newActive, id);
    audit(req.db, 'automation_toggled', req.user!.id, req.ip || 'unknown', { automation_id: id, is_active: newActive });

    const updated = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;

    res.json({
      success: true,
      data: {
        ...updated,
        trigger_config: safeParseJson(updated.trigger_config, {}),
        action_config: safeParseJson(updated.action_config, {}),
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/dry-run – Evaluate trigger match without side-effects
// ---------------------------------------------------------------------------
// Accepts an optional context payload (ticket_id, invoice_id, customer_id)
// and returns whether the rule would fire + what action would execute.
// No SMS/email/status-change is performed.
router.post(
  '/:id/dry-run',
  asyncHandler(async (req, res) => {
    requireAutomationsFeature(req);
    requireManagerOrAdmin(req);
    // SCAN-727: rate-limit dry-run to prevent rule-config enumeration
    const userId = req.user!.id;
    if (!checkWindowRate(req.db, 'automation_dry_run', String(userId), 20, 60_000)) {
      throw new AppError('Too many dry-run attempts', 429);
    }
    recordWindowAttempt(req.db, 'automation_dry_run', String(userId), 60_000);
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const automation = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    if (!automation) throw new AppError('Automation not found', 404);

    const triggerConfig = safeParseJson(automation.trigger_config, {});
    const actionConfig = safeParseJson(automation.action_config, {});

    // Build context from optional payload identifiers
    const { ticket_id, invoice_id, customer_id } = (req.body ?? {}) as {
      ticket_id?: number;
      invoice_id?: number;
      customer_id?: number;
    };

    const context: Record<string, unknown> = {};

    const ticketId = ticket_id !== undefined && ticket_id !== null && ticket_id !== ('' as unknown)
      ? validateId(ticket_id, 'ticket_id')
      : null;
    const invoiceId = invoice_id !== undefined && invoice_id !== null && invoice_id !== ('' as unknown)
      ? validateId(invoice_id, 'invoice_id')
      : null;
    const customerId = customer_id !== undefined && customer_id !== null && customer_id !== ('' as unknown)
      ? validateId(customer_id, 'customer_id')
      : null;

    if (ticketId !== null) {
      const ticket = await adb.get('SELECT * FROM tickets WHERE id = ?', ticketId) as any;
      if (ticket) context.ticket = ticket;
    }

    if (invoiceId !== null) {
      const invoice = await adb.get('SELECT * FROM invoices WHERE id = ?', invoiceId) as any;
      if (invoice) context.invoice = invoice;
    }

    if (customerId !== null) {
      const customer = await adb.get('SELECT id, first_name, last_name, email, phone, mobile FROM customers WHERE id = ?', customerId) as any;
      if (customer) context.customer = customer;
    }

    // Evaluate trigger match
    let triggerWouldFire = true;
    const { from_status_id, to_status_id } = triggerConfig as { from_status_id?: number; to_status_id?: number };

    if (automation.trigger_type === 'ticket_status_changed') {
      const ticket = context.ticket as Record<string, unknown> | undefined;
      if (from_status_id !== undefined) {
        const current = ticket ? Number(ticket.status_id) : null;
        if (current !== Number(from_status_id)) triggerWouldFire = false;
      }
      if (to_status_id !== undefined) {
        // No "new status" provided in context — flag it as "unknown"
        if (!context.to_status_id && context.ticket) triggerWouldFire = false;
      }
    }

    // Summarise what action would execute (template substitution preview)
    let actionPreview: string | null = null;
    if (triggerWouldFire) {
      if (automation.action_type === 'send_sms' && actionConfig.template) {
        const customer = context.customer as Record<string, unknown> | undefined;
        const ticket = context.ticket as Record<string, unknown> | undefined;
        actionPreview = String(actionConfig.template)
          .replace(/\{customer_name\}/g, [customer?.first_name, customer?.last_name].filter(Boolean).join(' ') || '{customer_name}')
          .replace(/\{ticket_id\}/g, String(ticket?.order_id ?? ticket?.id ?? '{ticket_id}'));
      } else if (automation.action_type === 'send_email' && actionConfig.subject) {
        actionPreview = `Subject: ${actionConfig.subject}`;
      } else if (automation.action_type === 'change_status' && actionConfig.status_id) {
        const status = await adb.get('SELECT name FROM ticket_statuses WHERE id = ?', Number(actionConfig.status_id)) as any;
        actionPreview = `Change status → ${status?.name ?? actionConfig.status_id}`;
      }
    }

    res.json({
      success: true,
      data: {
        automation_id: id,
        automation_name: automation.name,
        trigger_type: automation.trigger_type,
        trigger_config: triggerConfig,
        action_type: automation.action_type,
        action_config: actionConfig,
        is_active: !!automation.is_active,
        trigger_would_fire: triggerWouldFire,
        action_preview: actionPreview,
        context_used: {
          has_ticket: !!context.ticket,
          has_invoice: !!context.invoice,
          has_customer: !!context.customer,
        },
        note: 'Dry-run only — no side effects performed',
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function safeParseJson(val: any, fallback: any = {}): any {
  if (!val) return fallback;
  try { return JSON.parse(val); } catch { return fallback; }
}

export default router;
