/**
 * Receipt OCR Cron (SCAN-490).
 *
 * Runs every 2 minutes. For each tenant DB:
 *   1. Claims up to 10 'pending' uploads (oldest first) and calls
 *      processReceiptOcr for each one sequentially (one Tesseract worker at
 *      a time bounds peak memory usage).
 *   2. Stale-cleanup pass: any 'pending' upload older than 24 h is marked
 *      'failed' so the queue never accumulates infinite pending rows.
 *
 * Wiring (do NOT edit index.ts here — see registration snippet at bottom):
 *   import { startReceiptOcrCron } from './services/receiptOcrCron.js';
 *   const receiptOcrTimer = startReceiptOcrCron(() => getActiveDbIterable(), config.uploadsPath);
 *   backgroundIntervals.push(receiptOcrTimer);
 *
 * Contract:
 *   - startReceiptOcrCron() returns a NodeJS.Timeout for trackInterval /
 *     backgroundIntervals (graceful shutdown).
 *   - Never throws at the top level — all errors are logged and swallowed.
 *   - Processes uploads one at a time per tenant so Tesseract memory is
 *     bounded (one image in memory per tick regardless of tenant count).
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { processReceiptOcr } from './receiptOcr.js';

const logger = createLogger('receipt-ocr-cron');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CRON_INTERVAL_MS = 2 * 60 * 1000;          // 2 minutes
const PENDING_BATCH_LIMIT = 10;                    // uploads per tenant per tick
const STALE_PENDING_HOURS = 24;                    // hours before a pending/processing is failed

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TenantDbEntry {
  slug: string;
  db: Database.Database;
}

// Row shapes for prepared queries
interface UploadIdRow {
  id: number;
}

// ---------------------------------------------------------------------------
// Per-tenant work
// ---------------------------------------------------------------------------

/**
 * Stale-cleanup pass: mark any pending upload older than STALE_PENDING_HOURS
 * as failed.  Runs at every tick to prevent infinite-pending accumulation when
 * the OCR processor is unavailable.
 */
function cleanStale(slug: string, db: Database.Database): void {
  try {
    const staleModifier = `-${STALE_PENDING_HOURS} hours`;
    const result = db
      .prepare(
        `UPDATE expense_receipt_uploads
            SET ocr_status    = 'failed',
                error_message = 'OCR processor not configured — tesseract.js not installed'
          WHERE ocr_status IN ('pending', 'processing')
            AND created_at <= datetime('now', ?)`,
      )
      .run(staleModifier);

    if (result.changes > 0) {
      logger.warn('OCR: stale pending uploads marked failed', {
        slug,
        count: result.changes,
        stale_hours: STALE_PENDING_HOURS,
      });
    }
  } catch (err) {
    // Table may not exist on tenants not yet migrated — skip silently.
    logger.debug('OCR stale-cleanup skipped (table may be missing)', {
      slug,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Process up to PENDING_BATCH_LIMIT pending uploads for one tenant DB.
 * Uploads are processed sequentially (not concurrently) so Tesseract's worker
 * thread is fully released between images.
 */
async function runForTenant(
  slug: string,
  db: Database.Database,
  uploadsPath: string,
): Promise<void> {
  // --- stale cleanup first (synchronous, fast) ---
  cleanStale(slug, db);

  // --- fetch pending batch ---
  let rows: UploadIdRow[];
  try {
    rows = db
      .prepare<[], UploadIdRow>(
        `SELECT id
           FROM expense_receipt_uploads
          WHERE ocr_status = 'pending'
          ORDER BY created_at ASC
          LIMIT ${PENDING_BATCH_LIMIT}`,
      )
      .all();
  } catch (err) {
    // Table may not exist on un-migrated tenants.
    logger.debug('OCR: could not query expense_receipt_uploads', {
      slug,
      error: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (rows.length === 0) return;

  logger.info('OCR: processing batch', { slug, count: rows.length });

  for (const row of rows) {
    // processReceiptOcr never throws; any per-upload error is recorded in the DB row.
    await processReceiptOcr(db, row.id, uploadsPath);
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Start the receipt OCR background cron.
 *
 * @param getDbsFn    Callback returning the current set of active tenant DBs.
 *                    Called on every tick so newly provisioned tenants are included.
 * @param uploadsPath Absolute path to the uploads root (config.uploadsPath).
 * @returns           NodeJS.Timeout handle. Pass to backgroundIntervals.push()
 *                    or trackInterval() in index.ts for graceful shutdown.
 *
 * Registration snippet (add to index.ts after server.listen — DO NOT edit index.ts here):
 * ```ts
 * import { startReceiptOcrCron } from './services/receiptOcrCron.js';
 * try {
 *   const receiptOcrTimer = startReceiptOcrCron(() => {
 *     const entries: Array<{ slug: string; db: any }> = [];
 *     forEachDb((slug, db) => { if (slug && db) entries.push({ slug, db }); });
 *     return entries as unknown as Iterable<import('./services/receiptOcrCron.js').TenantDbEntry>;
 *   }, config.uploadsPath);
 *   backgroundIntervals.push(receiptOcrTimer);
 * } catch (err) {
 *   log.error('Failed to start receipt OCR cron', {
 *     error: err instanceof Error ? err.message : String(err),
 *   });
 * }
 * ```
 */
export function startReceiptOcrCron(
  getDbsFn: () => Iterable<TenantDbEntry>,
  uploadsPath: string,
): NodeJS.Timeout {
  async function tick(): Promise<void> {
    try {
      for (const { slug, db } of getDbsFn()) {
        // Process tenants sequentially to cap peak Tesseract memory usage.
        await runForTenant(slug, db, uploadsPath);
      }
    } catch (err) {
      logger.error('receipt-ocr-cron: top-level tick error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Run once immediately on startup so uploads queued before server restart
  // are not held up for up to 2 minutes.
  void tick();
  return setInterval(() => void tick(), CRON_INTERVAL_MS);
}
