/**
 * SLA Assignment Helper
 *
 * Given a ticket's priority level and creation time, looks up the matching
 * active SLA policy and computes + writes sla_policy_id,
 * sla_first_response_due_at, and sla_resolution_due_at onto the ticket row.
 *
 * SCAN-464: Called from ticket.routes.ts on ticket create/priority-change.
 * DO NOT call directly from this file — it is a pure helper.
 *
 * Business-hours note:
 *   When business_hours_only = 1, SLA clocks count only Mon–Fri 09:00–17:00
 *   (8 h/day). This helper computes due-at by adding calendar hours first,
 *   then adjusting forward past evenings/weekends. When business_hours_only = 0
 *   (e.g. critical tier), wall-clock hours are used directly.
 *
 * Usage example (ticket.routes.ts):
 * ```ts
 * import { computeSlaForTicket } from '../services/slaAssignment.js';
 * // after INSERT / after priority change:
 * await computeSlaForTicket(req.asyncDb, {
 *   ticket_id: newTicketId,
 *   priority_level: priority,
 *   created_at: ticketCreatedAt,
 * });
 * ```
 */

import type { AsyncDb } from '../db/async-db.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('sla-assignment');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface SlaTicketInput {
  ticket_id: number;
  priority_level: string;
  created_at: string;
}

interface SlaPolicy {
  id: number;
  priority_level: string;
  first_response_hours: number;
  resolution_hours: number;
  business_hours_only: number;
}

// ---------------------------------------------------------------------------
// Business-hours arithmetic
// ---------------------------------------------------------------------------

const BIZ_HOURS_START = 9;  // 09:00 local (UTC for simplicity — same server TZ)
const BIZ_HOURS_END   = 17; // 17:00
const BIZ_HOURS_PER_DAY = BIZ_HOURS_END - BIZ_HOURS_START; // 8

/**
 * Add `hours` business hours to `from`, skipping evenings (before 09:00 /
 * after 17:00 UTC) and weekends (Saturday = 6, Sunday = 0).
 * Returns a UTC ISO string truncated to seconds.
 */
function addBusinessHours(from: Date, hours: number): Date {
  let remaining = hours * 60; // work in minutes for precision
  let cursor = new Date(from.getTime());

  // If cursor starts outside business hours, advance to next open window
  cursor = advanceToNextBizMinute(cursor);

  while (remaining > 0) {
    const endOfDay = new Date(cursor.getTime());
    endOfDay.setUTCHours(BIZ_HOURS_END, 0, 0, 0);

    const minutesUntilEod = Math.max(0, (endOfDay.getTime() - cursor.getTime()) / 60_000);

    if (remaining <= minutesUntilEod) {
      cursor = new Date(cursor.getTime() + remaining * 60_000);
      remaining = 0;
    } else {
      remaining -= minutesUntilEod;
      // Jump to next business day 09:00
      cursor = new Date(cursor.getTime() + minutesUntilEod * 60_000);
      cursor = advanceToNextBizMinute(cursor);
    }
  }

  return cursor;
}

/** Advance cursor to the start of the next business minute if currently outside hours. */
function advanceToNextBizMinute(d: Date): Date {
  let cursor = new Date(d.getTime());
  // Max 10 iterations to avoid infinite loop on bad input
  for (let i = 0; i < 10; i++) {
    const dow = cursor.getUTCDay(); // 0=Sun, 6=Sat
    const hour = cursor.getUTCHours();

    if (dow === 0 || dow === 6) {
      // Weekend: jump to next Monday 09:00
      const daysToMonday = dow === 0 ? 1 : 2;
      cursor = new Date(cursor.getTime());
      cursor.setUTCDate(cursor.getUTCDate() + daysToMonday);
      cursor.setUTCHours(BIZ_HOURS_START, 0, 0, 0);
      continue;
    }

    if (hour < BIZ_HOURS_START) {
      cursor.setUTCHours(BIZ_HOURS_START, 0, 0, 0);
      continue;
    }

    if (hour >= BIZ_HOURS_END) {
      // After end of day: advance to next weekday 09:00
      cursor.setUTCDate(cursor.getUTCDate() + 1);
      cursor.setUTCHours(BIZ_HOURS_START, 0, 0, 0);
      continue;
    }

    // Cursor is inside business hours
    break;
  }
  return cursor;
}

/**
 * Add calendar hours (wall-clock) to a date.
 */
function addCalendarHours(from: Date, hours: number): Date {
  return new Date(from.getTime() + hours * 3_600_000);
}

function toSqliteTimestamp(d: Date): string {
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

// ---------------------------------------------------------------------------
// Public export
// ---------------------------------------------------------------------------

/**
 * Look up the matching SLA policy for `priority_level`, compute due-at
 * timestamps, and UPDATE the ticket row. Silently no-ops (with a log warn)
 * if no active policy is found for the given priority level.
 *
 * @param adb            AsyncDb instance for the current tenant
 * @param input          ticket_id, priority_level, and created_at of the ticket
 */
export async function computeSlaForTicket(
  adb: AsyncDb,
  input: SlaTicketInput,
): Promise<void> {
  const { ticket_id, priority_level, created_at } = input;

  if (!priority_level) {
    logger.warn('sla-assignment: no priority_level provided', { ticket_id });
    return;
  }

  let policy: SlaPolicy | undefined;
  try {
    policy = await adb.get<SlaPolicy>(
      `SELECT id, priority_level, first_response_hours, resolution_hours, business_hours_only
       FROM sla_policies
       WHERE priority_level = ? AND is_active = 1
       LIMIT 1`,
      priority_level,
    );
  } catch (err) {
    // Table may not exist on un-migrated DBs — don't crash ticket creation
    logger.warn('sla-assignment: could not query sla_policies', {
      ticket_id,
      err: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (!policy) {
    logger.warn('sla-assignment: no active policy for priority_level', {
      ticket_id,
      priority_level,
    });
    return;
  }

  // Parse ticket created_at as base timestamp
  const base = new Date(created_at.replace(' ', 'T') + (created_at.includes('T') ? '' : 'Z'));
  if (isNaN(base.getTime())) {
    logger.warn('sla-assignment: invalid created_at timestamp', { ticket_id, created_at });
    return;
  }

  const useBizHours = policy.business_hours_only === 1;
  const addHours = useBizHours ? addBusinessHours : addCalendarHours;

  const firstResponseDue = toSqliteTimestamp(addHours(base, policy.first_response_hours));
  const resolutionDue = toSqliteTimestamp(addHours(base, policy.resolution_hours));

  try {
    await adb.run(
      `UPDATE tickets
       SET sla_policy_id             = ?,
           sla_first_response_due_at = ?,
           sla_resolution_due_at     = ?,
           sla_breached              = 0
       WHERE id = ?`,
      policy.id, firstResponseDue, resolutionDue, ticket_id,
    );
    logger.info('sla-assignment: SLA assigned', {
      ticket_id,
      policy_id: policy.id,
      priority_level,
      first_response_due_at: firstResponseDue,
      resolution_due_at: resolutionDue,
      business_hours_only: useBizHours,
    });
  } catch (err) {
    logger.error('sla-assignment: failed to update ticket', {
      ticket_id,
      err: err instanceof Error ? err.message : String(err),
    });
  }
}
