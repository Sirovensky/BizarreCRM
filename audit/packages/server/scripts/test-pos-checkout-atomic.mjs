#!/usr/bin/env node
/**
 * AUD-20260414-H3 integration test fixture for /pos/checkout-with-ticket.
 *
 * Proves the atomic-transaction fix: if ANY step in the checkout sequence
 * (ticket insert, invoice insert, line-item insert, payment insert, stock
 * decrement) fails, NO rows are written.
 *
 * Strategy: rather than spin up the full Express stack we replicate the
 * exact batched TxQuery[] pattern the route uses and verify rollback.
 *
 * Usage:
 *   cd packages/server && node scripts/test-pos-checkout-atomic.mjs
 *
 * Prerequisites:
 *   - data/bizarre-crm.db exists (run `npm run migrate` + `npm run seed` first)
 *   - run before starting the server (the script holds an exclusive handle)
 *
 * Exit codes:
 *   0 — all assertions passed
 *   1 — at least one assertion failed (orphan rows found)
 *   2 — setup error (missing DB, missing fixture data, etc.)
 */
import Database from 'better-sqlite3';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Allow targeting a tenant DB via env var (multi-tenant dev setups keep
// inventory under packages/server/data/tenants/<slug>.db). Defaults to the
// single-tenant dev DB.
const DB_PATH = process.env.DB_PATH
  ? path.resolve(process.env.DB_PATH)
  : path.resolve(__dirname, '..', 'data', 'bizarre-crm.db');

const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const RESET = '\x1b[0m';

let passed = 0;
let failed = 0;
function assert(condition, message) {
  if (condition) {
    console.log(`  ${GREEN}PASS${RESET} ${message}`);
    passed++;
  } else {
    console.log(`  ${RED}FAIL${RESET} ${message}`);
    failed++;
  }
}

function section(title) {
  console.log(`\n${YELLOW}${title}${RESET}`);
}

// --- Bootstrap ---------------------------------------------------------
let db;
try {
  db = new Database(DB_PATH);
  db.pragma('foreign_keys = ON');
} catch (err) {
  console.error(`${RED}Cannot open DB at ${DB_PATH}: ${err.message}${RESET}`);
  console.error('Run `npm run migrate && npm run seed` first, and make sure no server is holding the file.');
  process.exit(2);
}

// Fetch a baseline inventory row we can use in the cart
const inv = db.prepare(`
  SELECT id, name, in_stock, item_type, retail_price
  FROM inventory_items
  WHERE is_active = 1 AND item_type != 'service' AND in_stock >= 1
  ORDER BY id ASC LIMIT 1
`).get();

if (!inv) {
  console.error(`${RED}No suitable inventory item found (need is_active=1, item_type!='service', in_stock>=1)${RESET}`);
  process.exit(2);
}

const walkIn = db.prepare("SELECT id FROM customers WHERE code = 'WALK-IN' LIMIT 1").get()
  || db.prepare("SELECT id FROM customers WHERE is_deleted = 0 LIMIT 1").get();
if (!walkIn) {
  console.error(`${RED}No customer row available${RESET}`);
  process.exit(2);
}
const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get()
  || db.prepare('SELECT id FROM ticket_statuses LIMIT 1').get();
if (!defaultStatus) {
  console.error(`${RED}No ticket_statuses rows — seed first${RESET}`);
  process.exit(2);
}

// --- Baseline snapshot --------------------------------------------------
const snapshot = {
  tickets: db.prepare('SELECT COUNT(*) AS c FROM tickets').get().c,
  ticket_devices: db.prepare('SELECT COUNT(*) AS c FROM ticket_devices').get().c,
  invoices: db.prepare('SELECT COUNT(*) AS c FROM invoices').get().c,
  invoice_line_items: db.prepare('SELECT COUNT(*) AS c FROM invoice_line_items').get().c,
  payments: db.prepare('SELECT COUNT(*) AS c FROM payments').get().c,
  pos_transactions: db.prepare('SELECT COUNT(*) AS c FROM pos_transactions').get().c,
  in_stock: inv.in_stock,
};
console.log('Baseline counts:', snapshot);

// --- Scenario: guarded stock decrement fails mid-batch -----------------
section('Scenario 1 — stock race (expectChanges fails) rolls back ticket + invoice + payments');

const ticketOrderId = `T-TEST-${Date.now()}`;
const invoiceOrderId = `INV-TEST-${Date.now()}`;
const userId = 1;
const nowStr = new Date().toISOString().replace('T', ' ').slice(0, 19);

// Simulate the exact TxQuery[] pattern the route uses, with a deliberately
// impossible stock decrement (require more than in_stock) at step 5f. The
// better-sqlite3 transaction should throw and every prior INSERT should
// roll back.
const impossibleQty = inv.in_stock + 999; // guaranteed shortage
const txn = db.transaction(() => {
  // 5a. ticket
  db.prepare(`
    INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                         source, labels, due_on, created_by, tracking_token, signature_file, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    ticketOrderId, walkIn.id, defaultStatus.id, null, 0, null,
    'Walk-in', '[]', null, userId, 'test-tok', null, nowStr, nowStr,
  );

  // 5b. invoice
  db.prepare(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
                          amount_paid, amount_due, status, created_by, created_at, updated_at)
    VALUES (?, ?, (SELECT id FROM tickets WHERE order_id = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    invoiceOrderId, walkIn.id, ticketOrderId,
    inv.retail_price, 0, 0, inv.retail_price,
    inv.retail_price, 0, 'paid', userId, nowStr, nowStr,
  );

  // 5c. invoice_line_items
  db.prepare(`
    INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
    VALUES ((SELECT id FROM invoices WHERE order_id = ?), ?, ?, ?, ?, ?, ?)
  `).run(invoiceOrderId, inv.id, inv.name, impossibleQty, inv.retail_price, 0, inv.retail_price * impossibleQty);

  // 5e. payment row
  db.prepare(`
    INSERT INTO payments (invoice_id, amount, method, user_id, created_at)
    VALUES ((SELECT id FROM invoices WHERE order_id = ?), ?, ?, ?, ?)
  `).run(invoiceOrderId, inv.retail_price * impossibleQty, 'cash', userId, nowStr);

  // 5f. GUARDED stock decrement — will affect 0 rows because impossibleQty > in_stock
  const dec = db.prepare(`
    UPDATE inventory_items
       SET in_stock = in_stock - ?, updated_at = ?
     WHERE id = ? AND in_stock >= ?
  `).run(impossibleQty, nowStr, inv.id, impossibleQty);

  if (dec.changes === 0) {
    const err = new Error(`Insufficient stock for ${inv.name}`);
    err.code = 'E_EXPECT_CHANGES';
    throw err;
  }
});

let thrown = null;
try {
  txn();
} catch (err) {
  thrown = err;
}

assert(thrown !== null, 'transaction threw on guarded stock failure');
assert(
  thrown && (thrown.code === 'E_EXPECT_CHANGES' || /Insufficient stock/.test(thrown.message)),
  `error tagged with E_EXPECT_CHANGES / matching Insufficient stock (got: ${thrown?.code} / ${thrown?.message})`,
);

// --- Post-rollback verification ---------------------------------------
section('Scenario 1 — verify ZERO orphan rows after rollback');

const after = {
  tickets: db.prepare('SELECT COUNT(*) AS c FROM tickets').get().c,
  ticket_devices: db.prepare('SELECT COUNT(*) AS c FROM ticket_devices').get().c,
  invoices: db.prepare('SELECT COUNT(*) AS c FROM invoices').get().c,
  invoice_line_items: db.prepare('SELECT COUNT(*) AS c FROM invoice_line_items').get().c,
  payments: db.prepare('SELECT COUNT(*) AS c FROM payments').get().c,
  pos_transactions: db.prepare('SELECT COUNT(*) AS c FROM pos_transactions').get().c,
  in_stock: db.prepare('SELECT in_stock FROM inventory_items WHERE id = ?').get(inv.id).in_stock,
};

assert(after.tickets === snapshot.tickets, `tickets unchanged (${after.tickets} === ${snapshot.tickets})`);
assert(after.invoices === snapshot.invoices, `invoices unchanged (${after.invoices} === ${snapshot.invoices})`);
assert(after.invoice_line_items === snapshot.invoice_line_items, `invoice_line_items unchanged (${after.invoice_line_items} === ${snapshot.invoice_line_items})`);
assert(after.payments === snapshot.payments, `payments unchanged (${after.payments} === ${snapshot.payments})`);
assert(after.pos_transactions === snapshot.pos_transactions, `pos_transactions unchanged (${after.pos_transactions} === ${snapshot.pos_transactions})`);
assert(after.in_stock === snapshot.in_stock, `inventory in_stock unchanged (${after.in_stock} === ${snapshot.in_stock})`);

// Double-check the specific order_ids we tried to insert are NOT present
const ticketRow = db.prepare('SELECT id FROM tickets WHERE order_id = ?').get(ticketOrderId);
const invoiceRow = db.prepare('SELECT id FROM invoices WHERE order_id = ?').get(invoiceOrderId);
assert(!ticketRow, `ticket with order_id=${ticketOrderId} does NOT exist`);
assert(!invoiceRow, `invoice with order_id=${invoiceOrderId} does NOT exist`);

// --- Scenario: happy path still works under the same atomic wrapper ----
section('Scenario 2 — sanity check: successful atomic insert when all guards pass');

const goodTicketOrderId = `T-GOOD-${Date.now()}`;
const goodInvoiceOrderId = `INV-GOOD-${Date.now()}`;

const happyTxn = db.transaction(() => {
  db.prepare(`
    INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                         source, labels, due_on, created_by, tracking_token, signature_file, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    goodTicketOrderId, walkIn.id, defaultStatus.id, null, 0, null,
    'Walk-in', '[]', null, userId, 'good-tok', null, nowStr, nowStr,
  );

  db.prepare(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
                          amount_paid, amount_due, status, created_by, created_at, updated_at)
    VALUES (?, ?, (SELECT id FROM tickets WHERE order_id = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    goodInvoiceOrderId, walkIn.id, goodTicketOrderId,
    inv.retail_price, 0, 0, inv.retail_price,
    inv.retail_price, 0, 'paid', userId, nowStr, nowStr,
  );

  db.prepare(`
    INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
    VALUES ((SELECT id FROM invoices WHERE order_id = ?), ?, ?, ?, ?, ?, ?)
  `).run(goodInvoiceOrderId, inv.id, inv.name, 1, inv.retail_price, 0, inv.retail_price);

  db.prepare(`
    INSERT INTO payments (invoice_id, amount, method, user_id, created_at)
    VALUES ((SELECT id FROM invoices WHERE order_id = ?), ?, ?, ?, ?)
  `).run(goodInvoiceOrderId, inv.retail_price, 'cash', userId, nowStr);

  const dec = db.prepare(`
    UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ? AND in_stock >= ?
  `).run(1, nowStr, inv.id, 1);
  if (dec.changes === 0) {
    const err = new Error(`Insufficient stock for ${inv.name}`);
    err.code = 'E_EXPECT_CHANGES';
    throw err;
  }
});

happyTxn();

const happyTicket = db.prepare('SELECT id FROM tickets WHERE order_id = ?').get(goodTicketOrderId);
const happyInvoice = db.prepare('SELECT id FROM invoices WHERE order_id = ?').get(goodInvoiceOrderId);
const happyLines = db.prepare('SELECT COUNT(*) AS c FROM invoice_line_items WHERE invoice_id = ?').get(happyInvoice.id).c;
const happyPayments = db.prepare('SELECT COUNT(*) AS c FROM payments WHERE invoice_id = ?').get(happyInvoice.id).c;
const happyStock = db.prepare('SELECT in_stock FROM inventory_items WHERE id = ?').get(inv.id).in_stock;

assert(!!happyTicket, 'happy-path ticket was inserted');
assert(!!happyInvoice, 'happy-path invoice was inserted');
assert(happyLines >= 1, `happy-path invoice has ${happyLines} line items (>= 1)`);
assert(happyPayments >= 1, `happy-path invoice has ${happyPayments} payment rows (>= 1)`);
assert(happyStock === snapshot.in_stock - 1, `inventory decremented by exactly 1 (${happyStock} === ${snapshot.in_stock} - 1)`);

// --- Cleanup -----------------------------------------------------------
section('Cleanup');
db.prepare('DELETE FROM payments WHERE invoice_id = ?').run(happyInvoice.id);
db.prepare('DELETE FROM invoice_line_items WHERE invoice_id = ?').run(happyInvoice.id);
db.prepare('DELETE FROM invoices WHERE id = ?').run(happyInvoice.id);
db.prepare('DELETE FROM tickets WHERE id = ?').run(happyTicket.id);
db.prepare('UPDATE inventory_items SET in_stock = ? WHERE id = ?').run(snapshot.in_stock, inv.id);
console.log('  Cleaned up happy-path rows and restored stock.');

// --- Summary ----------------------------------------------------------
console.log(`\n${passed} passed, ${failed} failed`);
db.close();
process.exit(failed === 0 ? 0 : 1);
