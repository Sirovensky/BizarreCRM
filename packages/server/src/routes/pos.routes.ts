import { Router } from 'express';
import crypto from 'crypto';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { validatePrice } from '../utils/validate.js';
import { generateOrderId } from '../utils/format.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { roundCurrency } from '../utils/currency.js';

const router = Router();

// GET /pos/products - products/services available for POS
router.get('/products', (req, res) => {
  const { keyword, category, item_type } = req.query as Record<string, string>;

  let where = 'WHERE is_active = 1 AND (item_type = \'product\' OR item_type = \'service\')';
  const params: any[] = [];

  if (item_type) { where += ' AND item_type = ?'; params.push(item_type); }
  if (category) { where += ' AND category = ?'; params.push(category); }
  if (keyword) {
    where += ' AND (name LIKE ? OR sku LIKE ? OR upc LIKE ?)';
    const k = `%${keyword}%`;
    params.push(k, k, k);
  }

  const items = db.prepare(`
    SELECT id, name, item_type, category, retail_price, cost_price, in_stock, sku, upc, image_url,
           tax_class_id, tax_inclusive
    FROM inventory_items ${where}
    ORDER BY category, name
  `).all(...params);

  // Get categories
  const categories = db.prepare(`
    SELECT DISTINCT category FROM inventory_items
    WHERE is_active = 1 AND category IS NOT NULL
    ORDER BY category
  `).all();

  res.json({ success: true, data: { items, categories: categories.map((c: any) => c.category) } });
});

// GET /pos/register - current register state
router.get('/register', (_req, res) => {
  const cashIn = (db.prepare('SELECT COALESCE(SUM(amount),0) as t FROM cash_register WHERE type = \'cash_in\' AND DATE(created_at) = DATE(\'now\')').get() as any).t;
  const cashOut = (db.prepare('SELECT COALESCE(SUM(amount),0) as t FROM cash_register WHERE type = \'cash_out\' AND DATE(created_at) = DATE(\'now\')').get() as any).t;
  const cashPayments = (db.prepare('SELECT COALESCE(SUM(p.amount),0) as t FROM payments p JOIN invoices inv ON inv.id = p.invoice_id WHERE p.method = \'cash\' AND DATE(p.created_at) = DATE(\'now\')').get() as any).t;
  const recentEntries = db.prepare(`
    SELECT cr.*, u.first_name || ' ' || u.last_name as user_name
    FROM cash_register cr LEFT JOIN users u ON u.id = cr.user_id
    WHERE DATE(cr.created_at) = DATE('now')
    ORDER BY cr.created_at DESC LIMIT 20
  `).all();

  res.json({
    success: true,
    data: {
      cash_in: cashIn,
      cash_out: cashOut,
      cash_sales: cashPayments,
      net: cashIn + cashPayments - cashOut,
      entries: recentEntries,
    },
  });
});

