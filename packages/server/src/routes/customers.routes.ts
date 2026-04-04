import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { normalizePhone } from '../utils/phone.js';
import { generateOrderId } from '../utils/format.js';
import { runAutomations } from '../services/automations.js';
import type { CreateCustomerInput, UpdateCustomerInput } from '@bizarre-crm/shared';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const CUSTOMER_COLUMNS = [
  'first_name', 'last_name', 'title', 'organization', 'type',
  'email', 'phone', 'mobile',
  'address1', 'address2', 'city', 'state', 'postcode', 'country',
  'contact_person', 'contact_relation',
  'referred_by', 'customer_group_id',
  'tax_number', 'tax_class_id',
  'email_opt_in', 'sms_opt_in',
  'comments', 'source', 'tags',
] as const;

/** Sanitise an FTS5 MATCH term – double-quote each token so special chars are safe. */
function ftsMatchExpr(keyword: string): string {
  // Strip all non-alphanumeric except spaces and hyphens to prevent FTS injection
  const cleaned = keyword.replace(/[^a-zA-Z0-9\s\-@.]/g, '').trim();
  const tokens = cleaned.split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return '';
  return tokens.map(t => `"${t}"*`).join(' OR ');
}

// ---------------------------------------------------------------------------
// GET / – List customers (paginated, searchable)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const keyword = (req.query.keyword as string || '').trim();
    const groupId = req.query.group_id ? parseInt(req.query.group_id as string, 10) : null;
    const sortBy = (req.query.sort_by as string) || 'created_at';
    const sortOrder = (req.query.sort_order as string || 'DESC').toUpperCase() === 'ASC' ? 'ASC' : 'DESC';
    const includeStats = req.query.include_stats === '1';
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();
    const hasOpenTickets = req.query.has_open_tickets as string | undefined;

    // Whitelist sortable columns
    const allowedSorts = ['created_at', 'updated_at', 'first_name', 'last_name', 'organization', 'code', 'email', 'city', 'phone', 'mobile', 'total_spent', 'ticket_count'];
    const safeSortBy = allowedSorts.includes(sortBy) ? sortBy : 'created_at';

    const conditions: string[] = ['c.is_deleted = 0'];
    const params: unknown[] = [];

    // FTS keyword search with phone number fallback
    let ftsJoin = '';
    if (keyword) {
      // Extract digits for phone search fallback
      const digits = keyword.replace(/\D/g, '');
      const isPhoneSearch = digits.length >= 7;

      if (isPhoneSearch) {
        // Phone search: match digits against phone/mobile columns (strip formatting)
        conditions.push(`(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.phone, ' ', ''), '-', ''), '(', ''), ')', ''), '+', '') LIKE ? OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.mobile, ' ', ''), '-', ''), '(', ''), ')', ''), '+', '') LIKE ?)`);
        const digitPattern = `%${digits.slice(-10)}%`; // last 10 digits (strip country code)
        params.push(digitPattern, digitPattern);
      } else {
        const matchExpr = ftsMatchExpr(keyword);
        if (matchExpr) {
          ftsJoin = `INNER JOIN customers_fts fts ON fts.rowid = c.id`;
          conditions.push(`fts.customers_fts MATCH ?`);
          params.push(matchExpr);
        }
      }
    }

    if (groupId) {
      conditions.push('c.customer_group_id = ?');
      params.push(groupId);
    }

    if (fromDate) {
      conditions.push('DATE(c.created_at) >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      conditions.push('DATE(c.created_at) <= ?');
      params.push(toDate);
    }

    if (hasOpenTickets === '1') {
      conditions.push('EXISTS (SELECT 1 FROM tickets t JOIN ticket_statuses ts ON ts.id = t.status_id WHERE t.customer_id = c.id AND t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0)');
    } else if (hasOpenTickets === '0') {
      conditions.push('NOT EXISTS (SELECT 1 FROM tickets t JOIN ticket_statuses ts ON ts.id = t.status_id WHERE t.customer_id = c.id AND t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0)');
    }

    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    // Count total
    const countSql = `SELECT COUNT(*) as total FROM customers c ${ftsJoin} ${whereClause}`;
    const { total } = db.prepare(countSql).get(...params) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    // Stats columns (optional for performance)
    const statsColumns = includeStats
      ? `,
        COALESCE((SELECT SUM(inv.total) FROM invoices inv WHERE inv.customer_id = c.id AND inv.status != 'void'), 0) AS total_spent,
        COALESCE((SELECT SUM(inv.amount_due) FROM invoices inv WHERE inv.customer_id = c.id AND inv.status IN ('unpaid','partial')), 0) AS outstanding_balance,
        (SELECT MAX(t2.created_at) FROM tickets t2 WHERE t2.customer_id = c.id AND t2.is_deleted = 0) AS last_ticket_date`
      : '';

    // For sorting by computed columns, wrap in subquery
    const orderColumn = ['total_spent', 'ticket_count'].includes(safeSortBy) ? safeSortBy : `c.${safeSortBy}`;

    // Fetch page
    const dataSql = `
      SELECT
        c.*,
        cg.name AS customer_group_name,
        cg.discount_pct AS group_discount_pct,
        cg.discount_type AS group_discount_type,
        cg.auto_apply AS group_auto_apply,
        (SELECT COUNT(*) FROM tickets t WHERE t.customer_id = c.id AND t.is_deleted = 0) AS ticket_count
        ${statsColumns}
      FROM customers c
      ${ftsJoin}
      LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
      ${whereClause}
      ORDER BY ${orderColumn} ${sortOrder}
      LIMIT ? OFFSET ?
    `;

    const customers = db.prepare(dataSql).all(...params, pageSize, offset);

    res.json({
      success: true,
      data: {
        customers,
        pagination: {
          page,
          per_page: pageSize,
          total,
          total_pages: totalPages,
        },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /search – Quick typeahead search
// ---------------------------------------------------------------------------
router.get(
  '/search',
  asyncHandler(async (req, res) => {
    const q = (req.query.q as string || '').trim();
    if (!q) {
      return void res.json({ success: true, data: [] });
    }

    const matchExpr = ftsMatchExpr(q);
    let results: unknown[];

    if (matchExpr) {
      try {
        results = db
          .prepare(
            `SELECT c.id, c.code, c.first_name, c.last_name, c.phone, c.mobile, c.email, c.organization,
                    c.customer_group_id, cg.name AS customer_group_name,
                    cg.discount_pct AS group_discount_pct, cg.discount_type AS group_discount_type,
                    cg.auto_apply AS group_auto_apply
             FROM customers c
             INNER JOIN customers_fts fts ON fts.rowid = c.id
             LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
             WHERE fts.customers_fts MATCH ? AND c.is_deleted = 0
             LIMIT 10`,
          )
          .all(matchExpr);
      } catch {
        // FTS can fail on odd characters – fall back to LIKE
        results = likeSearch(q);
      }
    } else {
      results = likeSearch(q);
    }

    res.json({ success: true, data: results });
  }),
);

function likeSearch(q: string) {
  const like = `%${q}%`;
  return db
    .prepare(
      `SELECT c.id, c.code, c.first_name, c.last_name, c.phone, c.mobile, c.email, c.organization,
              c.customer_group_id, cg.name AS customer_group_name,
              cg.discount_pct AS group_discount_pct, cg.discount_type AS group_discount_type,
              cg.auto_apply AS group_auto_apply
       FROM customers c
       LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
       WHERE c.is_deleted = 0
         AND (c.first_name LIKE ? OR c.last_name LIKE ? OR c.phone LIKE ? OR c.mobile LIKE ? OR c.email LIKE ? OR c.organization LIKE ?)
       LIMIT 10`,
    )
    .all(like, like, like, like, like, like);
}

// ---------------------------------------------------------------------------
// GET /groups – List all customer groups
// ---------------------------------------------------------------------------
router.get(
  '/groups',
  asyncHandler(async (_req, res) => {
    const groups = db.prepare('SELECT * FROM customer_groups ORDER BY name').all();
    res.json({ success: true, data: groups });
  }),
);

// ---------------------------------------------------------------------------
// POST /groups – Create customer group
// ---------------------------------------------------------------------------
router.post(
  '/groups',
  asyncHandler(async (req, res) => {
    const { name, discount_pct, discount_type, auto_apply, description } = req.body;
    if (!name) throw new AppError('Group name is required');

    const result = db
      .prepare(
        `INSERT INTO customer_groups (name, discount_pct, discount_type, auto_apply, description) VALUES (?, ?, ?, ?, ?)`,
      )
      .run(name, discount_pct ?? 0, discount_type ?? 'percentage', auto_apply !== undefined ? (auto_apply ? 1 : 0) : 1, description ?? null);

    const group = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(result.lastInsertRowid);
    res.status(201).json({ success: true, data: group });
  }),
);

// ---------------------------------------------------------------------------
// PUT /groups/:id – Update customer group
// ---------------------------------------------------------------------------
router.put(
  '/groups/:id',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { name, discount_pct, discount_type, auto_apply, description } = req.body;

    const existing = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(Number(id));
    if (!existing) throw new AppError('Customer group not found', 404);

    db.prepare(
      `UPDATE customer_groups SET name = ?, discount_pct = ?, discount_type = ?, auto_apply = ?, description = ?, updated_at = datetime('now') WHERE id = ?`,
    ).run(
      name ?? (existing as any).name,
      discount_pct ?? (existing as any).discount_pct,
      discount_type ?? (existing as any).discount_type,
      auto_apply !== undefined ? (auto_apply ? 1 : 0) : (existing as any).auto_apply,
      description !== undefined ? description : (existing as any).description,
      Number(id),
    );

    const group = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(Number(id));
    res.json({ success: true, data: group });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /groups/:id – Delete customer group
// ---------------------------------------------------------------------------
router.delete(
  '/groups/:id',
  asyncHandler(async (req, res) => {
    const { id } = req.params;

    const existing = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(Number(id));
    if (!existing) throw new AppError('Customer group not found', 404);

    // Unlink customers first
    db.prepare('UPDATE customers SET customer_group_id = NULL WHERE customer_group_id = ?').run(Number(id));
    db.prepare('DELETE FROM customer_groups WHERE id = ?').run(Number(id));

    res.json({ success: true, data: { message: 'Group deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// POST /import-csv – Bulk create customers from CSV data
// ---------------------------------------------------------------------------
router.post(
  '/import-csv',
  asyncHandler(async (req, res) => {
    const { items } = req.body;
    if (!Array.isArray(items) || items.length === 0) throw new AppError('items array is required', 400);
    if (items.length > 500) throw new AppError('Maximum 500 customers per import', 400);

    const results: { created: number; errors: { row: number; error: string }[] } = { created: 0, errors: [] };

    const importCustomers = db.transaction(() => {
      for (let i = 0; i < items.length; i++) {
        const row = items[i];
        try {
          if (!row.first_name) { results.errors.push({ row: i + 1, error: 'first_name is required' }); continue; }
          const phone = normalizePhone(row.phone) || null;
          const mobile = normalizePhone(row.mobile) || null;

          const result = db.prepare(`
            INSERT INTO customers (first_name, last_name, email, phone, mobile, organization, city, state, postcode, address1, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `).run(
            row.first_name, row.last_name || '', row.email || null, phone, mobile,
            row.organization || null, row.city || null, row.state || null, row.postcode || null,
            row.address1 || null, 'csv_import',
          );
          const customerId = result.lastInsertRowid as number;
          const code = generateOrderId('C', customerId);
          db.prepare('UPDATE customers SET code = ? WHERE id = ?').run(code, customerId);
          results.created++;
        } catch (err: any) {
          results.errors.push({ row: i + 1, error: err.message || 'Unknown error' });
        }
      }
    });

    importCustomers();
    res.json({ success: true, data: results });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create customer
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const input: CreateCustomerInput = req.body;

    if (!input.first_name) {
      throw new AppError('first_name is required');
    }

    const createCustomer = db.transaction(() => {
      // Normalise phones on the main record
      const phone = normalizePhone(input.phone) || null;
      const mobile = normalizePhone(input.mobile) || null;

      // Check for duplicate phone numbers (warn, don't block — unless force_create is false)
      if (!input.force_create) {
        const phoneToCheck = mobile || phone;
        if (phoneToCheck) {
          const existing = db.prepare(`
            SELECT c.id, c.first_name, c.last_name FROM customers c
            WHERE c.is_deleted = 0 AND (c.phone = ? OR c.mobile = ?)
            LIMIT 1
          `).get(phoneToCheck, phoneToCheck) as AnyRow | undefined;
          if (existing) {
            throw new AppError(
              `Phone number already belongs to ${existing.first_name} ${existing.last_name || ''} (ID: ${existing.id}). Send force_create: true to override.`,
              409,
            );
          }
        }

        // Check for duplicate email
        const emailToCheck = (input.email || '').trim().toLowerCase();
        if (emailToCheck) {
          const existing = db.prepare(`
            SELECT c.id, c.first_name, c.last_name FROM customers c
            WHERE c.is_deleted = 0 AND LOWER(c.email) = ?
            LIMIT 1
          `).get(emailToCheck) as AnyRow | undefined;
          if (existing) {
            throw new AppError(
              `Email already belongs to ${existing.first_name} ${existing.last_name || ''} (ID: ${existing.id}). Send force_create: true to override.`,
              409,
            );
          }
        }
      }

      const result = db
        .prepare(
          `INSERT INTO customers
            (first_name, last_name, title, organization, type,
             email, phone, mobile,
             address1, address2, city, state, postcode, country,
             contact_person, contact_relation,
             referred_by, customer_group_id,
             tax_number, tax_class_id,
             email_opt_in, sms_opt_in,
             comments, source, tags)
           VALUES
            (?, ?, ?, ?, ?,
             ?, ?, ?,
             ?, ?, ?, ?, ?, ?,
             ?, ?,
             ?, ?,
             ?, ?,
             ?, ?,
             ?, ?, ?)`,
        )
        .run(
          input.first_name,
          input.last_name ?? '',
          input.title ?? null,
          input.organization ?? null,
          input.type ?? 'individual',
          input.email ?? null,
          phone,
          mobile,
          input.address1 ?? null,
          input.address2 ?? null,
          input.city ?? null,
          input.state ?? null,
          input.postcode ?? null,
          input.country ?? null,
          input.contact_person ?? null,
          input.contact_relation ?? null,
          input.referred_by ?? null,
          input.customer_group_id ?? null,
          input.tax_number ?? null,
          input.tax_class_id ?? null,
          input.email_opt_in ? 1 : 0,
          input.sms_opt_in ? 1 : 0,
          input.comments ?? null,
          input.source ?? null,
          JSON.stringify(input.tags ?? []),
        );

      const customerId = result.lastInsertRowid as number;

      // Generate code
      const code = generateOrderId('C', customerId);
      db.prepare('UPDATE customers SET code = ? WHERE id = ?').run(code, customerId);

      // Phones
      if (input.phones?.length) {
        const insertPhone = db.prepare(
          'INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, ?)',
        );
        for (const p of input.phones) {
          insertPhone.run(customerId, normalizePhone(p.phone), p.label ?? '', p.is_primary ? 1 : 0);
        }
      }

      // Emails
      if (input.emails?.length) {
        const insertEmail = db.prepare(
          'INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, ?)',
        );
        for (const e of input.emails) {
          insertEmail.run(customerId, e.email, e.label ?? '', e.is_primary ? 1 : 0);
        }
      }

      // FTS – the trigger handles this automatically on INSERT, but if we updated code
      // after insert, we should re-sync. The UPDATE trigger on customers should fire,
      // so FTS is already up to date after the code UPDATE above.

      return customerId;
    });

    const customerId = createCustomer();

    const customer = db
      .prepare(
        `SELECT c.*, cg.name AS customer_group_name,
                cg.discount_pct AS group_discount_pct, cg.discount_type AS group_discount_type,
                cg.auto_apply AS group_auto_apply
         FROM customers c
         LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
         WHERE c.id = ?`,
      )
      .get(customerId);

    const phones = db.prepare('SELECT * FROM customer_phones WHERE customer_id = ?').all(customerId);
    const emails = db.prepare('SELECT * FROM customer_emails WHERE customer_id = ?').all(customerId);

    // Fire automations (async, non-blocking)
    runAutomations('customer_created', { customer: { ...(customer as any), phones, emails } });

    res.status(201).json({
      success: true,
      data: { ...(customer as any), phones, emails },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Customer detail
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);

    const customer = db
      .prepare(
        `SELECT c.*,
                cg.name AS customer_group_name,
                cg.discount_pct AS group_discount_pct,
                cg.discount_type AS group_discount_type,
                cg.auto_apply AS group_auto_apply,
                (SELECT COUNT(*) FROM tickets t WHERE t.customer_id = c.id AND t.is_deleted = 0) AS ticket_count,
                (SELECT COALESCE(SUM(i.total), 0) FROM invoices i WHERE i.customer_id = c.id) AS total_invoiced
         FROM customers c
         LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
         WHERE c.id = ? AND c.is_deleted = 0`,
      )
      .get(id);

    if (!customer) throw new AppError('Customer not found', 404);

    const phones = db.prepare('SELECT * FROM customer_phones WHERE customer_id = ?').all(id);
    const emails = db.prepare('SELECT * FROM customer_emails WHERE customer_id = ?').all(id);
    const assets = db.prepare('SELECT * FROM customer_assets WHERE customer_id = ? ORDER BY created_at DESC').all(id);

    res.json({
      success: true,
      data: { ...(customer as any), phones, emails, assets },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update customer
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const input: UpdateCustomerInput = req.body;

    const existing = db.prepare('SELECT * FROM customers WHERE id = ? AND is_deleted = 0').get(id) as any;
    if (!existing) throw new AppError('Customer not found', 404);

    const updateCustomer = db.transaction(() => {
      // Build dynamic SET clause from provided fields
      const sets: string[] = [];
      const values: unknown[] = [];

      for (const col of CUSTOMER_COLUMNS) {
        if (col in input) {
          let val = (input as any)[col];

          if (col === 'phone' || col === 'mobile') {
            val = normalizePhone(val) || null;
          } else if (col === 'tags') {
            val = JSON.stringify(val ?? []);
          } else if (col === 'email_opt_in' || col === 'sms_opt_in') {
            val = val ? 1 : 0;
          }

          sets.push(`${col} = ?`);
          values.push(val ?? null);
        }
      }

      if (sets.length > 0) {
        sets.push(`updated_at = datetime('now')`);
        values.push(id);
        db.prepare(`UPDATE customers SET ${sets.join(', ')} WHERE id = ?`).run(...values);
      }

      // Replace phones
      if (input.phones !== undefined) {
        db.prepare('DELETE FROM customer_phones WHERE customer_id = ?').run(id);
        if (input.phones?.length) {
          const ins = db.prepare(
            'INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, ?)',
          );
          for (const p of input.phones) {
            ins.run(id, normalizePhone(p.phone), p.label ?? '', p.is_primary ? 1 : 0);
          }
        }
      }

      // Replace emails
      if (input.emails !== undefined) {
        db.prepare('DELETE FROM customer_emails WHERE customer_id = ?').run(id);
        if (input.emails?.length) {
          const ins = db.prepare(
            'INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, ?)',
          );
          for (const e of input.emails) {
            ins.run(id, e.email, e.label ?? '', e.is_primary ? 1 : 0);
          }
        }
      }

      // FTS is updated via the UPDATE trigger on the customers table
    });

    updateCustomer();

    // Return refreshed customer
    const customer = db
      .prepare(
        `SELECT c.*, cg.name AS customer_group_name,
                cg.discount_pct AS group_discount_pct,
                cg.discount_type AS group_discount_type,
                cg.auto_apply AS group_auto_apply,
                (SELECT COUNT(*) FROM tickets t WHERE t.customer_id = c.id AND t.is_deleted = 0) AS ticket_count,
                (SELECT COALESCE(SUM(i.total), 0) FROM invoices i WHERE i.customer_id = c.id) AS total_invoiced
         FROM customers c
         LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
         WHERE c.id = ?`,
      )
      .get(id);

    const phones = db.prepare('SELECT * FROM customer_phones WHERE customer_id = ?').all(id);
    const emails = db.prepare('SELECT * FROM customer_emails WHERE customer_id = ?').all(id);

    res.json({
      success: true,
      data: { ...(customer as any), phones, emails },
    });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id – Soft delete
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);

    const existing = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(id);
    if (!existing) throw new AppError('Customer not found', 404);

    // Prevent deleting customers with open tickets
    const openTickets = (db.prepare(`
      SELECT COUNT(*) AS n FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.customer_id = ? AND t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
    `).get(id) as any).n as number;
    if (openTickets > 0) {
      throw new AppError(`Cannot delete customer with ${openTickets} open ticket${openTickets > 1 ? 's' : ''}. Close or reassign them first.`, 400);
    }

    db.prepare(`UPDATE customers SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?`).run(id);

    res.json({ success: true, data: { message: 'Customer deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/analytics – Customer lifetime analytics
// ---------------------------------------------------------------------------
router.get(
  '/:id/analytics',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const stats = db.prepare(`
      SELECT
        COUNT(DISTINCT t.id) AS total_tickets,
        COALESCE(SUM(i.total), 0) AS lifetime_value,
        COALESCE(AVG(i.total), 0) AS avg_ticket_value,
        MIN(t.created_at) AS first_visit,
        MAX(t.created_at) AS last_visit,
        CAST(julianday('now') - julianday(MAX(t.created_at)) AS INTEGER) AS days_since_last_visit
      FROM tickets t
      LEFT JOIN invoices i ON i.ticket_id = t.id AND i.status != 'void'
      WHERE t.customer_id = ? AND t.is_deleted = 0
    `).get(id) as any;

    res.json({ success: true, data: {
      total_tickets: stats.total_tickets || 0,
      lifetime_value: Math.round((stats.lifetime_value || 0) * 100) / 100,
      avg_ticket_value: Math.round((stats.avg_ticket_value || 0) * 100) / 100,
      first_visit: stats.first_visit,
      last_visit: stats.last_visit,
      days_since_last_visit: stats.days_since_last_visit || null,
    }});
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/tickets – Customer's tickets (paginated)
// ---------------------------------------------------------------------------
router.get(
  '/:id/tickets',
  asyncHandler(async (req, res) => {
    const customerId = Number(req.params.id);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const existing = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    const { total } = db
      .prepare('SELECT COUNT(*) as total FROM tickets WHERE customer_id = ? AND is_deleted = 0')
      .get(customerId) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const rows = db
      .prepare(
        `SELECT t.*,
                ts.name AS status_name, ts.color AS status_color, ts.is_closed, ts.is_cancelled,
                td.device_name AS first_device_name
         FROM tickets t
         LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
         LEFT JOIN (
           SELECT ticket_id, device_name FROM ticket_devices GROUP BY ticket_id
         ) td ON td.ticket_id = t.id
         WHERE t.customer_id = ? AND t.is_deleted = 0
         ORDER BY t.created_at DESC
         LIMIT ? OFFSET ?`,
      )
      .all(customerId, pageSize, offset) as any[];

    const tickets = rows.map((r: any) => ({
      ...r,
      status: { name: r.status_name, color: r.status_color, is_closed: r.is_closed, is_cancelled: r.is_cancelled },
      devices: r.first_device_name ? [{ device_name: r.first_device_name }] : [],
    }));

    res.json({
      success: true,
      data: {
        tickets,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/invoices – Customer's invoices (paginated)
// ---------------------------------------------------------------------------
router.get(
  '/:id/invoices',
  asyncHandler(async (req, res) => {
    const customerId = Number(req.params.id);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const existing = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    const { total } = db
      .prepare('SELECT COUNT(*) as total FROM invoices WHERE customer_id = ?')
      .get(customerId) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const invoices = db
      .prepare(
        `SELECT * FROM invoices
         WHERE customer_id = ?
         ORDER BY created_at DESC
         LIMIT ? OFFSET ?`,
      )
      .all(customerId, pageSize, offset);

    res.json({
      success: true,
      data: {
        invoices,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/communications – SMS + email for this customer
// ---------------------------------------------------------------------------
router.get(
  '/:id/communications',
  asyncHandler(async (req, res) => {
    const customerId = Number(req.params.id);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const existing = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    // Collect all normalised phone numbers for this customer
    const customer = db.prepare('SELECT phone, mobile FROM customers WHERE id = ?').get(customerId) as any;
    const extraPhones = db
      .prepare('SELECT phone FROM customer_phones WHERE customer_id = ?')
      .all(customerId) as { phone: string }[];

    const phoneSet = new Set<string>();
    if (customer.phone) phoneSet.add(normalizePhone(customer.phone));
    if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
    for (const p of extraPhones) {
      const norm = normalizePhone(p.phone);
      if (norm) phoneSet.add(norm);
    }

    if (phoneSet.size === 0) {
      return void res.json({
        success: true,
        data: {
          communications: [],
          pagination: { page, per_page: pageSize, total: 0, total_pages: 0 },
        },
      });
    }

    const phones = Array.from(phoneSet);
    const placeholders = phones.map(() => '?').join(', ');

    const { total } = db
      .prepare(`SELECT COUNT(*) as total FROM sms_messages WHERE conv_phone IN (${placeholders})`)
      .get(...phones) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const communications = db
      .prepare(
        `SELECT * FROM sms_messages
         WHERE conv_phone IN (${placeholders})
         ORDER BY created_at DESC
         LIMIT ? OFFSET ?`,
      )
      .all(...phones, pageSize, offset);

    res.json({
      success: true,
      data: {
        communications,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/assets – Customer's assets
// ---------------------------------------------------------------------------
router.get(
  '/:id/assets',
  asyncHandler(async (req, res) => {
    const customerId = Number(req.params.id);

    const existing = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    const assets = db
      .prepare('SELECT * FROM customer_assets WHERE customer_id = ? ORDER BY created_at DESC')
      .all(customerId);

    res.json({ success: true, data: assets });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/assets – Add asset
// ---------------------------------------------------------------------------
router.post(
  '/:id/assets',
  asyncHandler(async (req, res) => {
    const customerId = Number(req.params.id);
    const { name, device_type, serial, imei, color, notes } = req.body;

    const existing = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    if (!name) throw new AppError('Asset name is required');

    const result = db
      .prepare(
        `INSERT INTO customer_assets (customer_id, name, device_type, serial, imei, color, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(customerId, name, device_type ?? null, serial ?? null, imei ?? null, color ?? null, notes ?? null);

    const asset = db.prepare('SELECT * FROM customer_assets WHERE id = ?').get(result.lastInsertRowid);
    res.status(201).json({ success: true, data: asset });
  }),
);

// ---------------------------------------------------------------------------
// PUT /assets/:assetId – Update asset
// ---------------------------------------------------------------------------
router.put(
  '/assets/:assetId',
  asyncHandler(async (req, res) => {
    const assetId = Number(req.params.assetId);
    const { name, device_type, serial, imei, color, notes } = req.body;

    const existing = db.prepare('SELECT * FROM customer_assets WHERE id = ?').get(assetId) as any;
    if (!existing) throw new AppError('Asset not found', 404);

    db.prepare(
      `UPDATE customer_assets
       SET name = ?, device_type = ?, serial = ?, imei = ?, color = ?, notes = ?, updated_at = datetime('now')
       WHERE id = ?`,
    ).run(
      name ?? existing.name,
      device_type !== undefined ? device_type : existing.device_type,
      serial !== undefined ? serial : existing.serial,
      imei !== undefined ? imei : existing.imei,
      color !== undefined ? color : existing.color,
      notes !== undefined ? notes : existing.notes,
      assetId,
    );

    const asset = db.prepare('SELECT * FROM customer_assets WHERE id = ?').get(assetId);
    res.json({ success: true, data: asset });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /assets/:assetId – Delete asset
// ---------------------------------------------------------------------------
router.delete(
  '/assets/:assetId',
  asyncHandler(async (req, res) => {
    const assetId = Number(req.params.assetId);

    const existing = db.prepare('SELECT id FROM customer_assets WHERE id = ?').get(assetId);
    if (!existing) throw new AppError('Asset not found', 404);

    db.prepare('DELETE FROM customer_assets WHERE id = ?').run(assetId);

    res.json({ success: true, data: { message: 'Asset deleted' } });
  }),
);

export default router;
