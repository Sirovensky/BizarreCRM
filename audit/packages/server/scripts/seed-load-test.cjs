/**
 * Seed realistic data into the bizarreelectronics tenant DB for load testing.
 * Creates 500 customers, 800 tickets with devices/parts, 200 invoices, 100 inventory items.
 */
const Database = require('better-sqlite3');
const crypto = require('crypto');
const path = require('path');

const db = new Database(path.join(__dirname, '..', 'data', 'tenants', 'bizarreelectronics.db'));
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');

function now() {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}
function randomDate(daysBack) {
  const d = new Date(Date.now() - Math.random() * daysBack * 86400000);
  return d.toISOString().replace('T', ' ').substring(0, 19);
}
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

const firstNames = ['John','Jane','Mike','Sarah','Chris','Emma','David','Lisa','James','Amy','Robert','Emily','Tom','Laura','Brian','Rachel','Alex','Nicole','Kevin','Megan'];
const lastNames = ['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Wilson','Moore','Taylor','Anderson','Thomas','Jackson','White','Harris','Martin','Lee','Clark','Lewis'];
const devicesList = ['iPhone 15 Pro','iPhone 14','iPhone 13','Samsung S24','Samsung S23','iPad Pro 12.9','iPad Air','MacBook Pro','Google Pixel 8','OnePlus 12'];
const servicesList = ['Screen Replacement','Battery Replacement','Charging Port Repair','Water Damage Repair','Back Glass Replacement','Camera Repair','Speaker Repair','Motherboard Repair'];
const partNames = ['LCD Assembly','Battery Cell','Charging Flex','Adhesive Kit','Pentalobe Screws','Back Glass Panel','Camera Module','Speaker Unit'];

console.log('Seeding load test data...');

