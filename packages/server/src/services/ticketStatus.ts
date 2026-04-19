/**
 * Shared ticket-status-change logic.
 *
 * This module owns ALL the business-logic post-conditions and side-effects that
 * must run whenever a ticket's status changes — whether the change is triggered
 * by the HTTP PATCH /:id/status handler or by the automation engine.
 *
 * WHAT IS IN HERE (shared):
 *   - Guard checks  (post-conditions, required parts, stopwatch, diagnostic note)
 *   - The UPDATE tickets SET status_id row
 *   - Timer auto-start / auto-stop
 *   - Invoice auto-void on cancellation
 *   - Commission write on open→closed
 *   - Ticket history row
 *   - WebSocket broadcast
 *   - Webhook fire
 *   - Automation re-trigger
 *
 * WHAT STAYS IN THE ROUTE (HTTP-only):
 *   - Customer notification SMS / email (needs req.tenantSlug and retry queue)
 *   - Delayed feedback SMS (needs req.tenantSlug + setTimeout)
 *
 * SEC-H122: before this module existed, executeChangeStatus in automations.ts
 * did a raw UPDATE with no guards, allowing automations to create states the UI
 * cannot reach (e.g. `completed` without required parts or diagnostic note).
 */

import { createAsyncDb, type AsyncDb } from '../db/async-db.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { runAutomations } from './automations.js';
import { fireWebhook } from './webhooks.js';
import { writeCommission } from '../utils/commissions.js';
import { roundCents, toCents } from '../utils/validate.js';
import { calculateActiveRepairTime } from '../utils/repair-time.js';
import { AppError } from '../middleware/errorHandler.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('ticketStatus');

/** Sentinel userId used when the change originates from the automation engine. */
export const AUTOMATION_USER_ID: null = null;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type AnyRow = Record<string, any>;

