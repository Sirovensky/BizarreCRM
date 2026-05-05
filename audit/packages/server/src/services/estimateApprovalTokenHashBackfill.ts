/**
 * Estimate approval token SHA-256 backfill (SEC-H52).
 *
 * Companion to migration `107_estimate_approval_token_hash.sql`, which adds
 * the `approval_token_hash` column but can't populate it from pure SQL
 * (SQLite has no built-in sha256). This helper walks `estimates` once per
 * boot and hashes every row that still has a plaintext `approval_token` but
 * no `approval_token_hash`.
 *
 * Idempotent — after the first successful run, the WHERE clause matches
 * zero rows and the UPDATE is a no-op. Safe to call on every boot.
 *
 * Note: we do NOT null out the plaintext `approval_token` column here.
 * During the two-step rollover (see migration 107 header), both columns
 * are read. The verify endpoint itself nulls the plaintext the first time
 * it falls back to the legacy lookup, so stale plaintext tokens drain out
 * naturally as customers approve / expire / re-send.
 */
import crypto from 'crypto';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('estimate-approval-token-hash-backfill');

interface EstimateRow {
  id: number;
  approval_token: string;
}

/**
 * Hash an estimate approval token with SHA-256. Tokens are raw random bytes
 * (hex or base64url), so no normalization is needed — bytes in, hex out.
 */
export function hashEstimateApprovalToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Backfill `approval_token_hash` for every estimate row that has a plaintext
 * `approval_token` but no hash yet. Runs in a single transaction so a partial
 * failure doesn't leave the table with some rows hashed and some unhashed.
 *
 * Returns the number of rows updated.
 */
export function backfillEstimateApprovalTokenHashes(db: any): number {
  // Safety: if the column doesn't exist yet (migration hasn't run), bail
  // silently. `runMigrations` should have already executed by the time
  // this helper is called, but callers may invoke it too early on an
  // unmigrated DB.
  try {
    const cols = db.prepare('PRAGMA table_info(estimates)').all() as { name: string }[];
    if (!cols.some((c) => c.name === 'approval_token_hash')) {
      return 0;
    }
  } catch (err: unknown) {
    logger.warn('Could not inspect estimates table, skipping backfill', {
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }

  const pending = db
    .prepare(
      'SELECT id, approval_token FROM estimates WHERE approval_token IS NOT NULL AND approval_token_hash IS NULL',
    )
    .all() as EstimateRow[];

  if (pending.length === 0) return 0;

  const update = db.prepare('UPDATE estimates SET approval_token_hash = ? WHERE id = ?');
  const tx = db.transaction((rows: EstimateRow[]) => {
    for (const row of rows) {
      update.run(hashEstimateApprovalToken(row.approval_token), row.id);
    }
  });
  tx(pending);

  logger.info('Backfilled estimate approval token hashes', { count: pending.length });
  return pending.length;
}
