/**
 * Gift card code SHA-256 backfill (SEC-H38).
 *
 * Companion to migration `104_gift_card_code_hash.sql`, which adds the
 * `code_hash` column but can't populate it inside pure SQL (SQLite has
 * no built-in sha256). This helper walks `gift_cards` once per boot and
 * hashes any row whose `code_hash IS NULL`.
 *
 * Idempotent — after the first successful run, the WHERE clause matches
 * zero rows and the UPDATE is a no-op. Safe to call on every boot.
 */
import crypto from 'crypto';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('gift-card-hash-backfill');

interface GiftCardRow {
  id: number;
  code: string;
}

/**
 * Hash a gift card code with SHA-256. Uppercased before hashing so the
 * lookup path (which also uppercases input) matches regardless of how
 * the code was stored historically.
 */
export function hashGiftCardCode(code: string): string {
  return crypto.createHash('sha256').update(code.toUpperCase()).digest('hex');
}

/**
 * Backfill `code_hash` for every gift card row missing one. Runs in a
 * single transaction so a partial failure doesn't leave the table with
 * some rows hashed and some unhashed.
 *
 * Returns the number of rows updated.
 */
export function backfillGiftCardCodeHashes(db: any): number {
  // Safety: if the column doesn't exist yet (migration hasn't run), bail
  // silently. `runMigrations` should have already executed by the time
  // this helper is called, but callers may invoke it too early on an
  // unmigrated DB.
  try {
    const cols = db.prepare("PRAGMA table_info(gift_cards)").all() as { name: string }[];
    if (!cols.some((c) => c.name === 'code_hash')) {
      return 0;
    }
  } catch (err: unknown) {
    logger.warn('Could not inspect gift_cards table, skipping backfill', {
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }

  const pending = db
    .prepare('SELECT id, code FROM gift_cards WHERE code_hash IS NULL')
    .all() as GiftCardRow[];

  if (pending.length === 0) return 0;

  const update = db.prepare('UPDATE gift_cards SET code_hash = ? WHERE id = ?');
  const tx = db.transaction((rows: GiftCardRow[]) => {
    for (const row of rows) {
      update.run(hashGiftCardCode(row.code), row.id);
    }
  });
  tx(pending);

  logger.info('Backfilled gift card code hashes', { count: pending.length });
  return pending.length;
}
