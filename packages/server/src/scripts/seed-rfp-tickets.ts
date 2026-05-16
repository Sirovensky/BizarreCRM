/**
 * Seed "Ready for pickup" tickets for POS testing.
 *
 * Inserts N tickets at status_id=17 ("Repaired - Waiting for payment"),
 * each with one device line, against existing seeded customers. Matches
 * the POS gate's RFP filter (isReadyPickupStatus → "waiting for payment").
 *
 * Usage:
 *   cd packages/server
 *   npx tsx src/scripts/seed-rfp-tickets.ts            # default 5 tickets
 *   npx tsx src/scripts/seed-rfp-tickets.ts 10         # 10 tickets
 *   npx tsx src/scripts/seed-rfp-tickets.ts 5 --reset  # wipe prior RFP-SEED rows first
 *
 * Tickets are tagged with order_id prefix `RFP-SEED-` so a `--reset` run
 * cleans them up without touching real data.
 */
import path from 'path';
import { fileURLToPath } from 'url';
import Database from 'better-sqlite3';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const count = Math.max(1, Math.min(50, Number(process.argv[2] ?? 5)));
const reset = process.argv.includes('--reset');

const dbPath = path.resolve(__dirname, '../../data/bizarre-crm.db');
const db = new Database(dbPath);

const RFP_STATUS_ID = 17; // "Repaired - Waiting for payment"
const ORDER_PREFIX = 'RFP-SEED-';

const DEVICES = [
  { name: 'iPhone 15 Pro', service: 'Screen replacement', price: 249.99 },
  { name: 'iPhone 14', service: 'Battery replacement', price: 89.99 },
  { name: 'Samsung Galaxy S23', service: 'Back glass repair', price: 179.99 },
  { name: 'Google Pixel 8', service: 'Charging port repair', price: 119.99 },
  { name: 'iPad Pro 11', service: 'Screen replacement', price: 299.99 },
  { name: 'iPhone 13', service: 'Water damage diagnosis', price: 69.99 },
  { name: 'OnePlus 11', service: 'Speaker replacement', price: 99.99 },
  { name: 'iPhone 12 Pro Max', service: 'Camera lens repair', price: 159.99 },
  { name: 'Pixel 7', service: 'Battery replacement', price: 99.99 },
  { name: 'Galaxy Note 20', service: 'Screen replacement', price: 219.99 },
];

const customers = db.prepare(
  "SELECT id, first_name, last_name FROM customers WHERE is_deleted = 0 AND id > 1 ORDER BY RANDOM() LIMIT 20",
).all() as Array<{ id: number; first_name: string; last_name: string }>;

if (customers.length === 0) {
  console.error('No customers (other than walk-in) seeded. Run the base seeder first.');
  process.exit(1);
}

const status = db.prepare('SELECT id, name FROM ticket_statuses WHERE id = ?').get(RFP_STATUS_ID) as
  | { id: number; name: string }
  | undefined;
if (!status) {
  console.error(`Status id ${RFP_STATUS_ID} not found. Re-seed ticket_statuses first.`);
  process.exit(1);
}

if (reset) {
  const wipe = db.transaction(() => {
    const rows = db.prepare(`SELECT id FROM tickets WHERE order_id LIKE '${ORDER_PREFIX}%'`).all() as Array<{ id: number }>;
    for (const r of rows) {
      db.prepare('DELETE FROM ticket_devices WHERE ticket_id = ?').run(r.id);
      db.prepare('DELETE FROM tickets WHERE id = ?').run(r.id);
    }
    return rows.length;
  });
  const n = wipe();
  console.log(`wiped ${n} prior ${ORDER_PREFIX}* tickets`);
}

const currentMaxRow = db.prepare(
  `SELECT COALESCE(MAX(CAST(SUBSTR(order_id, ?) AS INTEGER)), 0) as n FROM tickets WHERE order_id LIKE ?`,
).get(ORDER_PREFIX.length + 1, `${ORDER_PREFIX}%`) as { n: number };
let nextSeq = currentMaxRow.n + 1;

const insertTicket = db.prepare(`
  INSERT INTO tickets (
    order_id, customer_id, status_id, subtotal, discount, total_tax, total,
    is_deleted, created_by, created_at, updated_at, is_pinned, repair_timer_running,
    stall_followup_sent, is_warranty, is_layaway, sla_breached, priority
  ) VALUES (
    @order_id, @customer_id, @status_id, @subtotal, 0, 0, @total,
    0, 1, @created_at, @updated_at, 0, 0,
    0, 0, 0, 0, 'normal'
  )
`);

const insertDevice = db.prepare(`
  INSERT INTO ticket_devices (
    ticket_id, device_name, device_type, status_id, service_name,
    price, line_discount, tax_amount, tax_inclusive, total,
    warranty, warranty_days, created_at, updated_at
  ) VALUES (
    @ticket_id, @device_name, @device_type, @status_id, @service_name,
    @price, 0, 0, 0, @price,
    0, 0, @created_at, @updated_at
  )
`);

const insertAll = db.transaction((n: number) => {
  const inserted: Array<{ orderId: string; customer: string; device: string; price: number }> = [];
  for (let i = 0; i < n; i++) {
    const cust = customers[i % customers.length]!;
    const device = DEVICES[Math.floor(Math.random() * DEVICES.length)]!;
    const orderId = `${ORDER_PREFIX}T${String(nextSeq).padStart(3, '0')}`;
    nextSeq++;
    // Stagger updated_at so the "Waiting Xh AM" labels read distinctly.
    const ageHours = Math.floor(Math.random() * 12) + 1;
    const stamp = new Date(Date.now() - ageHours * 60 * 60 * 1000)
      .toISOString()
      .replace('T', ' ')
      .slice(0, 19);
    const info = insertTicket.run({
      order_id: orderId,
      customer_id: cust.id,
      status_id: RFP_STATUS_ID,
      subtotal: device.price,
      total: device.price,
      created_at: stamp,
      updated_at: stamp,
    });
    insertDevice.run({
      ticket_id: info.lastInsertRowid as number,
      device_name: device.name,
      device_type: 'Phone',
      status_id: RFP_STATUS_ID,
      service_name: device.service,
      price: device.price,
      created_at: stamp,
      updated_at: stamp,
    });
    inserted.push({
      orderId,
      customer: `${cust.first_name} ${cust.last_name}`,
      device: `${device.name} · ${device.service}`,
      price: device.price,
    });
  }
  return inserted;
});

const created = insertAll(count);
console.log(`seeded ${created.length} RFP tickets (status: "${status.name}"):`);
for (const t of created) {
  console.log(`  ${t.orderId}  ${t.customer.padEnd(24)}  ${t.device}  $${t.price.toFixed(2)}`);
}
console.log(`\nRefresh POS gate to see them in "Ready for pickup".`);
console.log(`Clean up later: npx tsx src/scripts/seed-rfp-tickets.ts ${count} --reset`);
