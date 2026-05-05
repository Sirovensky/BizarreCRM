
/**
 * Patterns that indicate an INACTIVE (hold/wait) status.
 * Time spent in these statuses is excluded from active repair time.
 */
const INACTIVE_PATTERNS = [
  /waiting/i,
  /hold/i,
  /on\s*hold/i,
  /parts\s*arrived/i,
  /cancelled/i,
];

function isInactiveStatus(statusName: string): boolean {
  return INACTIVE_PATTERNS.some(p => p.test(statusName));
}

interface HistoryRow {
  action: string;
  old_value: string | null;
  new_value: string | null;
  created_at: string;
}

interface TicketRow {
  created_at: string;
  status_name: string;
  is_closed: number;
}

/**
 * Calculate active repair time in hours for a single ticket.
 * Walks through status change history and sums only time in active statuses.
 *
 * Returns null if ticket has no history or is not yet closed.
 */
export function calculateActiveRepairTime(db: any, ticketId: number): number | null {
  const ticket = db.prepare(`
    SELECT t.created_at, ts.name AS status_name, ts.is_closed
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.id = ? AND t.is_deleted = 0
  `).get(ticketId) as TicketRow | undefined;

  if (!ticket) return null;

  // Get all status change events in chronological order
  // Handle both 'status_changed' and 'status_change' action names
  const history = db.prepare(`
    SELECT action, old_value, new_value, created_at
    FROM ticket_history
    WHERE ticket_id = ? AND action IN ('status_changed', 'status_change')
    ORDER BY created_at ASC, id ASC
  `).all(ticketId) as HistoryRow[];

  // If no history, fall back to simple elapsed time for closed tickets
  if (history.length === 0) {
    if (!ticket.is_closed) return null;
    // No status changes recorded — assume all time was active
    return null;
  }

  let activeMs = 0;
  // Initial status: ticket starts in whatever status it was created with
  // The first history entry's old_value tells us (or default to 'Open')
  let currentStatus = history[0].old_value || 'Open';
  let segmentStart = new Date(ticket.created_at).getTime();

  for (const entry of history) {
    const changeTime = new Date(entry.created_at).getTime();

    if (!isInactiveStatus(currentStatus)) {
      activeMs += Math.max(0, changeTime - segmentStart);
    }

    currentStatus = entry.new_value || currentStatus;
    segmentStart = changeTime;
  }

  // Final segment: from last status change to now (if open) or to close time
  if (ticket.is_closed) {
    // The last history entry that closed it is the close time
    const lastCloseEntry = [...history].reverse().find(h => {
      const name = h.new_value || '';
      // Check if this was the transition to a closed status
      const status = db.prepare('SELECT is_closed FROM ticket_statuses WHERE name = ?').get(name) as { is_closed: number } | undefined;
      return status?.is_closed === 1;
    });

    if (lastCloseEntry) {
      const closeTime = new Date(lastCloseEntry.created_at).getTime();
      // The last segment up to close was already counted in the loop
      // (the loop processes the close entry and moves segmentStart to closeTime)
      // No additional time to add — ticket is done
    }
    // Don't count time after closure
  } else {
    // Ticket still open — count time in current status up to now
    if (!isInactiveStatus(currentStatus)) {
      activeMs += Math.max(0, Date.now() - segmentStart);
    }
  }

  return activeMs / (1000 * 60 * 60); // Convert to hours
}

/**
 * Calculate average active repair time across multiple closed tickets.
 * Used by report endpoints.
 */
export function calculateAvgActiveRepairTime(db: any, ticketIds: number[]): number | null {
  if (ticketIds.length === 0) return null;

  const times: number[] = [];
  for (const id of ticketIds) {
    const t = calculateActiveRepairTime(db, id);
    if (t !== null) times.push(t);
  }

  if (times.length === 0) return null;
  return times.reduce((a, b) => a + b, 0) / times.length;
}

/**
 * Get IDs of closed tickets within a date range (for report use).
 */
export function getClosedTicketIds(db: any, from?: string, to?: string, assignedTo?: number): number[] {
  let sql = `
    SELECT DISTINCT t.id
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 1
  `;
  const params: any[] = [];

  if (from) {
    sql += ' AND DATE(t.created_at) >= ?';
    params.push(from);
  }
  if (to) {
    sql += ' AND DATE(t.created_at) <= ?';
    params.push(to);
  }
  if (assignedTo !== undefined) {
    sql += ' AND t.assigned_to = ?';
    params.push(assignedTo);
  }

  return (db.prepare(sql).all(...params) as { id: number }[]).map(r => r.id);
}

/**
 * Get closed ticket IDs from the last N days (for dashboard).
 */
export function getRecentClosedTicketIds(db: any, days: number): number[] {
  return (db.prepare(`
    SELECT DISTINCT t.id
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    JOIN ticket_history th ON th.ticket_id = t.id
    WHERE t.is_deleted = 0
      AND ts.is_closed = 1
      AND th.action IN ('status_changed', 'status_change')
      AND th.created_at >= datetime('now', ?)
  `).all(`-${days} days`) as { id: number }[]).map(r => r.id);
}