export interface TicketStatusChangeResult {
  success: true;
  ticket: AnyRow | null;
  oldStatusId: number;
  newStatusId: number;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

async function insertHistory(
  adb: AsyncDb,
  ticketId: number,
  userId: number | null,
  action: string,
  description: string,
  oldValue?: string | null,
  newValue?: string | null,
): Promise<void> {
  await adb.run(
    `INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
     VALUES (?, ?, ?, ?, ?, ?)`,
    ticketId, userId, action, description, oldValue ?? null, newValue ?? null,
  );
}

async function getFullTicket(adb: AsyncDb, ticketId: number): Promise<AnyRow | null> {
  const ticket = await adb.get<AnyRow>(
    `SELECT t.*, ts.name AS status_name, ts.color AS status_color,
            ts.is_closed AS status_is_closed, ts.is_cancelled AS status_is_cancelled
       FROM tickets t
       LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.id = ? AND t.is_deleted = 0`,
    ticketId,
  );
  return ticket ?? null;
}

// ---------------------------------------------------------------------------
// Main exported helper
// ---------------------------------------------------------------------------

/**
 * Apply a ticket status change with all guards and side-effects.
 *
 * @param db        - Raw better-sqlite3 Database handle (per-tenant).
 *                    Used for services that require the synchronous handle
 *                    (calculateActiveRepairTime, broadcast, webhooks, automations).
 * @param ticketId  - The ticket to update.
 * @param newStatusId - The target status_id.
 * @param userId    - The user initiating the change, or AUTOMATION_USER_ID (null)
 *                    when called from the automation engine.
 * @param tenantSlug - Required for WebSocket broadcast tenant routing. Pass null
 *                    for single-tenant deployments.
 * @param skipGuards - When true the post-condition guards are bypassed (reserved
 *                    for internal transitions like auto-close on invoice creation).
 *                    Do NOT pass this from the automation path.
 * @param fireAutomations - When false, skip the internal runAutomations call.
 *                    Set to false when called from the automation engine so the
 *                    engine itself can re-trigger with proper depth/loop tracking.
 *                    Defaults to true (HTTP handler path).
 *
 * @throws AppError if any guard rejects the transition. The automation engine
 *   catches this and writes a 'failure' row to automation_run_log.
 */
export async function applyTicketStatusChange(
  db: any,
  ticketId: number,
  newStatusId: number,
  userId: number | null,
  tenantSlug: string | null,
  skipGuards = false,
  fireAutomations = true,
): Promise<TicketStatusChangeResult> {
  const adb: AsyncDb = createAsyncDb(db.name as string);

  // -------------------------------------------------------------------------
  // Validate ticket + statuses
  // -------------------------------------------------------------------------
  const existing = await adb.get<AnyRow>(
    'SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0',
    ticketId,
  );
  if (!existing) throw new AppError('Ticket not found', 404);

  const [oldStatus, newStatus] = await Promise.all([
    adb.get<AnyRow>('SELECT id, name, is_closed FROM ticket_statuses WHERE id = ?', existing.status_id),
    adb.get<AnyRow>('SELECT id, name, notify_customer, is_closed, is_cancelled FROM ticket_statuses WHERE id = ?', newStatusId),
  ]);
  if (!newStatus) throw new AppError('Status not found', 404);

  // -------------------------------------------------------------------------
  // Post-condition guards (skipped for internal auto-close, not for automations)
  // -------------------------------------------------------------------------
  if (!skipGuards) {
    // F10: Require post-conditions before closing
    if (newStatus.is_closed) {
      const requirePostCond = await adb.get<AnyRow>(
        "SELECT value FROM store_config WHERE key = 'repair_require_post_condition'",
      );
      if (requirePostCond?.value === '1' || requirePostCond?.value === 'true') {
        const devices = await adb.all<AnyRow>(
          'SELECT id, device_name, post_conditions FROM ticket_devices WHERE ticket_id = ?',
          ticketId,
        );
        for (const d of devices) {
          const postConds = d.post_conditions ? JSON.parse(d.post_conditions) : [];
          if (postConds.length === 0) {
            throw new AppError(`Post-conditions required for ${d.device_name} before closing`, 400);
          }
        }
      }

      // F11: Require parts before closing
      const requireParts = await adb.get<AnyRow>(
        "SELECT value FROM store_config WHERE key = 'repair_require_parts'",
      );
      if (requireParts?.value === '1' || requireParts?.value === 'true') {
        const partsCount = await adb.get<AnyRow>(
          'SELECT COUNT(*) as c FROM ticket_device_parts tdp JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?',
          ticketId,
        );
        if (partsCount!.c === 0) {
          throw new AppError('At least one part must be added before closing the ticket', 400);
        }
      }

      // SW-D5: Require repair timer usage before closing
      const requireStopwatch = await adb.get<AnyRow>(
        "SELECT value FROM store_config WHERE key = 'ticket_require_stopwatch'",
      );
      if (requireStopwatch?.value === '1') {
        const activeTime = calculateActiveRepairTime(db, ticketId);
        if (activeTime === null || activeTime <= 0) {
          throw new AppError('Repair timer must be started before closing the ticket', 400);
        }
      }
    }

    // F13: Require diagnostic note before any status change
    const requireDiag = await adb.get<AnyRow>(
      "SELECT value FROM store_config WHERE key = 'repair_require_diagnostic'",
    );
    if (requireDiag?.value === '1' || requireDiag?.value === 'true') {
      const diagNote = await adb.get<AnyRow>(
        "SELECT id FROM ticket_notes WHERE ticket_id = ? AND type = 'diagnostic' LIMIT 1",
        ticketId,
      );
      if (!diagNote) {
        throw new AppError('A diagnostic note is required before changing status', 400);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------
  await adb.run(
    'UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?',
    newStatusId, now(), ticketId,
  );

  // SW-D9: Auto-start / auto-stop repair timer based on status change
  const [timerAutoStart, timerAutoStop] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_timer_auto_start_status'"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_timer_auto_stop_status'"),
  ]);

  if (timerAutoStart?.value && String(newStatusId) === String(timerAutoStart.value)) {
    await adb.run(
      'UPDATE tickets SET repair_timer_running = 1, repair_timer_started_at = COALESCE(repair_timer_started_at, ?) WHERE id = ? AND repair_timer_running = 0',
      now(), ticketId,
    );
    await insertHistory(adb, ticketId, userId, 'timer_started', 'Repair timer auto-started on status change');
  }

  if (timerAutoStop?.value && String(newStatusId) === String(timerAutoStop.value)) {
    const running = await adb.get<AnyRow>(
      'SELECT repair_timer_running FROM tickets WHERE id = ?',
      ticketId,
    );
    if (running?.repair_timer_running) {
      await adb.run('UPDATE tickets SET repair_timer_running = 0, updated_at = ? WHERE id = ?', now(), ticketId);
      await insertHistory(adb, ticketId, userId, 'timer_stopped', 'Repair timer auto-stopped on status change');
    }
  }

  // If cancelled, void any linked unpaid invoice
  if (newStatus.is_cancelled) {
    const linkedInvoice = await adb.get<AnyRow>(
      "SELECT id, status FROM invoices WHERE ticket_id = ? AND status != 'void'",
      ticketId,
    );
    if (linkedInvoice) {
      await adb.run(
        "UPDATE invoices SET status = 'void', amount_due = 0, updated_at = ? WHERE id = ?",
        now(), linkedInvoice.id,
      );
      await insertHistory(adb, ticketId, userId, 'invoice_voided', 'Invoice auto-voided on ticket cancellation');
    }
  }

  // Sync device-level statuses to match ticket status
  await adb.run(
    'UPDATE ticket_devices SET status_id = ?, updated_at = ? WHERE ticket_id = ?',
    newStatusId, now(), ticketId,
  );

  // Open→closed commission write
  if (newStatus.is_closed && !oldStatus?.is_closed && !newStatus.is_cancelled) {
    const ticketRow = await adb.get<AnyRow>(
      'SELECT assigned_to, subtotal, discount, total, total_tax FROM tickets WHERE id = ?',
      ticketId,
    );
    const assignedTo = ticketRow?.assigned_to ?? null;
    if (assignedTo) {
      // Fast-path pre-check: skip the INSERT entirely if a non-reversal
      // commission already exists.  This avoids burning a DB write on the
      // common single-caller case.  It is NOT the correctness guarantee —
      // the UNIQUE partial index on commissions(ticket_id) WHERE type != 'reversal'
      // (migration 111) is the authoritative gate that prevents duplicates
      // even under concurrent status-change calls.
      const existingCommission = await adb.get<AnyRow>(
        `SELECT id FROM commissions
          WHERE ticket_id = ?
            AND COALESCE(type, '') != 'reversal'
          LIMIT 1`,
        ticketId,
      );
      if (!existingCommission) {
        const totalNum = Number(ticketRow?.total ?? 0);
        const taxNum = Number(ticketRow?.total_tax ?? 0);
        const subNum = Number(ticketRow?.subtotal ?? 0);
        const discNum = Number(ticketRow?.discount ?? 0);
        const preTax = totalNum > 0
          ? roundCents(totalNum - taxNum)
          : roundCents(Math.max(0, subNum - discNum));
        if (preTax > 0) {
          try {
            await writeCommission(adb, {
              userId: assignedTo,
              source: 'ticket_close',
              ticketId,
              commissionableAmountCents: toCents(preTax),
            });
          } catch (err: unknown) {
            // SEC-H68: A concurrent status-change call may have already
            // inserted the commission row between our pre-check SELECT above
            // and this INSERT.  The UNIQUE partial index (migration 111)
            // surfaces this as a SQLITE_CONSTRAINT_UNIQUE error.  Treat it as
            // a benign idempotent miss — the first writer already committed the
            // correct row — log at info and continue the rest of the
            // status-change flow without throwing.
            if (err instanceof Error && /UNIQUE constraint/i.test(err.message)) {
              logger.info('commission_already_exists', {
                ticket_id: ticketId,
                user_id: assignedTo,
                detail: 'concurrent status-change race; commission row already committed by first writer',
              });
            } else if (err instanceof AppError) {
              throw err;
            } else {
              logger.error('commission_write_failed', {
                ticket_id: ticketId,
                user_id: assignedTo,
                error: err instanceof Error ? err.message : String(err),
              });
            }
          }
        }
      }
    }
  }

  // Audit history
  await insertHistory(
    adb, ticketId, userId, 'status_changed',
    `Status changed from "${oldStatus?.name ?? '?'}" to "${newStatus.name}"`,
    oldStatus?.name ?? null, newStatus.name,
  );

  // Fetch the updated ticket for broadcast/return
  const ticket = await getFullTicket(adb, ticketId);

  // WebSocket broadcast
  broadcast(WS_EVENTS.TICKET_STATUS_CHANGED, ticket, tenantSlug);

  // Webhook
  const ticketOrderId =
    ticket && typeof (ticket as { order_id?: unknown }).order_id === 'string'
      ? (ticket as { order_id: string }).order_id
      : undefined;
  fireWebhook(db, 'ticket_status_changed', {
    ticket_id: ticketId,
    order_id: ticketOrderId,
    from_status_id: oldStatus?.id ?? null,
    to_status_id: newStatusId,
  });

  // Re-trigger automations
  const cust = await adb.get<AnyRow>(
    'SELECT * FROM customers WHERE id = ?',
    (ticket as AnyRow | null)?.customer_id,
  );
  // Re-trigger automations for the HTTP path.  When called from the automation
  // engine (fireAutomations=false) the engine handles the re-trigger itself
  // with proper depth/visitedRuleIds tracking, so we skip it here.
  if (fireAutomations) {
    // Pass tenantSlug in context so that if the re-triggered automation fires
    // another change_status, the subsequent applyTicketStatusChange call gets
    // the correct tenantSlug for broadcast routing.
    runAutomations(db, 'ticket_status_changed', {
      ticket,
      customer: cust ?? {},
      from_status_id: oldStatus?.id ?? null,
      to_status_id: newStatusId,
      tenantSlug,
    });
  }

  return {
    success: true,
    ticket,
    oldStatusId: oldStatus?.id ?? existing.status_id,
    newStatusId,
  };
}