const seedAll = db.transaction(() => {
  // --- Customers (500) ---
  console.log('  Creating 500 customers...');
  const insertCust = db.prepare(`
    INSERT INTO customers (first_name, last_name, email, phone, mobile, organization, address1, city, state, postcode, tags, source, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?, ?)
  `);
  for (let i = 0; i < 500; i++) {
    const fn = pick(firstNames);
    const ln = pick(lastNames);
    const created = randomDate(365);
    insertCust.run(fn, ln, `${fn.toLowerCase()}.${ln.toLowerCase()}${i}@test.com`,
      `+1${String(2000000000 + i).padStart(10,'0')}`,
      `+1${String(3000000000 + i).padStart(10,'0')}`,
      i % 10 === 0 ? `${ln} Electronics` : null,
      `${100 + i} Main St`, 'Tampa', 'FL', `3360${String(i % 100).padStart(2,'0')}`,
      pick(['walk-in','phone','online','referral']), created, created);
  }

  // --- Inventory Items (100) ---
  console.log('  Creating 100 inventory items...');
  const insertInv = db.prepare(`
    INSERT INTO inventory_items (name, sku, category, in_stock, cost_price, retail_price, reorder_level, is_active, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
  `);
  for (let i = 0; i < 100; i++) {
    const name = `${pick(partNames)} - ${pick(devicesList).split(' ')[0]} ${i}`;
    insertInv.run(name, `PART-${String(i).padStart(4,'0')}`, pick(['parts','accessories','screens']),
      Math.floor(Math.random() * 50) + 1, (Math.random() * 30 + 5).toFixed(2), (Math.random() * 80 + 20).toFixed(2),
      5, now(), now());
  }

  // --- Tickets (800) with devices and parts ---
  console.log('  Creating 800 tickets with devices and parts...');
  const statuses = db.prepare('SELECT id FROM ticket_statuses').all().map(s => s.id);
  const seqRow = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_sequence'").get();
  let seq = seqRow ? parseInt(seqRow.value) || 0 : 0;

  const insertTicket = db.prepare(`
    INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, subtotal, discount, total_tax, total, source, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
  `);
  const insertDevice = db.prepare(`
    INSERT INTO ticket_devices (ticket_id, device_name, device_type, imei, serial, service_name, price, line_discount, tax_amount, tax_class_id, tax_inclusive, total, status_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertPart = db.prepare(`
    INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  const insertNote = db.prepare(`
    INSERT INTO ticket_notes (ticket_id, user_id, type, content, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const insertHistory = db.prepare(`
    INSERT INTO ticket_history (ticket_id, user_id, action, description, created_at)
    VALUES (?, ?, ?, ?, ?)
  `);

  const invItems = db.prepare('SELECT id, retail_price AS price FROM inventory_items LIMIT 100').all();

  for (let i = 0; i < 800; i++) {
    seq++;
    const orderId = `T-${String(seq).padStart(5, '0')}`;
    const custId = Math.floor(Math.random() * 500) + 1;
    const statusId = pick(statuses);
    const price = Math.floor(Math.random() * 200) + 50;
    const tax = Math.round(price * 0.075 * 100) / 100;
    const total = price + tax;
    const created = randomDate(180);

    const tRes = insertTicket.run(orderId, custId, statusId, 1, price, 0, tax, total, pick(['walk-in','phone','online']), created, created);
    const ticketId = Number(tRes.lastInsertRowid);

    // 1-2 devices per ticket
    const numDevices = Math.random() > 0.7 ? 2 : 1;
    for (let d = 0; d < numDevices; d++) {
      const dev = pick(devicesList);
      const svc = pick(servicesList);
      const devPrice = Math.floor(Math.random() * 150) + 30;
      const devTax = Math.round(devPrice * 0.075 * 100) / 100;
      const dRes = insertDevice.run(ticketId, dev, 'phone',
        `${350000000000000 + Math.floor(Math.random() * 999999999)}`,
        `SN${crypto.randomBytes(4).toString('hex').toUpperCase()}`,
        svc, devPrice, 0, devTax, 1, 0, devPrice + devTax, statusId, created, created);
      const deviceId = Number(dRes.lastInsertRowid);

      // 0-3 parts per device
      const numParts = Math.floor(Math.random() * 4);
      for (let p = 0; p < numParts; p++) {
        const inv = pick(invItems);
        insertPart.run(deviceId, inv.id, 1, inv.price, pick(['available','ordered','received']), created, created);
      }
    }

    // 1-3 notes per ticket
    const numNotes = Math.floor(Math.random() * 3) + 1;
    for (let n = 0; n < numNotes; n++) {
      insertNote.run(ticketId, 1, pick(['internal','diagnostic']),
        `Test note ${n+1} for ticket ${orderId}. ${crypto.randomBytes(20).toString('hex')}`, created, created);
    }

    // 2-5 history entries
    const numHist = Math.floor(Math.random() * 4) + 2;
    for (let h = 0; h < numHist; h++) {
      insertHistory.run(ticketId, 1, pick(['created','status_changed','note_added','updated']),
        `History entry ${h+1}`, created);
    }
  }

  // Update ticket sequence
  db.prepare("INSERT OR REPLACE INTO store_config (key, value) VALUES ('ticket_sequence', ?)").run(String(seq));

  // --- Invoices (200) ---
  console.log('  Creating 200 invoices...');
  const insertInvoice = db.prepare(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, total_tax, total, amount_paid, amount_due, status, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
  `);
  const insertLineItem = db.prepare(`
    INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, total, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  const insertPayment = db.prepare(`
    INSERT INTO payments (invoice_id, amount, method, user_id, created_at, updated_at)
    VALUES (?, ?, ?, 1, ?, ?)
  `);

  let invSeq = 0;
  // Use first 200 ticket IDs (unique constraint on ticket_id)
  const ticketIdsForInv = db.prepare('SELECT id, customer_id FROM tickets ORDER BY id LIMIT 200').all();
  for (let i = 0; i < ticketIdsForInv.length; i++) {
    invSeq++;
    const custId = ticketIdsForInv[i].customer_id;
    const ticketId = ticketIdsForInv[i].id;
    const subtotal = Math.floor(Math.random() * 300) + 50;
    const tax = Math.round(subtotal * 0.075 * 100) / 100;
    const total = subtotal + tax;
    const isPaid = Math.random() > 0.3;
    const created = randomDate(180);

    const iRes = insertInvoice.run(`INV-${String(invSeq).padStart(5,'0')}`, custId, ticketId,
      subtotal, tax, total, isPaid ? total : 0, isPaid ? 0 : total, isPaid ? 'paid' : 'unpaid', created, created);
    const invoiceId = Number(iRes.lastInsertRowid);

    insertLineItem.run(invoiceId, pick(servicesList), 1, subtotal, subtotal, created, created);

    if (isPaid) {
      insertPayment.run(invoiceId, total, pick(['cash','credit_card','debit']), created, created);
    }
  }

  console.log('  Done seeding!');
});

seedAll();
console.log(`Seeded: 500 customers, 800 tickets, 200 invoices, 100 inventory items`);
db.close();
