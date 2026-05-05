import type { Database } from 'better-sqlite3';

/**
 * Atomic sequential counter allocation.
 *
 * Fixes audit bugs I4, I5, I6, I7: the old pattern
 *   SELECT COALESCE(MAX(CAST(SUBSTR(order_id,3) AS INTEGER)), 0) + 1
 * is vulnerable to:
 *   1. POISONING — a single negative / malformed row permanently corrupts the counter.
 *   2. RACE — two concurrent INSERTs both read the same MAX and allocate the same ID.
 *
 * This function runs inside a DB transaction and uses better-sqlite3's atomic
 * UPDATE ... RETURNING to guarantee that each caller gets a unique, monotonically
 * increasing integer per counter name.
 *
 * Each tenant DB has its own counters table (migration 072). Counters are seeded
 * from the MAX of existing good rows on first migration apply. After that, the
 * counters table is the single source of truth; order_id columns are never read
 * back to pick the next number.
 *
 * Known counter names:
 *   'ticket_order_id'  → next T-{N}
 *   'invoice_order_id' → next INV-{N}
 *   'credit_note_id'   → next CN-{N}
 *   'po_number'        → next PO-{N}
 *   'inventory_sku'    → next SKU integer for auto-generated SKUs
 *
 * Callers should NOT generate their own IDs from MAX() anymore.
 */
export function allocateCounter(db: Database, name: string): number {
  // better-sqlite3 is synchronous. A single UPDATE ... RETURNING is atomic by
  // itself, but wrapping in a transaction ensures consistency if callers chain
  // multiple allocations + inserts in one logical operation.
  const run = db.transaction((counterName: string): number => {
    // Ensure the row exists (idempotent). Migration 072 seeds the known ones,
    // but this keeps the helper resilient for new counter names introduced later.
    db.prepare('INSERT OR IGNORE INTO counters (name, value) VALUES (?, 0)').run(counterName);

    const row = db
      .prepare<[string], { value: number }>(
        `UPDATE counters
           SET value = value + 1,
               updated_at = datetime('now')
         WHERE name = ?
         RETURNING value`,
      )
      .get(counterName);

    if (!row || typeof row.value !== 'number' || row.value < 1) {
      throw new Error(`Counter allocation failed for '${counterName}'`);
    }
    return row.value;
  });

  return run(name);
}

/**
 * Format a ticket order_id from a counter value. Keeps formatting in one place
 * so the counter increments and the printed ID can never drift.
 */
export function formatTicketOrderId(n: number): string {
  return `T-${n}`;
}

export function formatInvoiceOrderId(n: number): string {
  return `INV-${n}`;
}

export function formatCreditNoteId(n: number): string {
  return `CN-${n}`;
}

export function formatPoNumber(n: number): string {
  return `PO-${n}`;
}
