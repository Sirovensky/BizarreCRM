import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { validatePrice } from '../utils/validate.js';
import { generateOrderId } from '../utils/format.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { roundCurrency } from '../utils/currency.js';
import { idempotent } from '../middleware/idempotency.js';
import { config } from '../config.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// GET /pos/products - products/services available for POS
router.get('/products', async (req, res) => {
  const adb = req.asyncDb;
  const { keyword, category, item_type } = req.query as Record<string, string>;

  let where = 'WHERE is_active = 1 AND (item_type = \'product\' OR item_type = \'service\')';
  const params: any[] = [];

  // SW-D12: Filter categories based on POS show toggles
  const getToggle = async (key: string) => {
    const row = await adb.get<any>("SELECT value FROM store_config WHERE key = ?", key);
    return row?.value === '0' || row?.value === 'false' ? false : true; // default: show
  };

  const [showBundles, showDevices, showServices, showLabor, showAccessories, showMisc] = await Promise.all([
    getToggle('pos_show_bundles'),
    getToggle('pos_show_devices'),
    getToggle('pos_show_services'),
    getToggle('pos_show_labor'),
    getToggle('pos_show_accessories'),
    getToggle('pos_show_misc'),
  ]);

  const hiddenCategories: string[] = [];
  if (!showBundles) hiddenCategories.push('bundle', 'bundles');
  if (!showDevices) hiddenCategories.push('device', 'devices');
  if (!showServices) hiddenCategories.push('service', 'services');
  if (!showLabor) hiddenCategories.push('labor');
  if (!showAccessories) hiddenCategories.push('accessory', 'accessories');
  if (!showMisc) hiddenCategories.push('misc', 'miscellaneous');

  if (hiddenCategories.length > 0) {
    where += ' AND (LOWER(category) NOT IN (' + hiddenCategories.map(() => '?').join(',') + ') OR category IS NULL)';
    params.push(...hiddenCategories);
  }

  if (item_type) { where += ' AND item_type = ?'; params.push(item_type); }
  if (category) { where += ' AND category = ?'; params.push(category); }
  if (keyword) {
    where += ' AND (name LIKE ? OR sku LIKE ? OR upc LIKE ?)';
    const k = `%${keyword}%`;
    params.push(k, k, k);
  }

  // SW-D12: Optionally hide cost_price column
  const showCostPrice = await getToggle('pos_show_cost_price');

  const [items, categories] = await Promise.all([
    adb.all<any>(`
      SELECT id, name, item_type, category, retail_price, ${showCostPrice ? 'cost_price,' : ''} in_stock, sku, upc, image_url,
             tax_class_id, tax_inclusive
      FROM inventory_items ${where}
      ORDER BY category, name
    `, ...params),
    adb.all<any>(`
      SELECT DISTINCT category FROM inventory_items
      WHERE is_active = 1 AND category IS NOT NULL
      ORDER BY category
    `),
  ]);

  // If cost_price hidden, ensure it's not in the response
  const finalItems = showCostPrice ? items : items.map((item: any) => {
    const { cost_price, ...rest } = item;
    return rest;
  });

  res.json({ success: true, data: { items: finalItems, categories: categories.map((c: any) => c.category) } });
});

