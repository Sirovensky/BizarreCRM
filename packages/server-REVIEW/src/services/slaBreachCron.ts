/**
 * SLA Breach Cron
 *
 * Runs every 5 minutes. For each tenant DB, finds tickets whose SLA
 * resolution deadline has passed but whose sla_breached flag is still 0,
 * marks them breached, inserts a sla_breach_log row, and optionally emits
 * a WebSocket event.
 *
 * Idempotency / race safety:
 *   - The UPDATE uses `WHERE sla_breached = 0` so a concurrent tick that
 *     races us will find 0 rows to change for already-flagged tickets.
 *   - The entire mark+log pair runs inside a transaction so we never have a
 *     ticket flagged without a matching log row (or vice-versa on crash).
 *
 * SCAN-464: Ticket SLA tracking
 *
 * Registration snippet (add to index.ts after server.listen):
 * ```ts
 * import { startSlaBreachCron } from './services/slaBreachCron.js';
 * const slaBreachTimer = startSlaBreachCron(() => getActiveDbIterable());
 * trackInterval(slaBreachTimer);
 * ```
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { broadcast } from '../ws/server.js';

const logger = createLogger('sla-breach-cron');

const CRON_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TenantDbEntry {
  slug: string;
  db: Database.Database;
}

interface OverdueTicket {
  id: number;
  sla_policy_id: number | null;
  order_id: string | null;
}

// ---------------------------------------------------------------------------
// Per-tenant run
// ---------------------------------------------------------------------------

function runForTenant(slug: string, db: Database.Database): void {
  let overdueTickets: OverdueTicket[];

  try {
    overdueTickets = db.prepare<[], OverdueTicket>(`
      SELECT id, sla_policy_id, order_id
      FROM tickets
      WHERE sla_resolution_due_at IS NOT NULL
        AND sla_resolution_due_at <= datetime('now')
        AND sla_breached = 0
        AND status NOT IN ('closed', 'completed', 'resolved')
    `).all();
  } catch (err) {
    // Columns may not exist on tenants pending migration — skip gracefully.
    logger.warn('sla-breach-cron: could not query tickets', {
      slug,
      err: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (overdueTickets.length === 0) return;

  logger.info('sla-breach-cron: processing overdue tickets', {
    slug,
    count: overdueTickets.length,
  });

  for (const ticket of overdueTickets) {
    markBreached(slug, db, ticket);
  }
}

function markBreached(slug: string, db: Database.Database, ticket: OverdueTicket): void {
  const breachedAt = new Date().toISOString().replace('T', ' ').slice(0, 19);

  try {
    // SCAN-1137: gate the broadcast on whether the UPDATE actually flipped
    // the flag for this tick; previously the rebroadcast fired on every
    // tick for already-breached tickets.
    const logged = db.transaction((): boolean => {
      // Idempotency guard: only mark if still 0 (another tick may have raced us)
      const updateResult = db.prepare(`
        UPDATE tickets
        SET sla_breached = 1
        WHERE id = ? AND sla_breached = 0
      `).run(ticket.id);

      if (updateResult.changes === 0) {
        return false;
      }

      db.prepare(`
        INSERT INTO sla_breach_log
          (ticket_id, policy_id, breach_type, breached_at)
        VALUES (?, ?, 'resolution', ?)
      `).run(ticket.id, ticket.sla_policy_id ?? null, breachedAt);

      logger.info('sla-breach-cron: ticket marked breached', {
        slug,
        ticket_id: ticket.id,
        order_id: ticket.order_id,
        breached_at: breachedAt,
      });
      return true;
    })();

    if (logged) {
      try {
        broadcast('sla_breached', {
          ticket_id: ticket.id,
          order_id: ticket.order_id,
          breach_type: 'resolution',
          breached_at: breachedAt,
        }, slug);
      } catch (wsErr) {
        logger.warn('sla-breach-cron: ws broadcast failed', {
          slug,
          ticket_id: ticket.id,
          err: wsErr instanceof Error ? wsErr.message : String(wsErr),
        });
      }
    }
  } catch (err) {
    logger.error('sla-breach-cron: failed to mark ticket breached', {
      slug,
      ticket_id: ticket.id,
      err: err instanceof Error ? err.message : String(err),
    });
  }
}

// ---------------------------------------------------------------------------
// First-response breach scan
// ---------------------------------------------------------------------------

/**
 * Also checks first_response breach: tickets where sla_first_response_due_at
 * has passed but no `first_response` breach log entry exists yet.
 * We detect this by checking a dedicated flag-free approach:
 * look for tickets past first_response_due_at with no first_response entry.
 */