// POST /pos/cash-in
router.post('/cash-in', (req, res) => {
  const { amount, reason } = req.body;
  if (!amount || parseFloat(amount) <= 0) throw new AppError('Valid amount required', 400);
  const result = db.prepare('INSERT INTO cash_register (type, amount, reason, user_id) VALUES (\'cash_in\', ?, ?, ?)').run(parseFloat(amount), reason || null, req.user!.id);
  const entry = db.prepare('SELECT * FROM cash_register WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { entry } });
});

// POST /pos/cash-out
router.post('/cash-out', (req, res) => {
  const { amount, reason } = req.body;
  if (!amount || parseFloat(amount) <= 0) throw new AppError('Valid amount required', 400);
  const result = db.prepare('INSERT INTO cash_register (type, amount, reason, user_id) VALUES (\'cash_out\', ?, ?, ?)').run(parseFloat(amount), reason || null, req.user!.id);
  const entry = db.prepare('SELECT * FROM cash_register WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { entry } });
});

// POST /pos/transaction - complete a POS sale
router.post('/transaction', (req, res) => {
  const {
    customer_id, items = [], payment_method = 'cash', payment_amount,
    notes, discount = 0, tip = 0,
  } = req.body;

  if (!items.length) throw new AppError('No items in cart', 400);
  if (payment_amount !== undefined && payment_amount !== null) {
    const pa = parseFloat(payment_amount);
    if (isNaN(pa) || pa < 0) throw new AppError('Payment amount must be non-negative', 400);
  }
  if (discount < 0) throw new AppError('Discount must be non-negative', 400);

  const processTransaction = db.transaction(() => {
    // Calculate totals
    let subtotal = 0;
    let total_tax = 0;
    const lineItems: any[] = [];

    for (const item of items) {
      // Validate quantity
      const qty = parseInt(item.quantity, 10);
      if (isNaN(qty) || qty < 1 || qty > 100000) throw new AppError('Invalid quantity (1-100000)', 400);
      item.quantity = qty;

      const inv = db.prepare('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1').get(item.inventory_item_id) as any;
      if (!inv) throw new AppError(`Item ${item.inventory_item_id} not found`, 404);

      // Check stock for non-services
      if (inv.item_type !== 'service' && inv.in_stock < item.quantity) {
        throw new AppError(`Insufficient stock for ${inv.name}`, 400);
      }

      const taxClass = inv.tax_class_id ? db.prepare('SELECT rate FROM tax_classes WHERE id = ?').get(inv.tax_class_id) as any : null;
      const lineSubtotal = item.quantity * (item.unit_price ?? inv.retail_price);
      const taxRate = taxClass ? taxClass.rate / 100 : 0;
      const lineTax = inv.tax_inclusive ? 0 : lineSubtotal * taxRate;

      subtotal += lineSubtotal;
      total_tax += lineTax;
      lineItems.push({ ...item, inv, lineSubtotal, lineTax, unit_price: item.unit_price ?? inv.retail_price });
    }

    const tipAmount = Math.max(0, parseFloat(String(tip)) || 0);
    const total = subtotal + total_tax - (discount || 0) + tipAmount;
    // Get next order_id from existing order_ids (safe across deletions)
    const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices").get() as any;
    const orderId = generateOrderId('INV', seqRow.next_num);

    // Create invoice
    const invoiceResult = db.prepare(`
      INSERT INTO invoices (order_id, customer_id, subtotal, discount, total_tax, total, amount_paid, amount_due, status, notes, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(orderId, customer_id || null, subtotal, discount, total_tax, total,
      parseFloat(payment_amount || total), Math.max(0, total - parseFloat(payment_amount || total)),
      parseFloat(payment_amount || total) >= total ? 'paid' : 'partial',
      notes || null, req.user!.id);

    const invoiceId = invoiceResult.lastInsertRowid;

    // Add line items and deduct stock
    for (const item of lineItems) {
      db.prepare(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(invoiceId, item.inventory_item_id, item.inv.name, item.quantity,
        item.unit_price, item.lineTax, item.lineSubtotal + item.lineTax);

      if (item.inv.item_type !== 'service') {
        db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = datetime(\'now\') WHERE id = ?').run(item.quantity, item.inventory_item_id);
        db.prepare(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id)
          VALUES (?, 'sale', ?, 'invoice', ?, 'POS Sale', ?)
        `).run(item.inventory_item_id, -item.quantity, invoiceId, req.user!.id);
      }
    }

    // Record payment
    db.prepare(`
      INSERT INTO payments (invoice_id, amount, method, user_id)
      VALUES (?, ?, ?, ?)
    `).run(invoiceId, parseFloat(payment_amount || total), payment_method, req.user!.id);

    // POS transaction record
    db.prepare(`
      INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id, tip)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(invoiceId, customer_id || null, total, payment_method, req.user!.id, tipAmount);

    const invoice = db.prepare(`
      SELECT inv.*, c.first_name, c.last_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `).get(invoiceId);

    return { invoice, tip: tipAmount, change: Math.max(0, parseFloat(payment_amount || total.toString()) - total) };
  });

  const result = processTransaction();
  res.status(201).json({ success: true, data: result });
});

// GET /pos/transactions - recent POS transactions
router.get('/transactions', (req, res) => {
  const { from_date, to_date } = req.query as Record<string, string>;
  let where = 'WHERE 1=1';
  const params: any[] = [];
  if (from_date) { where += ' AND DATE(pt.created_at) >= ?'; params.push(from_date); }
  if (to_date) { where += ' AND DATE(pt.created_at) <= ?'; params.push(to_date); }

  const transactions = db.prepare(`
    SELECT pt.*, inv.order_id, c.first_name, c.last_name,
           u.first_name || ' ' || u.last_name as cashier_name
    FROM pos_transactions pt
    LEFT JOIN invoices inv ON inv.id = pt.invoice_id
    LEFT JOIN customers c ON c.id = pt.customer_id
    LEFT JOIN users u ON u.id = pt.user_id
    ${where}
    ORDER BY pt.created_at DESC
    LIMIT 100
  `).all(...params);

  res.json({ success: true, data: { transactions } });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function calcTax(price: number, taxClassId: number | null, taxInclusive: boolean): number {
  if (!taxClassId) return 0;
  const tc = db.prepare('SELECT rate FROM tax_classes WHERE id = ?').get(taxClassId) as AnyRow | undefined;
  if (!tc) return 0;
  const rate = tc.rate / 100;
  if (taxInclusive) return roundCurrency(price - price / (1 + rate));
  return roundCurrency(price * rate);
}

// POST /pos/checkout-with-ticket - Create ticket + invoice + optional payment in one transaction
router.post('/checkout-with-ticket', (req, res) => {
  const userId = req.user!.id;
  const {
    customer_id,
    mode,
    existing_ticket_id,
    ticket: ticketData,
    product_items = [],
    misc_items = [],
    payment_method = 'cash',
    payment_amount,
    signature_file,
  } = req.body;

  if (!mode || !['create_ticket', 'checkout'].includes(mode)) {
    throw new AppError('mode must be "create_ticket" or "checkout"', 400);
  }

  // Verify customer exists (optional — walk-in sales allowed)
  let customerId: number | null = customer_id || null;
  if (customerId) {
    const customer = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customerId) as AnyRow | undefined;
    if (!customer) throw new AppError('Customer not found', 404);
  }

  // Get default tax class for taxable items
  const defaultTaxClass = db.prepare("SELECT id, rate FROM tax_classes WHERE name LIKE '%Colorado%' OR rate = 8.865 LIMIT 1").get() as AnyRow | undefined;
  const defaultTaxClassId = defaultTaxClass?.id ?? null;

  const processCheckout = db.transaction(() => {
    let ticketId: number | null = existing_ticket_id ? Number(existing_ticket_id) : null;
    let ticketOrderId: string | null = null;

    // If checking out an existing ticket, verify it exists and get its order_id
    if (ticketId) {
      const existing = db.prepare('SELECT id, order_id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
      if (!existing) throw new AppError('Ticket not found', 404);
      ticketOrderId = existing.order_id;
      if (!customerId && existing.customer_id) customerId = existing.customer_id;
    }

    // ---- 1. Create ticket if devices are provided (skip if reusing existing) ----
    if (!ticketId && ticketData?.devices && Array.isArray(ticketData.devices) && ticketData.devices.length > 0) {
      // Get default status
      const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get() as AnyRow | undefined;
      const statusId = defaultStatus?.id ?? 1;

      // Next ticket order_id
      const ticketSeq = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 3) AS INTEGER)), 0) + 1 as next_num FROM tickets").get() as AnyRow;
      ticketOrderId = generateOrderId('T', ticketSeq.next_num);
      const trackingToken = crypto.randomUUID().split('-')[0];

      // Auto-calculate due date if not provided (same logic as tickets.routes.ts F16)
      let dueOn = ticketData.due_on ?? ticketData.due_date ?? null;
      if (!dueOn) {
        const dueCfg = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_due_value'").get() as AnyRow | undefined;
        const dueUnit = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_due_unit'").get() as AnyRow | undefined;
        if (dueCfg?.value && parseInt(dueCfg.value) > 0) {
          const val = parseInt(dueCfg.value);
          const unit = dueUnit?.value || 'days';
          const d = new Date();
          if (unit === 'hours') d.setHours(d.getHours() + val);
          else if (unit === 'weeks') d.setDate(d.getDate() + val * 7);
          else d.setDate(d.getDate() + val); // days
          dueOn = d.toISOString().replace('T', ' ').substring(0, 19);
        }
      }

      const ticketResult = db.prepare(`
        INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                             source, labels, due_on, created_by, tracking_token, signature_file, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        ticketOrderId,
        customerId,
        statusId,
        ticketData.assigned_to ?? null,
        ticketData.discount ?? 0,
        ticketData.discount_reason ?? null,
        ticketData.source ?? 'Walk-in',
        JSON.stringify(ticketData.labels ?? []),
        dueOn,
        userId,
        trackingToken,
        signature_file ?? null,
        now(),
        now(),
      );

      ticketId = Number(ticketResult.lastInsertRowid);

      // Insert devices
      for (const dev of ticketData.devices) {
        const devicePrice = dev.price ?? dev.labor_price ?? 0;
        const lineDiscount = dev.line_discount ?? 0;
        // Repairs (labor) default to non-taxable; explicit taxable flag overrides
        const taxClassId = dev.tax_class_id ?? (dev.taxable === true ? defaultTaxClassId : null);
        const taxAmount = calcTax(devicePrice - lineDiscount, taxClassId, dev.tax_inclusive ?? false);
        const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

        const devResult = db.prepare(`
          INSERT INTO ticket_devices (ticket_id, device_name, device_type, imei, serial, security_code,
                                      color, network, status_id, assigned_to, service_id, service_name, price, line_discount,
                                      tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                      due_on, device_location, additional_notes, pre_conditions, post_conditions,
                                      created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          ticketId,
          dev.device_name ?? '',
          dev.device_type ?? null,
          dev.imei ?? null,
          dev.serial ?? null,
          dev.security_code ?? null,
          dev.color ?? null,
          dev.network ?? null,
          statusId,
          dev.assigned_to ?? ticketData.assigned_to ?? null,
          dev.service_id ?? dev.repair_service_id ?? null,
          dev.service_name ?? null,
          devicePrice,
          lineDiscount,
          taxAmount,
          taxClassId,
          dev.tax_inclusive ? 1 : 0,
          deviceTotal,
          dev.warranty ? 1 : 0,
          dev.warranty_days ?? 0,
          dev.due_on ?? null,
          dev.device_location ?? null,
          dev.additional_notes ?? null,
          JSON.stringify(dev.pre_conditions ?? []),
          JSON.stringify(dev.post_conditions ?? []),
          now(),
          now(),
        );

        const deviceId = Number(devResult.lastInsertRowid);

        // Insert parts
        if (dev.parts && Array.isArray(dev.parts)) {
          for (const part of dev.parts) {
            db.prepare(`
              INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price,
                                               status, warranty, serial, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            `).run(
              deviceId,
              part.inventory_item_id,
              part.quantity ?? 1,
              part.price ?? 0,
              part.status ?? 'available',
              part.warranty ? 1 : 0,
              part.serial ?? null,
              now(),
              now(),
            );
          }
        }
      }

      // Recalculate ticket totals
      const devices = db.prepare('SELECT price, line_discount, tax_amount FROM ticket_devices WHERE ticket_id = ?').all(ticketId) as AnyRow[];
      const parts = db.prepare(`
        SELECT tdp.quantity, tdp.price FROM ticket_device_parts tdp
        JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?
      `).all(ticketId) as AnyRow[];

      let ticketSubtotal = 0;
      let ticketTax = 0;
      for (const d of devices) { ticketSubtotal += (d.price - d.line_discount); ticketTax += d.tax_amount; }
      for (const p of parts) { ticketSubtotal += p.quantity * p.price; }
      const ticketDiscount = ticketData.discount ?? 0;
      const ticketTotal = roundCurrency(ticketSubtotal - ticketDiscount + ticketTax);

      db.prepare('UPDATE tickets SET subtotal = ?, total_tax = ?, total = ?, updated_at = ? WHERE id = ?')
        .run(roundCurrency(ticketSubtotal), roundCurrency(ticketTax), ticketTotal, now(), ticketId);

      // History entry
      db.prepare(`
        INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(ticketId, userId, 'created', 'Ticket created via Unified POS', null, null);

      // Internal notes
      if (ticketData.internal_notes) {
        db.prepare(`
          INSERT INTO ticket_notes (ticket_id, type, content, created_by, created_at)
          VALUES (?, 'internal', ?, ?, ?)
        `).run(ticketId, ticketData.internal_notes, userId, now());
      }
    }

    // ---- 2. Build invoice line items from ALL sources ----
    let invoiceSubtotal = 0;
    let invoiceTax = 0;
    const invoiceLines: {
      inventory_item_id: number | null;
      description: string;
      quantity: number;
      unit_price: number;
      tax_amount: number;
      total: number;
    }[] = [];

    // 2a. Repair device lines (labor + parts from ticket)
    if (ticketId) {
      const tDevices = db.prepare(`
        SELECT td.id, td.device_name, td.price, td.line_discount, td.tax_amount, td.total, td.service_id
        FROM ticket_devices td WHERE td.ticket_id = ?
      `).all(ticketId) as AnyRow[];

      for (const td of tDevices) {
        const laborNet = (td.price ?? 0) - (td.line_discount ?? 0);
        invoiceSubtotal += laborNet;
        invoiceTax += td.tax_amount ?? 0;
        invoiceLines.push({
          inventory_item_id: td.service_id ?? null,
          description: `Repair: ${td.device_name}`,
          quantity: 1,
          unit_price: laborNet,
          tax_amount: td.tax_amount ?? 0,
          total: td.total ?? laborNet,
        });

        // Parts for this device
        const tParts = db.prepare('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?').all(td.id) as AnyRow[];
        for (const tp of tParts) {
          const partTotal = tp.quantity * tp.price;
          invoiceSubtotal += partTotal;
          // Parts tax: use default tax class
          const partTax = tp.price > 0 ? calcTax(partTotal, defaultTaxClassId, false) : 0;
          invoiceTax += partTax;
          invoiceLines.push({
            inventory_item_id: tp.inventory_item_id,
            description: `Part for ${td.device_name}`,
            quantity: tp.quantity,
            unit_price: tp.price,
            tax_amount: partTax,
            total: partTotal + partTax,
          });
        }
      }
    }

    // 2b. Product items
    for (const item of product_items) {
      const inv = db.prepare('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1').get(item.inventory_item_id) as AnyRow | undefined;
      if (!inv) throw new AppError(`Product ${item.inventory_item_id} not found`, 404);

      if (inv.item_type !== 'service' && inv.in_stock < item.quantity) {
        throw new AppError(`Insufficient stock for ${inv.name}`, 400);
      }

      const unitPrice = item.unit_price ?? inv.retail_price;
      const lineSubtotal = item.quantity * unitPrice;
      const taxClassId = inv.tax_class_id ?? null;
      const lineTax = inv.tax_inclusive ? 0 : calcTax(lineSubtotal, taxClassId, false);

      invoiceSubtotal += lineSubtotal;
      invoiceTax += lineTax;
      invoiceLines.push({
        inventory_item_id: item.inventory_item_id,
        description: inv.name,
        quantity: item.quantity,
        unit_price: unitPrice,
        tax_amount: lineTax,
        total: lineSubtotal + lineTax,
      });
    }

    // 2c. Misc items
    for (const item of misc_items) {
      const itemPrice = item.price ?? item.unit_price ?? 0;
      const lineSubtotal = itemPrice * (item.quantity ?? 1);
      const lineTax = item.taxable ? calcTax(lineSubtotal, defaultTaxClassId, false) : 0;

      invoiceSubtotal += lineSubtotal;
      invoiceTax += lineTax;
      invoiceLines.push({
        inventory_item_id: null,
        description: item.name || 'Miscellaneous',
        quantity: item.quantity ?? 1,
        unit_price: itemPrice,
        tax_amount: lineTax,
        total: lineSubtotal + lineTax,
      });
    }

    // ---- 3. Create or update invoice ----
    const discount = ticketData?.discount ?? 0;
    const invoiceTotal = roundCurrency(invoiceSubtotal + invoiceTax - discount);
    const isPaid = mode === 'checkout';
    const paidAmount = isPaid ? parseFloat(payment_amount ?? invoiceTotal) : 0;

    // Check if invoice already exists for this ticket (created during check-in)
    let invoiceId: number;
    const existingInvoice = ticketId
      ? db.prepare('SELECT id, order_id FROM invoices WHERE ticket_id = ?').get(ticketId) as AnyRow | undefined
      : undefined;

    if (existingInvoice) {
      // UPDATE existing invoice with current totals and payment status
      invoiceId = existingInvoice.id;
      db.prepare(`
        UPDATE invoices SET
          customer_id = ?, subtotal = ?, discount = ?, total_tax = ?, total = ?,
          amount_paid = ?, amount_due = ?, status = ?, updated_at = ?
        WHERE id = ?
      `).run(
        customerId,
        roundCurrency(invoiceSubtotal),
        discount,
        roundCurrency(invoiceTax),
        invoiceTotal,
        isPaid ? Math.min(paidAmount, invoiceTotal) : 0,
        isPaid ? Math.max(0, invoiceTotal - paidAmount) : invoiceTotal,
        isPaid ? (paidAmount >= invoiceTotal ? 'paid' : 'partial') : 'unpaid',
        now(),
        invoiceId,
      );

      // Replace line items (delete old, insert new)
      db.prepare('DELETE FROM invoice_line_items WHERE invoice_id = ?').run(invoiceId);
    } else {
      // CREATE new invoice
      const invSeq = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices").get() as AnyRow;
      const invoiceOrderId = generateOrderId('INV', invSeq.next_num);

      const invoiceResult = db.prepare(`
        INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
                              amount_paid, amount_due, status, created_by, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        invoiceOrderId,
        customerId,
        ticketId,
        roundCurrency(invoiceSubtotal),
        discount,
        roundCurrency(invoiceTax),
        invoiceTotal,
        isPaid ? Math.min(paidAmount, invoiceTotal) : 0,
        isPaid ? Math.max(0, invoiceTotal - paidAmount) : invoiceTotal,
        isPaid ? (paidAmount >= invoiceTotal ? 'paid' : 'partial') : 'unpaid',
        userId,
        now(),
        now(),
      );

      invoiceId = Number(invoiceResult.lastInsertRowid);
    }

    // Insert invoice line items (fresh for both create and update)
    for (const line of invoiceLines) {
      db.prepare(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(invoiceId, line.inventory_item_id, line.description, line.quantity, line.unit_price, line.tax_amount, line.total);
    }

    // Link invoice to ticket (so ticket detail can find it)
    if (ticketId) {
      db.prepare('UPDATE tickets SET invoice_id = ?, updated_at = ? WHERE id = ?')
        .run(invoiceId, now(), ticketId);
    }

    // ---- 4. If checkout mode: payment + stock deductions + POS transaction ----
    let change = 0;
    if (isPaid) {
      // Record payment
      db.prepare(`
        INSERT INTO payments (invoice_id, amount, method, user_id, created_at)
        VALUES (?, ?, ?, ?, ?)
      `).run(invoiceId, paidAmount, payment_method, userId, now());

      change = Math.max(0, paidAmount - invoiceTotal);

      // Deduct stock for product items
      for (const item of product_items) {
        const inv = db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(item.inventory_item_id) as AnyRow;
        if (inv && inv.item_type !== 'service') {
          db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?')
            .run(item.quantity, now(), item.inventory_item_id);
          db.prepare(`
            INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
            VALUES (?, 'sale', ?, 'invoice', ?, 'POS checkout', ?, ?, ?)
          `).run(item.inventory_item_id, -item.quantity, invoiceId, userId, now(), now());
        }
      }

      // POS transaction record
      db.prepare(`
        INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id)
        VALUES (?, ?, ?, ?, ?)
      `).run(invoiceId, customerId, invoiceTotal, payment_method, userId);
    }

    // ---- 4b. If checkout mode with a ticket: close the ticket ----
    if (isPaid && ticketId) {
      const closedStatus = db.prepare(
        'SELECT id FROM ticket_statuses WHERE is_closed = 1 ORDER BY sort_order ASC LIMIT 1'
      ).get() as AnyRow | undefined;
      if (closedStatus) {
        db.prepare("UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?")
          .run(closedStatus.id, now(), ticketId);
        // Record in ticket history
        const closedName = (db.prepare('SELECT name FROM ticket_statuses WHERE id = ?').get(closedStatus.id) as AnyRow)?.name || 'Closed';
        db.prepare(`
          INSERT INTO ticket_history (ticket_id, action, old_value, new_value, user_id, created_at)
          VALUES (?, 'status_change', '', ?, ?, ?)
        `).run(ticketId, closedName, userId, now());
      }
    }

    // ---- 5. Fetch created records for response ----
    const invoice = db.prepare(`
      SELECT inv.*, c.first_name, c.last_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `).get(invoiceId);

    let ticket: any = null;
    if (ticketId) {
      ticket = db.prepare(`
        SELECT t.*, ts.name AS status_name, ts.color AS status_color,
               c.first_name AS c_first_name, c.last_name AS c_last_name
        FROM tickets t
        LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        LEFT JOIN customers c ON c.id = t.customer_id
        WHERE t.id = ?
      `).get(ticketId);
      // Include devices for success screen summary
      if (ticket) {
        ticket.devices = db.prepare(`
          SELECT td.id, td.device_name, td.device_type, td.service_id,
                 COALESCE(td.service_name, ii.name) AS service_name
          FROM ticket_devices td
          LEFT JOIN inventory_items ii ON ii.id = td.service_id
          WHERE td.ticket_id = ?
        `).all(ticketId);
      }
    }

    return { ticket, invoice, change };
  });

  const result = processCheckout();

  // Broadcast ticket creation if a ticket was created
  if (result.ticket) {
    broadcast(WS_EVENTS.TICKET_CREATED, result.ticket);

    // Create in-app notification for all active users
    const customerName = result.ticket.c_first_name
      ? `${result.ticket.c_first_name} ${result.ticket.c_last_name || ''}`.trim()
      : 'Walk-in';
    const deviceSummary = result.ticket.devices?.map((d: any) => d.device_name).filter(Boolean).join(', ') || 'Repair';
    const notifTitle = `New Ticket ${result.ticket.order_id}`;
    const notifMessage = `${customerName} — ${deviceSummary}`;
    const activeUsers = db.prepare("SELECT id FROM users WHERE is_active = 1").all() as { id: number }[];
    for (const u of activeUsers) {
      db.prepare(`
        INSERT INTO notifications (user_id, type, title, message, entity_type, entity_id, created_at, updated_at)
        VALUES (?, 'ticket_created', ?, ?, 'ticket', ?, datetime('now'), datetime('now'))
      `).run(u.id, notifTitle, notifMessage, result.ticket.id);
    }
  }

  res.status(201).json({ success: true, data: result });
});

export default router;