// GET /pos/register - current register state
router.get('/register', async (req, res) => {
  const adb = req.asyncDb;
  const [cashInRow, cashOutRow, cashPaymentsRow, recentEntries] = await Promise.all([
    adb.get<any>('SELECT COALESCE(SUM(amount),0) as t FROM cash_register WHERE type = \'cash_in\' AND DATE(created_at) = DATE(\'now\')'),
    adb.get<any>('SELECT COALESCE(SUM(amount),0) as t FROM cash_register WHERE type = \'cash_out\' AND DATE(created_at) = DATE(\'now\')'),
    adb.get<any>('SELECT COALESCE(SUM(p.amount),0) as t FROM payments p JOIN invoices inv ON inv.id = p.invoice_id WHERE p.method = \'cash\' AND DATE(p.created_at) = DATE(\'now\')'),
    adb.all<any>(`
      SELECT cr.*, u.first_name || ' ' || u.last_name as user_name
      FROM cash_register cr LEFT JOIN users u ON u.id = cr.user_id
      WHERE DATE(cr.created_at) = DATE('now')
      ORDER BY cr.created_at DESC LIMIT 20
    `),
  ]);

  const cashIn = cashInRow.t;
  const cashOut = cashOutRow.t;
  const cashPayments = cashPaymentsRow.t;

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
router.post('/cash-in', async (req, res) => {
  const adb = req.asyncDb;
  const { amount, reason } = req.body;
  if (!amount || parseFloat(amount) <= 0) throw new AppError('Valid amount required', 400);
  // V5: POS cash-in bounds check
  if (parseFloat(amount) > 50_000) throw new AppError('Cash-in amount cannot exceed $50,000', 400);
  const result = await adb.run('INSERT INTO cash_register (type, amount, reason, user_id) VALUES (\'cash_in\', ?, ?, ?)', parseFloat(amount), reason || null, req.user!.id);
  const entry = await adb.get<any>('SELECT * FROM cash_register WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { entry } });
});

// POST /pos/cash-out
router.post('/cash-out', async (req, res) => {
  const adb = req.asyncDb;
  const { amount, reason } = req.body;
  if (!amount || parseFloat(amount) <= 0) throw new AppError('Valid amount required', 400);
  // V5: POS cash-out bounds check
  if (parseFloat(amount) > 50_000) throw new AppError('Cash-out amount cannot exceed $50,000', 400);
  const result = await adb.run('INSERT INTO cash_register (type, amount, reason, user_id) VALUES (\'cash_out\', ?, ?, ?)', parseFloat(amount), reason || null, req.user!.id);
  const entry = await adb.get<any>('SELECT * FROM cash_register WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { entry } });
});

// POST /pos/transaction - complete a POS sale
router.post('/transaction', idempotent, async (req, res) => {
  const adb = req.asyncDb;
  const {
    customer_id, items = [], payment_method = 'cash', payment_amount,
    payments: splitPayments,
    notes, discount = 0, tip = 0,
  } = req.body;

  if (!items.length) throw new AppError('No items in cart', 400);
  if (payment_amount !== undefined && payment_amount !== null) {
    const pa = parseFloat(payment_amount);
    if (isNaN(pa) || pa < 0) throw new AppError('Payment amount must be non-negative', 400);
  }
  if (discount < 0) throw new AppError('Discount must be non-negative', 400);

  // Normalize payments: support both single payment_method and split payments array
  const normalizedPayments: { method: string; amount: number }[] = [];
  if (Array.isArray(splitPayments) && splitPayments.length > 0) {
    for (const sp of splitPayments) {
      if (!sp.method || typeof sp.method !== 'string') throw new AppError('Each payment must have a method', 400);
      const amt = parseFloat(sp.amount);
      if (isNaN(amt) || amt <= 0) throw new AppError('Each payment amount must be positive', 400);
      const validSplitMethod = await adb.get<any>('SELECT id FROM payment_methods WHERE name = ? AND is_active = 1', sp.method);
      if (!validSplitMethod) throw new AppError(`Invalid payment method: ${sp.method}`, 400);
      normalizedPayments.push({ method: sp.method, amount: amt });
    }
  } else {
    // Legacy single payment mode
    // Validate payment_method against active payment methods
    const validMethod = await adb.get<any>('SELECT id FROM payment_methods WHERE name = ? AND is_active = 1', payment_method);
    if (!validMethod) throw new AppError(`Invalid payment method: ${payment_method}`, 400);
  }

  // Calculate totals (reads can happen before the write transaction)
  let subtotal = 0;
  let total_tax = 0;
  const lineItems: any[] = [];

  for (const item of items) {
    // Validate quantity
    const qty = parseInt(item.quantity, 10);
    if (isNaN(qty) || qty < 1 || qty > 100000) throw new AppError('Invalid quantity (1-100000)', 400);
    item.quantity = qty;

    const inv = await adb.get<any>('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1', item.inventory_item_id);
    if (!inv) throw new AppError(`Item ${item.inventory_item_id} not found`, 404);

    // Validate unit_price is non-negative when provided
    if (item.unit_price !== undefined && item.unit_price !== null) {
      const up = parseFloat(item.unit_price);
      if (isNaN(up) || up < 0) throw new AppError('unit_price must be non-negative', 400);
      item.unit_price = up;
    }

    // Check stock for non-services
    if (inv.item_type !== 'service' && inv.in_stock < item.quantity) {
      throw new AppError(`Insufficient stock for ${inv.name}`, 400);
    }

    const taxClass = inv.tax_class_id ? await adb.get<any>('SELECT rate FROM tax_classes WHERE id = ?', inv.tax_class_id) : null;
    const lineSubtotal = item.quantity * (item.unit_price ?? inv.retail_price);
    const taxRate = taxClass ? taxClass.rate / 100 : 0;
    const lineTax = inv.tax_inclusive ? 0 : lineSubtotal * taxRate;

    subtotal += lineSubtotal;
    total_tax += lineTax;
    lineItems.push({ ...item, inv, lineSubtotal, lineTax, unit_price: item.unit_price ?? inv.retail_price });
  }

  const tipAmount = Math.max(0, parseFloat(String(tip)) || 0);
  if (!isFinite(tipAmount) || tipAmount > 999999) throw new AppError('Tip must be a finite number and at most $999,999', 400);
  if ((discount || 0) > subtotal + total_tax) throw new AppError('Discount cannot exceed subtotal + tax', 400);
  const total = subtotal + total_tax - (discount || 0) + tipAmount;
  // Get next order_id from existing order_ids (safe across deletions)
  const seqRow = await adb.get<any>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices");
  const orderId = generateOrderId('INV', seqRow!.next_num);

  // Build all write queries for atomic transaction
  const txQueries: Array<{ sql: string; params?: unknown[] }> = [];

  // Create invoice
  txQueries.push({
    sql: `INSERT INTO invoices (order_id, customer_id, subtotal, discount, total_tax, total, amount_paid, amount_due, status, notes, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    params: [orderId, customer_id || null, subtotal, discount, total_tax, total,
      parseFloat(payment_amount || total), Math.max(0, total - parseFloat(payment_amount || total)),
      parseFloat(payment_amount || total) >= total ? 'paid' : 'partial',
      notes || null, req.user!.id],
  });

  const txResults = await adb.transaction(txQueries);
  const invoiceId = txResults[0].lastInsertRowid;

  // Add line items and deduct stock
  for (const item of lineItems) {
    await adb.run(`
      INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `, invoiceId, item.inventory_item_id, item.inv.name, item.quantity,
      item.unit_price, item.lineTax, item.lineSubtotal + item.lineTax);

    if (item.inv.item_type !== 'service') {
      await adb.run('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = datetime(\'now\') WHERE id = ?', item.quantity, item.inventory_item_id);
      await adb.run(`
        INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id)
        VALUES (?, 'sale', ?, 'invoice', ?, 'POS Sale', ?)
      `, item.inventory_item_id, -item.quantity, invoiceId, req.user!.id);
    }
  }

  // Record payment(s)
  if (normalizedPayments.length > 0) {
    // Split payment mode
    for (const sp of normalizedPayments) {
      await adb.run(`
        INSERT INTO payments (invoice_id, amount, method, user_id)
        VALUES (?, ?, ?, ?)
      `, invoiceId, sp.amount, sp.method, req.user!.id);
    }
    const totalPaid = normalizedPayments.reduce((sum, sp) => sum + sp.amount, 0);
    // POS transaction record (use first payment method for summary)
    await adb.run(`
      INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id, tip)
      VALUES (?, ?, ?, ?, ?, ?)
    `, invoiceId, customer_id || null, total, normalizedPayments.map(p => p.method).join('+'), req.user!.id, tipAmount);

    const invoice = await adb.get<any>(`
      SELECT inv.*, c.first_name, c.last_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `, invoiceId);

    res.status(201).json({ success: true, data: { invoice, tip: tipAmount, change: Math.max(0, totalPaid - total) } });
  } else {
    // Legacy single payment mode
    await adb.run(`
      INSERT INTO payments (invoice_id, amount, method, user_id)
      VALUES (?, ?, ?, ?)
    `, invoiceId, parseFloat(payment_amount || total), payment_method, req.user!.id);

    // POS transaction record
    await adb.run(`
      INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id, tip)
      VALUES (?, ?, ?, ?, ?, ?)
    `, invoiceId, customer_id || null, total, payment_method, req.user!.id, tipAmount);

    const invoice = await adb.get<any>(`
      SELECT inv.*, c.first_name, c.last_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `, invoiceId);

    res.status(201).json({ success: true, data: { invoice, tip: tipAmount, change: Math.max(0, parseFloat(payment_amount || total.toString()) - total) } });
  }
});

// GET /pos/transactions - recent POS transactions
router.get('/transactions', async (req, res) => {
  const adb = req.asyncDb;
  const { from_date, to_date } = req.query as Record<string, string>;
  let where = 'WHERE 1=1';
  const params: any[] = [];
  if (from_date) { where += ' AND DATE(pt.created_at) >= ?'; params.push(from_date); }
  if (to_date) { where += ' AND DATE(pt.created_at) <= ?'; params.push(to_date); }

  const transactions = await adb.all<any>(`
    SELECT pt.*, inv.order_id, c.first_name, c.last_name,
           u.first_name || ' ' || u.last_name as cashier_name
    FROM pos_transactions pt
    LEFT JOIN invoices inv ON inv.id = pt.invoice_id
    LEFT JOIN customers c ON c.id = pt.customer_id
    LEFT JOIN users u ON u.id = pt.user_id
    ${where}
    ORDER BY pt.created_at DESC
    LIMIT 100
  `, ...params);

  res.json({ success: true, data: { transactions } });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

async function calcTaxAsync(adb: AsyncDb, price: number, taxClassId: number | null, taxInclusive: boolean): Promise<number> {
  if (!taxClassId) return 0;
  const tc = await adb.get<AnyRow>('SELECT rate FROM tax_classes WHERE id = ?', taxClassId);
  if (!tc) return 0;
  const rate = tc.rate / 100;
  if (taxInclusive) return roundCurrency(price - price / (1 + rate));
  return roundCurrency(price * rate);
}

// POST /pos/checkout-with-ticket - Create ticket + invoice + optional payment in one transaction
router.post('/checkout-with-ticket', idempotent, async (req, res) => {
  const adb = req.asyncDb;
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
    payments: splitPayments,
    signature_file,
  } = req.body;

  if (!mode || !['create_ticket', 'checkout'].includes(mode)) {
    throw new AppError('mode must be "create_ticket" or "checkout"', 400);
  }

  // SW-D13: Require referral source if setting enabled
  // Pre-transaction async reads
  const [requireReferral, customerRow, defaultTaxClass, membershipEnabled, customerMembership] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'pos_require_referral'"),
    customer_id ? adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customer_id) : Promise.resolve(undefined),
    adb.get<AnyRow>("SELECT id, rate FROM tax_classes WHERE name LIKE '%Colorado%' OR rate = 8.865 LIMIT 1"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'membership_enabled'"),
    customer_id ? adb.get<AnyRow>(`
      SELECT cs.status, mt.discount_pct, mt.discount_applies_to, mt.name AS tier_name
      FROM customer_subscriptions cs
      JOIN membership_tiers mt ON mt.id = cs.tier_id
      WHERE cs.customer_id = ? AND cs.status = 'active'
      ORDER BY cs.created_at DESC LIMIT 1
    `, customer_id) : Promise.resolve(undefined),
  ]);

  if ((requireReferral?.value === '1' || requireReferral?.value === 'true') && customer_id && !ticketData?.referral_source) {
    throw new AppError('Referral source is required', 400);
  }

  // Verify customer exists (optional — walk-in sales allowed)
  let customerId: number | null = customer_id || null;
  if (customerId) {
    if (!customerRow) throw new AppError('Customer not found', 404);
  }

  // Get default tax class for taxable items
  const defaultTaxClassId = defaultTaxClass?.id ?? null;

  let ticketId: number | null = existing_ticket_id ? Number(existing_ticket_id) : null;
  let ticketOrderId: string | null = null;

  // If checking out an existing ticket, verify it exists and get its order_id
  if (ticketId) {
    const existing = await adb.get<AnyRow>('SELECT id, order_id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
    if (!existing) throw new AppError('Ticket not found', 404);
    ticketOrderId = existing.order_id;
    if (!customerId && existing.customer_id) customerId = existing.customer_id;
  }

  // ---- 1. Create ticket if devices are provided (skip if reusing existing) ----
  let tierReservationCommitted = false;
  if (!ticketId && ticketData?.devices && Array.isArray(ticketData.devices) && ticketData.devices.length > 0) {
    // Tier: atomic monthly ticket limit check (check + pre-increment in one transaction)
    // Free plans cap maxTicketsMonth; Pro plans set it to null (unlimited).
    const tierReservationTenantId = req.tenantId;
    if (config.multiTenant && tierReservationTenantId && req.tenantLimits?.maxTicketsMonth != null) {
      const { getMasterDb } = await import('../db/master-connection.js');
      const masterDb = getMasterDb();
      if (masterDb) {
        const month = new Date().toISOString().slice(0, 7); // YYYY-MM
        const limit = req.tenantLimits.maxTicketsMonth;

        const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
          const usage = masterDb.prepare(
            'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
          ).get(tierReservationTenantId, month) as { tickets_created: number } | undefined;
          const current = usage?.tickets_created ?? 0;
          if (current >= limit) {
            return { allowed: false, current };
          }
          masterDb.prepare(`
            INSERT INTO tenant_usage (tenant_id, month, tickets_created)
            VALUES (?, ?, 1)
            ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
          `).run(tierReservationTenantId, month);
          return { allowed: true, current: current + 1 };
        })();

        if (!reservation.allowed) {
          res.status(403).json({
            success: false,
            upgrade_required: true,
            feature: 'ticket_limit',
            message: `Monthly ticket limit reached (${reservation.current}/${limit}). Upgrade to Pro for unlimited tickets.`,
            current: reservation.current,
            limit,
          });
          return;
        }
        tierReservationCommitted = true;
      }
    }

    // Get default status
    const defaultStatus = await adb.get<AnyRow>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
    const statusId = defaultStatus?.id ?? 1;

    // Next ticket order_id
    const ticketSeq = await adb.get<AnyRow>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 3) AS INTEGER)), 0) + 1 as next_num FROM tickets");
    ticketOrderId = generateOrderId('T', ticketSeq!.next_num);
    const trackingToken = crypto.randomUUID().split('-')[0];

    // Auto-calculate due date if not provided (same logic as tickets.routes.ts F16)
    let dueOn = ticketData.due_on ?? ticketData.due_date ?? null;
    if (!dueOn) {
      const [dueCfg, dueUnit] = await Promise.all([
        adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_due_value'"),
        adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_due_unit'"),
      ]);
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

    const ticketResult = await adb.run(`
      INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                           source, labels, due_on, created_by, tracking_token, signature_file, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
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
      const taxAmount = await calcTaxAsync(adb, devicePrice - lineDiscount, taxClassId, dev.tax_inclusive ?? false);
      const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

      // SW-D11: Auto-fill default warranty, respecting unit setting
      let warrantyDays = dev.warranty_days;
      if (warrantyDays === undefined || warrantyDays === null) {
        const [wVal, wUnit] = await Promise.all([
          adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'repair_default_warranty_value'"),
          adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'repair_default_warranty_unit'"),
        ]);
        const rawVal = wVal?.value ? parseInt(wVal.value) : 0;
        warrantyDays = wUnit?.value === 'months' ? rawVal * 30 : rawVal;
      }

      const devResult = await adb.run(`
        INSERT INTO ticket_devices (ticket_id, device_name, device_type, imei, serial, security_code,
                                    color, network, status_id, assigned_to, service_id, service_name, price, line_discount,
                                    tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                    due_on, device_location, additional_notes, pre_conditions, post_conditions,
                                    created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
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
        warrantyDays,
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
          await adb.run(`
            INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price,
                                             status, warranty, serial, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          `,
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
    const [devices, parts] = await Promise.all([
      adb.all<AnyRow>('SELECT price, line_discount, tax_amount FROM ticket_devices WHERE ticket_id = ?', ticketId),
      adb.all<AnyRow>(`
        SELECT tdp.quantity, tdp.price FROM ticket_device_parts tdp
        JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?
      `, ticketId),
    ]);

    let ticketSubtotal = 0;
    let ticketTax = 0;
    for (const d of devices) { ticketSubtotal += (d.price - d.line_discount); ticketTax += d.tax_amount; }
    for (const p of parts) { ticketSubtotal += p.quantity * p.price; }
    const ticketDiscount = ticketData.discount ?? 0;
    const ticketTotal = roundCurrency(ticketSubtotal - ticketDiscount + ticketTax);

    await adb.run('UPDATE tickets SET subtotal = ?, total_tax = ?, total = ?, updated_at = ? WHERE id = ?',
      roundCurrency(ticketSubtotal), roundCurrency(ticketTax), ticketTotal, now(), ticketId);

    // History entry
    await adb.run(`
      INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
      VALUES (?, ?, ?, ?, ?, ?)
    `, ticketId, userId, 'created', 'Ticket created via Unified POS', null, null);

    // Internal notes
    if (ticketData.internal_notes) {
      await adb.run(`
        INSERT INTO ticket_notes (ticket_id, type, content, created_by, created_at)
        VALUES (?, 'internal', ?, ?, ?)
      `, ticketId, ticketData.internal_notes, userId, now());
    }
  }
  void tierReservationCommitted;

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
    const tDevices = await adb.all<AnyRow>(`
      SELECT td.id, td.device_name, td.price, td.line_discount, td.tax_amount, td.total, td.service_id
      FROM ticket_devices td WHERE td.ticket_id = ?
    `, ticketId);

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
      const tParts = await adb.all<AnyRow>('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?', td.id);
      for (const tp of tParts) {
        const partTotal = tp.quantity * tp.price;
        invoiceSubtotal += partTotal;
        // Parts tax: use default tax class
        const partTax = tp.price > 0 ? await calcTaxAsync(adb, partTotal, defaultTaxClassId, false) : 0;
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
    // Validate quantity
    const qty = parseInt(item.quantity, 10);
    if (isNaN(qty) || qty < 1 || qty > 100000) throw new AppError('Invalid product item quantity (1-100000)', 400);
    item.quantity = qty;

    const inv = await adb.get<AnyRow>('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1', item.inventory_item_id);
    if (!inv) throw new AppError(`Product ${item.inventory_item_id} not found`, 404);

    if (inv.item_type !== 'service' && inv.in_stock < item.quantity) {
      throw new AppError(`Insufficient stock for ${inv.name}`, 400);
    }

    // Validate unit_price is non-negative when provided
    if (item.unit_price !== undefined && item.unit_price !== null) {
      const up = parseFloat(item.unit_price);
      if (isNaN(up) || up < 0) throw new AppError('unit_price must be non-negative', 400);
      item.unit_price = up;
    }

    const unitPrice = item.unit_price ?? inv.retail_price;
    const lineSubtotal = item.quantity * unitPrice;
    const taxClassId = inv.tax_class_id ?? null;
    const lineTax = inv.tax_inclusive ? 0 : await calcTaxAsync(adb, lineSubtotal, taxClassId, false);

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
    const rawPrice = item.price ?? item.unit_price ?? 0;
    const itemPrice = parseFloat(rawPrice);
    if (isNaN(itemPrice) || itemPrice < 0) throw new AppError('Misc item price must be non-negative', 400);
    // Validate quantity
    const miscQty = parseInt(item.quantity ?? 1, 10);
    if (isNaN(miscQty) || miscQty < 1) throw new AppError('Misc item quantity must be at least 1', 400);
    item.quantity = miscQty;
    const lineSubtotal = itemPrice * item.quantity;
    const lineTax = item.taxable ? await calcTaxAsync(adb, lineSubtotal, defaultTaxClassId, false) : 0;

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
    ? await adb.get<AnyRow>('SELECT id, order_id FROM invoices WHERE ticket_id = ?', ticketId)
    : undefined;

  if (existingInvoice) {
    // UPDATE existing invoice with current totals and payment status
    invoiceId = existingInvoice.id;
    await adb.run(`
      UPDATE invoices SET
        customer_id = ?, subtotal = ?, discount = ?, total_tax = ?, total = ?,
        amount_paid = ?, amount_due = ?, status = ?, updated_at = ?
      WHERE id = ?
    `,
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
    await adb.run('DELETE FROM invoice_line_items WHERE invoice_id = ?', invoiceId);
  } else {
    // CREATE new invoice
    const invSeq = await adb.get<AnyRow>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices");
    const invoiceOrderId = generateOrderId('INV', invSeq!.next_num);

    const invoiceResult = await adb.run(`
      INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
                            amount_paid, amount_due, status, created_by, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
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
    await adb.run(`
      INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `, invoiceId, line.inventory_item_id, line.description, line.quantity, line.unit_price, line.tax_amount, line.total);
  }

  // Link invoice to ticket (so ticket detail can find it)
  if (ticketId) {
    await adb.run('UPDATE tickets SET invoice_id = ?, updated_at = ? WHERE id = ?',
      invoiceId, now(), ticketId);
  }

  // ENR-POS3: Log discount to audit trail when a discount is applied
  if (discount > 0) {
    try {
      await adb.run(
        'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
        'discount_applied', userId, req.ip || 'unknown',
        JSON.stringify({ ticket_id: ticketId, invoice_id: invoiceId, discount_amount: discount, discount_reason: ticketData?.discount_reason || null }),
      );
    } catch (err) {
      console.error('[Audit] Failed to write audit log:', err);
    }
  }

  // ---- 4. If checkout mode: payment + stock deductions + POS transaction ----
  let change = 0;
  if (isPaid) {
    // Record payment(s) — support split payments
    if (Array.isArray(splitPayments) && splitPayments.length > 0) {
      let totalPaid = 0;
      for (const sp of splitPayments) {
        const amt = parseFloat(sp.amount);
        if (isNaN(amt) || amt <= 0) throw new AppError('Each split payment amount must be positive', 400);
        await adb.run(`
          INSERT INTO payments (invoice_id, amount, method, user_id, created_at)
          VALUES (?, ?, ?, ?, ?)
        `, invoiceId, amt, sp.method, userId, now());
        totalPaid += amt;
      }
      change = Math.max(0, totalPaid - invoiceTotal);

      // POS transaction record (combine method names)
      await adb.run(`
        INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id)
        VALUES (?, ?, ?, ?, ?)
      `, invoiceId, customerId, invoiceTotal, splitPayments.map((p: any) => p.method).join('+'), userId);
    } else {
      // Legacy single payment
      await adb.run(`
        INSERT INTO payments (invoice_id, amount, method, user_id, created_at)
        VALUES (?, ?, ?, ?, ?)
      `, invoiceId, paidAmount, payment_method, userId, now());

      change = Math.max(0, paidAmount - invoiceTotal);

      // POS transaction record
      await adb.run(`
        INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id)
        VALUES (?, ?, ?, ?, ?)
      `, invoiceId, customerId, invoiceTotal, payment_method, userId);
    }

    // Deduct stock for product items
    for (const item of product_items) {
      const inv = await adb.get<AnyRow>('SELECT * FROM inventory_items WHERE id = ?', item.inventory_item_id);
      if (inv && inv.item_type !== 'service') {
        await adb.run('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?',
          item.quantity, now(), item.inventory_item_id);
        await adb.run(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
          VALUES (?, 'sale', ?, 'invoice', ?, 'POS checkout', ?, ?, ?)
        `, item.inventory_item_id, -item.quantity, invoiceId, userId, now(), now());
      }
    }
  }

  // ---- 4b. If checkout mode with a ticket: close the ticket ----
  if (isPaid && ticketId) {
    const closedStatus = await adb.get<AnyRow>(
      'SELECT id FROM ticket_statuses WHERE is_closed = 1 ORDER BY sort_order ASC LIMIT 1'
    );
    if (closedStatus) {
      await adb.run("UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?",
        closedStatus.id, now(), ticketId);
      // Record in ticket history
      const closedRow = await adb.get<AnyRow>('SELECT name FROM ticket_statuses WHERE id = ?', closedStatus.id);
      const closedName = closedRow?.name || 'Closed';
      await adb.run(`
        INSERT INTO ticket_history (ticket_id, action, old_value, new_value, user_id, created_at)
        VALUES (?, 'status_change', '', ?, ?, ?)
      `, ticketId, closedName, userId, now());
    }
  }

  // ---- 5. Fetch created records for response ----
  const invoice = await adb.get<any>(`
    SELECT inv.*, c.first_name, c.last_name
    FROM invoices inv
    LEFT JOIN customers c ON c.id = inv.customer_id
    WHERE inv.id = ?
  `, invoiceId);

  let ticket: any = null;
  if (ticketId) {
    ticket = await adb.get<any>(`
      SELECT t.*, ts.name AS status_name, ts.color AS status_color,
             c.first_name AS c_first_name, c.last_name AS c_last_name
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.id = ?
    `, ticketId);
    // Include devices for success screen summary
    if (ticket) {
      ticket.devices = await adb.all<any>(`
        SELECT td.id, td.device_name, td.device_type, td.service_id,
               COALESCE(td.service_name, ii.name) AS service_name
        FROM ticket_devices td
        LEFT JOIN inventory_items ii ON ii.id = td.service_id
        WHERE td.ticket_id = ?
      `, ticketId);
    }
  }

  const result = { ticket, invoice, change };

  // Broadcast ticket creation if a ticket was created
  if (result.ticket) {
    broadcast(WS_EVENTS.TICKET_CREATED, result.ticket, req.tenantSlug || null);

    // Create in-app notification for all active users
    const customerName = result.ticket.c_first_name
      ? `${result.ticket.c_first_name} ${result.ticket.c_last_name || ''}`.trim()
      : 'Walk-in';
    const deviceSummary = result.ticket.devices?.map((d: any) => d.device_name).filter(Boolean).join(', ') || 'Repair';
    const notifTitle = `New Ticket ${result.ticket.order_id}`;
    const notifMessage = `${customerName} — ${deviceSummary}`;
    const activeUsers = await adb.all<{ id: number }>("SELECT id FROM users WHERE is_active = 1");
    for (const u of activeUsers) {
      await adb.run(`
        INSERT INTO notifications (user_id, type, title, message, entity_type, entity_id, created_at, updated_at)
        VALUES (?, 'ticket_created', ?, ?, 'ticket', ?, datetime('now'), datetime('now'))
      `, u.id, notifTitle, notifMessage, result.ticket.id);
    }
  }

  // SW-D13: Include checkin settings in response
  const [checkinCategory, autoPrintLabel] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'checkin_default_category'"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'checkin_auto_print_label'"),
  ]);

  res.status(201).json({
    success: true,
    data: {
      ...result,
      checkin_default_category: checkinCategory?.value ?? null,
      auto_print_label: autoPrintLabel?.value === '1' || autoPrintLabel?.value === 'true',
      // Membership info for upsell prompt
      membership: customerMembership ? {
        active: true,
        tier_name: customerMembership.tier_name,
        discount_pct: customerMembership.discount_pct,
        discount_applies_to: customerMembership.discount_applies_to,
      } : membershipEnabled?.value === 'true' ? {
        active: false,
        upsell: true, // Frontend shows "Not a member — offer X% off" banner
      } : null,
    },
  });
});

// ---------------------------------------------------------------------------
// ENR-POS2: POST /pos/return — Return/exchange workflow
// Creates a credit note (negative invoice), restores stock, records reason.
// Admin/manager only.
// ---------------------------------------------------------------------------
router.post('/return', async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const userRole = req.user!.role;
  const ip = req.ip || 'unknown';

  // Admin/manager only
  if (userRole !== 'admin' && userRole !== 'manager') {
    throw new AppError('Only admin or manager can process returns', 403);
  }

  const { invoice_id, items } = req.body as {
    invoice_id: number;
    items: { line_item_id: number; quantity: number; reason: string }[];
  };

  if (!invoice_id) throw new AppError('invoice_id is required', 400);
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new AppError('At least one return item is required', 400);
  }

  // Verify invoice exists
  const invoice = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', invoice_id);
  if (!invoice) throw new AppError('Invoice not found', 404);

  let creditTotal = 0;
  const returnDetails: any[] = [];

  for (const item of items) {
    if (!item.line_item_id) throw new AppError('line_item_id is required for each item', 400);
    if (!item.quantity || item.quantity < 1) throw new AppError('quantity must be at least 1', 400);
    if (!item.reason?.trim()) throw new AppError('reason is required for each item', 400);

    const lineItem = await adb.get<any>(
      'SELECT * FROM invoice_line_items WHERE id = ? AND invoice_id = ?',
      item.line_item_id, invoice_id,
    );
    if (!lineItem) throw new AppError(`Line item ${item.line_item_id} not found on invoice ${invoice_id}`, 404);

    if (item.quantity > lineItem.quantity) {
      throw new AppError(`Return quantity (${item.quantity}) exceeds invoiced quantity (${lineItem.quantity})`, 400);
    }

    const unitPrice = lineItem.unit_price;
    const unitTax = lineItem.quantity > 0 ? lineItem.tax_amount / lineItem.quantity : 0;
    const returnAmount = roundCurrency(item.quantity * (unitPrice + unitTax));
    creditTotal += returnAmount;

    // Restore stock if the line item has an inventory_item_id (physical product)
    if (lineItem.inventory_item_id) {
      await adb.run(
        'UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime(\'now\') WHERE id = ?',
        item.quantity, lineItem.inventory_item_id,
      );

      await adb.run(`
        INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
        VALUES (?, 'return', ?, 'invoice', ?, ?, ?, datetime('now'), datetime('now'))
      `, lineItem.inventory_item_id, item.quantity, invoice_id, `Return: ${item.reason}`, userId);
    }

    returnDetails.push({
      line_item_id: item.line_item_id,
      description: lineItem.description,
      quantity: item.quantity,
      amount: returnAmount,
      reason: item.reason,
    });
  }

  // Create credit note (negative invoice)
  const seqRow = await adb.get<any>(
    "SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices",
  );
  const creditOrderId = generateOrderId('CRN', seqRow!.next_num);

  const creditResult = await adb.run(`
    INSERT INTO invoices (order_id, customer_id, subtotal, discount, total_tax, total, amount_paid, amount_due, status, notes, created_by, created_at, updated_at)
    VALUES (?, ?, ?, 0, 0, ?, 0, 0, 'credit_note', ?, ?, datetime('now'), datetime('now'))
  `,
    creditOrderId,
    invoice.customer_id,
    -creditTotal,
    -creditTotal,
    `Credit note for return on ${invoice.order_id}. Items: ${returnDetails.map(d => `${d.description} x${d.quantity} (${d.reason})`).join('; ')}`,
    userId,
  );

  const creditNoteId = Number(creditResult.lastInsertRowid);

  // Insert negative line items on the credit note
  for (const detail of returnDetails) {
    await adb.run(`
      INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, tax_amount, total, created_at, updated_at)
      VALUES (?, ?, ?, ?, 0, ?, datetime('now'), datetime('now'))
    `, creditNoteId, `RETURN: ${detail.description}`, -detail.quantity, detail.amount / detail.quantity, -detail.amount);
  }

  // Create refund record
  await adb.run(`
    INSERT INTO refunds (invoice_id, customer_id, amount, type, reason, status, created_by, created_at, updated_at)
    VALUES (?, ?, ?, 'credit_note', ?, 'completed', ?, datetime('now'), datetime('now'))
  `, invoice_id, invoice.customer_id, creditTotal, returnDetails.map(d => d.reason).join('; '), userId);

  // Audit log
  try {
    await adb.run(
      'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
      'pos_return', userId, ip,
      JSON.stringify({ invoice_id, credit_note_id: creditNoteId, credit_note_order_id: creditOrderId, total_credited: creditTotal, items: returnDetails }),
    );
  } catch (err) {
    console.error('[Audit] Failed to write audit log:', err);
  }

  const creditNote = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', creditNoteId);

  res.status(201).json({ success: true, data: { credit_note: creditNote, items: returnDetails, total_credited: creditTotal } });
});

// ==================== ENR-POS4: Cash drawer integration ====================
// POST /pos/open-drawer — sends a command to open the cash drawer
// For now, logs the event and returns success. Actual hardware integration is per-deployment.
router.post('/open-drawer', async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const { reason } = req.body;

  // Log the drawer open event to cash_register table
  await adb.run(`
    INSERT INTO cash_register (type, amount, reason, user_id)
    VALUES ('drawer_open', 0, ?, ?)
  `, reason || 'Manual drawer open', userId);

  try {
    await adb.run(
      'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
      'cash_drawer_opened', userId, req.ip || 'unknown',
      JSON.stringify({ reason: reason || 'Manual drawer open' }),
    );
  } catch (err) {
    console.error('[Audit] Failed to write audit log:', err);
  }

  console.log(`[POS] Cash drawer open requested by user ${userId}`);

  res.json({
    success: true,
    data: { message: 'Cash drawer open command sent', opened_at: new Date().toISOString() },
  });
});

export default router;