function runFirstResponseBreaches(slug: string, db: Database.Database): void {
  let overdueFirstResponse: OverdueTicket[];

  try {
    overdueFirstResponse = db.prepare<[], OverdueTicket>(`
      SELECT t.id, t.sla_policy_id, t.order_id
      FROM tickets t
      WHERE t.sla_first_response_due_at IS NOT NULL
        AND t.sla_first_response_due_at <= datetime('now')
        AND t.status NOT IN ('closed', 'completed', 'resolved')
        AND NOT EXISTS (
          SELECT 1 FROM sla_breach_log bl
          WHERE bl.ticket_id = t.id AND bl.breach_type = 'first_response'
        )
    `).all();
  } catch (err) {
    // Table or columns may not exist yet — skip
    logger.warn('sla-breach-cron: could not query first-response breaches', {
      slug,
      err: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (overdueFirstResponse.length === 0) return;

  logger.info('sla-breach-cron: first-response breaches', {
    slug,
    count: overdueFirstResponse.length,
  });

  for (const ticket of overdueFirstResponse) {
    markFirstResponseBreached(slug, db, ticket);
  }
}

function markFirstResponseBreached(slug: string, db: Database.Database, ticket: OverdueTicket): void {
  const breachedAt = new Date().toISOString().replace('T', ' ').slice(0, 19);

  try {
    // SCAN-1137: previously the `if (result.changes === 0) return` guard sat
    // inside the transaction callback, but the `broadcast(...)` call fired
    // unconditionally AFTER the transaction — every cron tick rebroadcast
    // `sla_breached` for already-logged tickets, spamming connected
    // clients with duplicate alerts. Return a boolean from the transaction
    // and only broadcast on a true first insert.
    const logged = db.transaction((): boolean => {
      // Idempotent at the DB level via the UNIQUE index on
      // (ticket_id, breach_type) added in migration 143. `INSERT OR IGNORE`
      // collapses the SELECT+INSERT into one atomic statement so two
      // concurrent workers can't both log the same breach.
      const result = db.prepare(`
        INSERT OR IGNORE INTO sla_breach_log
          (ticket_id, policy_id, breach_type, breached_at)
        VALUES (?, ?, 'first_response', ?)
      `).run(ticket.id, ticket.sla_policy_id ?? null, breachedAt);

      if (result.changes === 0) return false; // Already logged.

      logger.info('sla-breach-cron: first_response breach logged', {
        slug,
        ticket_id: ticket.id,
        order_id: ticket.order_id,
        breached_at: breachedAt,
      });
      return true;
    })();

    if (logged) {
      try {
        broadcast('sla_breached', {
          ticket_id: ticket.id,
          order_id: ticket.order_id,
          breach_type: 'first_response',
          breached_at: breachedAt,
        }, slug);
      } catch (wsErr) {
        logger.warn('sla-breach-cron: ws broadcast failed (first_response)', {
          slug,
          ticket_id: ticket.id,
          err: wsErr instanceof Error ? wsErr.message : String(wsErr),
        });
      }
    }
  } catch (err) {
    logger.error('sla-breach-cron: failed to log first_response breach', {
      slug,
      ticket_id: ticket.id,
      err: err instanceof Error ? err.message : String(err),
    });
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Start the SLA breach background cron.
 *
 * @param getDbsFn  Callback returning the current set of active tenant DBs.
 *                  Called on every tick so newly provisioned tenants are included.
 * @returns         The NodeJS.Timeout handle. Pass to trackInterval() in
 *                  index.ts for graceful shutdown.
 *
 * Registration snippet (add to index.ts after server.listen):
 * ```ts
 * import { startSlaBreachCron } from './services/slaBreachCron.js';
 * const slaBreachTimer = startSlaBreachCron(() => getActiveDbIterable());
 * trackInterval(slaBreachTimer);
 * ```
 */
export function startSlaBreachCron(
  getDbsFn: () => Iterable<TenantDbEntry>,
): NodeJS.Timeout {
  function tick(): void {
    try {
      for (const { slug, db } of getDbsFn()) {
        runForTenant(slug, db);
        runFirstResponseBreaches(slug, db);
      }
    } catch (err) {
      logger.error('sla-breach-cron top-level error', {
        err: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Run once immediately on startup, then every CRON_INTERVAL_MS
  tick();
  return setInterval(tick, CRON_INTERVAL_MS);
}
