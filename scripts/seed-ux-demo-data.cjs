#!/usr/bin/env node

const path = require('node:path');
const Database = require('better-sqlite3');

const repoRoot = path.resolve(__dirname, '..');
const dbPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(repoRoot, 'packages/server/data/bizarre-crm.db');

const db = new Database(dbPath);
db.pragma('foreign_keys = ON');

const seedPrefix = 'UX-SEED';
const seedTag = 'ux-seed';

function money(value) {
  return Math.round(Number(value) * 100) / 100;
}

function isoDaysAgo(days, hour = 14) {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  d.setDate(d.getDate() - days);
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

function isoHoursFrom(hours) {
  const d = new Date();
  d.setMinutes(0, 0, 0);
  d.setHours(d.getHours() + hours);
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

function dateDaysFrom(days) {
  const d = new Date();
  d.setHours(12, 0, 0, 0);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

function getStatusId(name) {
  const row = db.prepare('SELECT id FROM ticket_statuses WHERE LOWER(name) = LOWER(?) LIMIT 1').get(name);
  if (!row) throw new Error(`Missing ticket status: ${name}`);
  return row.id;
}

function getDefaultStatusId() {
  const row = db.prepare('SELECT id FROM ticket_statuses ORDER BY is_default DESC, sort_order ASC, id ASC LIMIT 1').get();
  if (!row) throw new Error('No ticket statuses configured');
  return row.id;
}

function insertCustomer(customer) {
  const existing = db.prepare('SELECT id FROM customers WHERE email = ? AND source = ? LIMIT 1').get(customer.email, seedTag);
  if (existing) return existing.id;
  const info = db.prepare(`
    INSERT INTO customers (
      first_name, last_name, organization, email, phone, mobile, city, state, postcode,
      source, tags, email_opt_in, sms_opt_in, comments, created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, datetime('now'), datetime('now'))
  `).run(
    customer.first,
    customer.last,
    customer.organization ?? null,
    customer.email,
    customer.phone,
    customer.phone,
    customer.city ?? 'Denver',
    customer.state ?? 'CO',
    customer.postcode ?? '80202',
    seedTag,
    JSON.stringify([seedTag, 'demo']),
    customer.comments ?? 'UX demo customer. Safe to remove by rerunning the UX seed script.',
  );
  return Number(info.lastInsertRowid);
}

function insertInventory(item, taxClassId) {
  db.prepare(`
    INSERT INTO inventory_items (
      sku, upc, name, description, item_type, category, manufacturer, device_type,
      cost_price, retail_price, in_stock, reorder_level, desired_stock_level,
      tax_class_id, tax_inclusive, is_serialized, is_active, location, shelf, bin,
      is_reorderable, created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 1, ?, ?, ?, ?, datetime('now'), datetime('now'))
  `).run(
    item.sku,
    item.upc ?? null,
    item.name,
    item.description ?? null,
    item.itemType,
    item.category,
    item.manufacturer ?? null,
    item.deviceType ?? null,
    item.cost,
    item.price,
    item.stock,
    item.reorderLevel ?? 2,
    item.desiredStock ?? Math.max(item.stock, 6),
    item.taxable === false ? null : taxClassId,
    item.serialized ? 1 : 0,
    item.location ?? 'Front counter',
    item.shelf ?? 'A',
    item.bin ?? item.sku.replace(`${seedPrefix}-`, ''),
    item.reorderable ? 1 : 0,
  );
  return db.prepare('SELECT id FROM inventory_items WHERE sku = ?').get(item.sku).id;
}

function insertTicket(ticket, ctx) {
  const subtotal = money(ticket.price);
  const tax = ticket.taxable === false ? 0 : money(subtotal * ctx.taxRate);
  const total = money(subtotal + tax);
  const createdAt = isoDaysAgo(ticket.daysAgo, ticket.hour ?? 14);
  const statusId = ticket.statusName ? getStatusId(ticket.statusName) : getDefaultStatusId();
  const info = db.prepare(`
    INSERT INTO tickets (
      order_id, customer_id, status_id, assigned_to, subtotal, discount, total_tax, total,
      source, referral_source, labels, due_on, created_by, created_at, updated_at,
      repair_timer_running, repair_timer_started_at, priority
    )
    VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    ticket.orderId,
    ctx.customers[ticket.customerKey],
    statusId,
    ticket.assigned ? ctx.userId : null,
    subtotal,
    tax,
    total,
    seedTag,
    ticket.referral ?? 'Walk-in',
    JSON.stringify([seedTag, ticket.label ?? 'demo']),
    ticket.dueInDays == null ? null : dateDaysFrom(ticket.dueInDays),
    ctx.userId,
    createdAt,
    createdAt,
    ticket.timerRunning ? 1 : 0,
    ticket.timerRunning ? createdAt : null,
    ticket.priority ?? 'normal',
  );
  const ticketId = Number(info.lastInsertRowid);
  db.prepare(`
    INSERT INTO ticket_devices (
      ticket_id, device_name, device_type, imei, serial, color, network, status_id, assigned_to,
      price, tax_amount, tax_class_id, total, warranty, warranty_days, due_on, device_location,
      additional_notes, pre_conditions, post_conditions, service_name, created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    ticketId,
    ticket.device,
    ticket.deviceType,
    ticket.imei ?? null,
    ticket.serial ?? null,
    ticket.color ?? null,
    ticket.network ?? null,
    statusId,
    ticket.assigned ? ctx.userId : null,
    subtotal,
    tax,
    ticket.taxable === false ? null : ctx.taxClassId,
    total,
    ticket.warranty ? 1 : 0,
    ticket.warrantyDays ?? 90,
    ticket.dueInDays == null ? null : dateDaysFrom(ticket.dueInDays),
    ticket.location ?? 'Bench 1',
    ticket.notes,
    JSON.stringify(ticket.pre ?? { powers_on: true, screen_cracked: false }),
    JSON.stringify(ticket.post ?? {}),
    ticket.service,
    createdAt,
    createdAt,
  );
  return { id: ticketId, subtotal, tax, total, customerId: ctx.customers[ticket.customerKey], createdAt };
}

function insertInvoice(invoice, ctx) {
  const base = ctx.ticketRows[invoice.ticketKey] ?? null;
  const subtotal = money(invoice.subtotal ?? base?.subtotal ?? 0);
  const tax = money(invoice.tax ?? (subtotal * ctx.taxRate));
  const total = money(invoice.total ?? subtotal + tax);
  const paid = money(invoice.paid ?? 0);
  const due = invoice.status === 'void' ? 0 : money(Math.max(0, total - paid));
  const createdAt = isoDaysAgo(invoice.daysAgo, invoice.hour ?? 15);
  const info = db.prepare(`
    INSERT INTO invoices (
      order_id, ticket_id, customer_id, status, subtotal, discount, total_tax, total,
      amount_paid, amount_due, due_on, notes, created_by, created_at, updated_at, currency
    )
    VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'USD')
  `).run(
    invoice.orderId,
    base?.id ?? null,
    invoice.customerKey ? ctx.customers[invoice.customerKey] : base?.customerId ?? null,
    invoice.status,
    subtotal,
    tax,
    total,
    invoice.status === 'void' ? 0 : paid,
    due,
    invoice.dueInDays == null ? null : dateDaysFrom(invoice.dueInDays),
    invoice.notes,
    ctx.userId,
    createdAt,
    createdAt,
  );
  const invoiceId = Number(info.lastInsertRowid);
  if (base?.id) {
    db.prepare('UPDATE tickets SET invoice_id = ?, updated_at = datetime(\'now\') WHERE id = ?').run(invoiceId, base.id);
  }
  const lines = invoice.lines ?? [{ description: invoice.description ?? 'Repair service', quantity: 1, unitPrice: subtotal, inventorySku: null }];
  for (const line of lines) {
    const item = line.inventorySku ? ctx.inventory[line.inventorySku] : null;
    const quantity = Number(line.quantity ?? 1);
    const unit = money(line.unitPrice);
    const lineSubtotal = money(quantity * unit);
    const lineTax = money(line.tax ?? (line.taxable === false ? 0 : lineSubtotal * ctx.taxRate));
    const lineTotal = money(lineSubtotal + lineTax);
    db.prepare(`
      INSERT INTO invoice_line_items (
        invoice_id, inventory_item_id, description, quantity, unit_price, line_discount,
        tax_amount, tax_class_id, total, notes, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
    `).run(
      invoiceId,
      item?.id ?? null,
      line.description,
      quantity,
      unit,
      lineTax,
      line.taxable === false ? null : ctx.taxClassId,
      lineTotal,
      line.notes ?? null,
      createdAt,
      createdAt,
    );
  }
  for (const payment of invoice.payments ?? []) {
    db.prepare(`
      INSERT INTO payments (
        invoice_id, amount, method, method_detail, transaction_id, notes, user_id,
        created_at, updated_at, processor, reference, capture_state, currency
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'captured', 'USD')
    `).run(
      invoiceId,
      money(payment.amount),
      payment.method,
      payment.detail ?? null,
      payment.transactionId ?? `${seedPrefix}-TX-${invoiceId}-${payment.method.replace(/\s+/g, '').toUpperCase()}`,
      payment.notes ?? 'UX demo payment',
      ctx.userId,
      createdAt,
      createdAt,
      payment.processor ?? null,
      payment.reference ?? null,
    );
  }
  if (paid > 0 && invoice.status !== 'void') {
    db.prepare(`
      INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id, register_id, created_at, updated_at, currency)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'USD')
    `).run(invoiceId, base?.customerId ?? (invoice.customerKey ? ctx.customers[invoice.customerKey] : null), total, invoice.payments?.[0]?.method ?? 'Cash', ctx.userId, 'UX-DEMO-REGISTER', createdAt, createdAt);
  }
  return invoiceId;
}

const run = db.transaction(() => {
  const invoiceIds = db.prepare(`SELECT id FROM invoices WHERE order_id LIKE '${seedPrefix}-%'`).all().map((row) => row.id);
  const ticketIds = db.prepare(`SELECT id FROM tickets WHERE order_id LIKE '${seedPrefix}-%'`).all().map((row) => row.id);
  const customerIds = db.prepare(`SELECT id FROM customers WHERE source = ? OR tags LIKE ?`).all(seedTag, `%${seedTag}%`).map((row) => row.id);
  const inventoryIds = db.prepare(`SELECT id FROM inventory_items WHERE sku LIKE '${seedPrefix}-%'`).all().map((row) => row.id);

  if (invoiceIds.length) {
    const placeholders = invoiceIds.map(() => '?').join(',');
    db.prepare(`DELETE FROM payments WHERE invoice_id IN (${placeholders})`).run(...invoiceIds);
    db.prepare(`DELETE FROM pos_transactions WHERE invoice_id IN (${placeholders})`).run(...invoiceIds);
    db.prepare(`DELETE FROM invoice_line_items WHERE invoice_id IN (${placeholders})`).run(...invoiceIds);
    db.prepare(`UPDATE tickets SET invoice_id = NULL WHERE invoice_id IN (${placeholders})`).run(...invoiceIds);
    db.prepare(`DELETE FROM invoices WHERE id IN (${placeholders})`).run(...invoiceIds);
  }
  if (ticketIds.length) {
    const placeholders = ticketIds.map(() => '?').join(',');
    db.prepare(`DELETE FROM appointments WHERE ticket_id IN (${placeholders})`).run(...ticketIds);
    db.prepare(`DELETE FROM ticket_notes WHERE ticket_id IN (${placeholders})`).run(...ticketIds);
    db.prepare(`DELETE FROM ticket_devices WHERE ticket_id IN (${placeholders})`).run(...ticketIds);
    db.prepare(`DELETE FROM tickets WHERE id IN (${placeholders})`).run(...ticketIds);
  }
  if (inventoryIds.length) {
    const placeholders = inventoryIds.map(() => '?').join(',');
    db.prepare(`DELETE FROM stock_movements WHERE inventory_item_id IN (${placeholders})`).run(...inventoryIds);
    db.prepare(`DELETE FROM inventory_items WHERE id IN (${placeholders})`).run(...inventoryIds);
  }
  if (customerIds.length) {
    const placeholders = customerIds.map(() => '?').join(',');
    db.prepare(`DELETE FROM customers WHERE id IN (${placeholders})`).run(...customerIds);
  }

  const user = db.prepare(`
    SELECT id FROM users
    WHERE is_active = 1
    ORDER BY CASE WHEN role IN ('admin', 'owner', 'manager') THEN 0 ELSE 1 END, id ASC
    LIMIT 1
  `).get();
  if (!user) throw new Error('No active users found');

  const taxClass = db.prepare('SELECT id, rate FROM tax_classes WHERE is_default = 1 ORDER BY id ASC LIMIT 1').get()
    ?? db.prepare('SELECT id, rate FROM tax_classes ORDER BY id ASC LIMIT 1').get();
  if (!taxClass) throw new Error('No tax classes found');
  const taxRate = Number(taxClass.rate || 0) / 100;

  for (const [name, order] of [['Cash', 0], ['Credit Card', 1], ['Debit Card', 2], ['Store Credit', 3]]) {
    db.prepare('INSERT OR IGNORE INTO payment_methods (name, is_active, sort_order) VALUES (?, 1, ?)').run(name, order);
  }

  const customers = {
    alex: insertCustomer({ first: 'Alex', last: 'Demo', email: 'ux.alex.demo@example.com', phone: '3035551101', comments: 'Walk-in phone repair customer for UX demo data.' }),
    jamie: insertCustomer({ first: 'Jamie', last: 'Sample', email: 'ux.jamie.sample@example.com', phone: '3035551102', comments: 'Repeat repair customer for invoice and ticket examples.' }),
    robin: insertCustomer({ first: 'Robin', last: 'Test', email: 'ux.robin.test@example.com', phone: '3035551103', organization: 'Robin Test LLC', comments: 'Business customer with partial invoice balance.' }),
    morgan: insertCustomer({ first: 'Morgan', last: 'Example', email: 'ux.morgan.example@example.com', phone: '3035551104', comments: 'Cancelled repair example.' }),
    casey: insertCustomer({ first: 'Casey', last: 'Preview', email: 'ux.casey.preview@example.com', phone: '3035551105', comments: 'Pickup-ready repair example.' }),
    taylor: insertCustomer({ first: 'Taylor', last: 'Counter', email: 'ux.taylor.counter@example.com', phone: '3035551106', comments: 'POS product sale customer.' }),
  };

  const inventory = {};
  for (const item of [
    { sku: `${seedPrefix}-CASE-001`, upc: '811111000001', name: 'MagSafe clear case', description: 'Everyday accessory displayed in POS.', itemType: 'product', category: 'accessories', manufacturer: 'Bizarre Basics', cost: 8.5, price: 24.99, stock: 18, reorderLevel: 4, reorderable: true, shelf: 'A', bin: '01' },
    { sku: `${seedPrefix}-CHARGER-001`, upc: '811111000002', name: '30W USB-C fast charger', description: 'Counter-sale charger with healthy stock.', itemType: 'product', category: 'accessories', manufacturer: 'Bizarre Basics', cost: 11, price: 34.99, stock: 10, reorderLevel: 3, reorderable: true, shelf: 'A', bin: '02' },
    { sku: `${seedPrefix}-CABLE-001`, upc: '811111000003', name: 'USB-C to Lightning cable', description: 'Low-stock counter accessory.', itemType: 'product', category: 'accessories', manufacturer: 'Bizarre Basics', cost: 4.75, price: 14.99, stock: 2, reorderLevel: 5, reorderable: true, shelf: 'A', bin: '03' },
    { sku: `${seedPrefix}-PROTECT-001`, upc: '811111000004', name: 'Tempered glass install', description: 'Sellable service with no stock decrement.', itemType: 'service', category: 'services', manufacturer: 'In-house', cost: 3, price: 19.99, stock: 0, reorderLevel: 0, shelf: 'B', bin: '01' },
    { sku: `${seedPrefix}-DIAG-001`, upc: '811111000005', name: 'Diagnostic bench fee', description: 'POS service for intake and estimates.', itemType: 'service', category: 'labor', manufacturer: 'In-house', cost: 0, price: 39.99, stock: 0, reorderLevel: 0, shelf: 'B', bin: '02' },
    { sku: `${seedPrefix}-IP13-SCREEN`, upc: '811111000006', name: 'iPhone 13 screen assembly', description: 'Repair part visible in inventory, not a top-level POS service.', itemType: 'part', category: 'screens', manufacturer: 'Aftermarket', deviceType: 'phone', cost: 54, price: 119.99, stock: 7, reorderLevel: 2, reorderable: true, shelf: 'C', bin: '13' },
    { sku: `${seedPrefix}-S22-PORT`, upc: '811111000007', name: 'Galaxy S22 charge port flex', description: 'Repair part for waiting-parts examples.', itemType: 'part', category: 'charge ports', manufacturer: 'Aftermarket', deviceType: 'phone', cost: 18, price: 54.99, stock: 0, reorderLevel: 2, reorderable: true, shelf: 'C', bin: '22' },
  ]) {
    const id = insertInventory(item, taxClass.id);
    inventory[item.sku] = { id, ...item };
    db.prepare(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id, created_at, updated_at)
      VALUES (?, 'adjustment', ?, 'ux_seed', 'UX demo opening stock', ?, datetime('now'), datetime('now'))
    `).run(id, item.stock, user.id);
  }

  const ctx = { userId: user.id, taxClassId: taxClass.id, taxRate, customers, inventory, ticketRows: {} };
  const tickets = [
    { key: 'inspection', orderId: `${seedPrefix}-T001`, customerKey: 'alex', statusName: 'Waiting for inspection', device: 'iPhone 14 Pro', deviceType: 'phone', service: 'Back glass estimate', price: 0, taxable: false, dueInDays: 0, daysAgo: 0, notes: 'Fresh intake waiting for inspection.', label: 'intake', priority: 'normal' },
    { key: 'diagnosis', orderId: `${seedPrefix}-T002`, customerKey: 'jamie', statusName: 'Diagnosis - In progress', device: 'MacBook Air M2', deviceType: 'computer', service: 'No power diagnosis', price: 79.99, dueInDays: 1, daysAgo: 1, assigned: true, timerRunning: true, notes: 'Tech is actively diagnosing the board.', label: 'in-progress', priority: 'high' },
    { key: 'repairing', orderId: `${seedPrefix}-T003`, customerKey: 'robin', statusName: 'In Progress', device: 'iPad Pro 11', deviceType: 'tablet', service: 'Screen replacement', price: 249.99, dueInDays: 2, daysAgo: 2, assigned: true, notes: 'Repair is on bench with parts pulled.', label: 'in-progress' },
    { key: 'parts_order', orderId: `${seedPrefix}-T004`, customerKey: 'morgan', statusName: 'Waiting for Parts', device: 'Galaxy S22', deviceType: 'phone', service: 'Charge port replacement', price: 129.99, dueInDays: 4, daysAgo: 3, notes: 'Charge port flex is on order.', label: 'waiting-parts' },
    { key: 'pending_qc', orderId: `${seedPrefix}-T005`, customerKey: 'casey', statusName: 'Repaired - Pending QC', device: 'iPhone 13', deviceType: 'phone', service: 'Screen replacement', price: 169.99, dueInDays: -1, daysAgo: 5, assigned: true, notes: 'Repair complete, waiting on QC sign-off.', label: 'pending-qc', priority: 'high' },
    { key: 'qc_passed', orderId: `${seedPrefix}-T006`, customerKey: 'alex', statusName: 'Repaired - QC Passed', device: 'Pixel 7', deviceType: 'phone', service: 'Battery replacement', price: 119.99, dueInDays: 0, daysAgo: 4, assigned: true, notes: 'QC passed, ready for customer contact.', label: 'qc-passed' },
    { key: 'awaiting_payment', orderId: `${seedPrefix}-T007`, customerKey: 'jamie', statusName: 'Repaired - Waiting for payment', device: 'Nintendo Switch', deviceType: 'other', service: 'USB-C port replacement', price: 139.99, dueInDays: -2, daysAgo: 7, notes: 'Customer notified; awaiting payment.', label: 'payment' },
    { key: 'fixed', orderId: `${seedPrefix}-T008`, customerKey: 'casey', statusName: 'Repaired', device: 'Dell XPS 13', deviceType: 'computer', service: 'SSD replacement', price: 219.99, dueInDays: -3, daysAgo: 10, warranty: true, notes: 'Fixed and awaiting final pickup workflow.', label: 'fixed' },
    { key: 'picked_up', orderId: `${seedPrefix}-T009`, customerKey: 'taylor', statusName: 'Payment Received & Picked Up', device: 'Apple Watch Series 7', deviceType: 'watch', service: 'Battery replacement', price: 99.99, dueInDays: -6, daysAgo: 14, warranty: true, notes: 'Closed repair with paid invoice.', label: 'closed' },
    { key: 'cancelled', orderId: `${seedPrefix}-T010`, customerKey: 'morgan', statusName: 'Cancelled', device: 'Surface Laptop 4', deviceType: 'computer', service: 'Liquid damage repair', price: 0, taxable: false, dueInDays: null, daysAgo: 8, notes: 'Customer declined repair after estimate.', label: 'cancelled' },
    { key: 'ber', orderId: `${seedPrefix}-T011`, customerKey: 'robin', statusName: 'BER (Beyond Economical Repair)', device: 'iPhone XR', deviceType: 'phone', service: 'Board repair estimate', price: 0, taxable: false, dueInDays: null, daysAgo: 9, notes: 'Marked BER after inspection.', label: 'cancelled' },
    { key: 'approval', orderId: `${seedPrefix}-T012`, customerKey: 'alex', statusName: 'Approval required', device: 'MacBook Pro 16', deviceType: 'computer', service: 'Keyboard/top case quote', price: 379.99, dueInDays: 3, daysAgo: 2, notes: 'Waiting for customer approval on quote.', label: 'approval' },
  ];
  for (const ticket of tickets) {
    ctx.ticketRows[ticket.key] = insertTicket(ticket, ctx);
  }

  db.prepare(`
    INSERT INTO appointments (customer_id, ticket_id, title, start_time, end_time, assigned_to, status, notes, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'scheduled', ?, datetime('now'), datetime('now'))
  `).run(
    customers.casey,
    ctx.ticketRows.pending_qc.id,
    '[UX Seed] Pickup appointment - iPhone 13',
    isoHoursFrom(1),
    isoHoursFrom(2),
    user.id,
    'Pickup window for repaired iPhone 13.',
  );

  const invoices = [
    {
      ticketKey: 'picked_up',
      orderId: `${seedPrefix}-INV001`,
      status: 'paid',
      paid: ctx.ticketRows.picked_up.total,
      daysAgo: 13,
      dueInDays: -10,
      notes: 'Paid pickup repair invoice.',
      payments: [{ method: 'Credit Card', amount: ctx.ticketRows.picked_up.total, processor: 'demo-terminal', reference: 'APPROVED-001' }],
      lines: [{ description: 'Apple Watch battery replacement', quantity: 1, unitPrice: ctx.ticketRows.picked_up.subtotal }],
    },
    {
      ticketKey: 'awaiting_payment',
      orderId: `${seedPrefix}-INV002`,
      status: 'unpaid',
      paid: 0,
      daysAgo: 7,
      dueInDays: -2,
      notes: 'Overdue unpaid repair invoice.',
      lines: [{ description: 'Nintendo Switch USB-C port replacement', quantity: 1, unitPrice: ctx.ticketRows.awaiting_payment.subtotal }],
    },
    {
      ticketKey: 'repairing',
      orderId: `${seedPrefix}-INV003`,
      status: 'partial',
      paid: 100,
      daysAgo: 2,
      dueInDays: 5,
      notes: 'Partial deposit against active repair.',
      payments: [{ method: 'Cash', amount: 100, reference: 'DEPOSIT-003' }],
      lines: [{ description: 'iPad Pro screen replacement deposit invoice', quantity: 1, unitPrice: ctx.ticketRows.repairing.subtotal }],
    },
    {
      customerKey: 'taylor',
      orderId: `${seedPrefix}-INV004`,
      status: 'paid',
      subtotal: 59.98,
      paid: money(59.98 + 59.98 * taxRate),
      daysAgo: 0,
      dueInDays: 0,
      notes: 'Walk-in POS accessory sale.',
      payments: [{ method: 'Debit Card', amount: money(59.98 + 59.98 * taxRate), processor: 'demo-terminal', reference: 'APPROVED-004' }],
      lines: [
        { inventorySku: `${seedPrefix}-CASE-001`, description: 'MagSafe clear case', quantity: 1, unitPrice: 24.99 },
        { inventorySku: `${seedPrefix}-CHARGER-001`, description: '30W USB-C fast charger', quantity: 1, unitPrice: 34.99 },
      ],
    },
    {
      ticketKey: 'cancelled',
      orderId: `${seedPrefix}-INV005`,
      status: 'void',
      subtotal: 49.99,
      paid: 0,
      daysAgo: 8,
      dueInDays: -8,
      notes: 'Voided estimate fee after cancelled repair.',
      lines: [{ description: 'Liquid damage estimate fee', quantity: 1, unitPrice: 49.99 }],
    },
  ];
  for (const invoice of invoices) {
    insertInvoice(invoice, ctx);
  }
});

try {
  run();
  const summary = {
    customers: db.prepare('SELECT COUNT(*) AS n FROM customers WHERE source = ? OR tags LIKE ?').get(seedTag, `%${seedTag}%`).n,
    tickets: db.prepare(`SELECT COUNT(*) AS n FROM tickets WHERE order_id LIKE '${seedPrefix}-%'`).get().n,
    invoices: db.prepare(`SELECT COUNT(*) AS n FROM invoices WHERE order_id LIKE '${seedPrefix}-%'`).get().n,
    inventory: db.prepare(`SELECT COUNT(*) AS n FROM inventory_items WHERE sku LIKE '${seedPrefix}-%'`).get().n,
  };
  const statuses = db.prepare(`
    SELECT ts.name, COUNT(*) AS tickets
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.order_id LIKE '${seedPrefix}-%'
    GROUP BY ts.name
    ORDER BY MIN(ts.sort_order)
  `).all();
  const invoiceStatuses = db.prepare(`
    SELECT status, COUNT(*) AS invoices, ROUND(SUM(total), 2) AS total, ROUND(SUM(amount_due), 2) AS due
    FROM invoices
    WHERE order_id LIKE '${seedPrefix}-%'
    GROUP BY status
    ORDER BY status
  `).all();
  console.log(`Seeded UX demo data into ${dbPath}`);
  console.table(summary);
  console.table(statuses);
  console.table(invoiceStatuses);
} finally {
  db.close();
}
