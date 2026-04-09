import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { normalizePhone } from '../utils/phone.js';
import { generateOrderId } from '../utils/format.js';
import { runAutomations } from '../services/automations.js';
import { audit } from '../utils/audit.js';
import { sendSms, getSmsProvider } from '../services/smsProvider.js';
import type { CreateCustomerInput, UpdateCustomerInput } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';

type AnyRow = Record<string, any>;

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const maxLen = (val: string | undefined, max: number) => val && val.length > max ? val.slice(0, max) : val;

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

/** Basic email format validation. */
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function isValidEmail(email: string): boolean {
  return EMAIL_REGEX.test(email);
}

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
    const adb = req.asyncDb;
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
    const { total } = await adb.get<{ total: number }>(countSql, ...params) as { total: number };

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

    const rawCustomers = await adb.all<AnyRow>(dataSql, ...params, pageSize, offset);

    // ENR-C8: Add data quality indicators (profile_completeness + missing_fields)
    const customers = rawCustomers.map((c) => {
      const requiredFields: { key: string; label: string }[] = [
        { key: 'first_name', label: 'first_name' },
        { key: 'phone', label: 'phone' },
        { key: 'email', label: 'email' },
        { key: 'address1', label: 'address' },
      ];
      const filledCount = requiredFields.filter(
        (f) => c[f.key] && String(c[f.key]).trim() !== '',
      ).length;
      const missingFields = requiredFields
        .filter((f) => !c[f.key] || String(c[f.key]).trim() === '')
        .map((f) => f.label);

      return {
        ...c,
        profile_completeness: Math.round((filledCount / requiredFields.length) * 100),
        missing_fields: missingFields,
      };
    });

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
    const adb = req.asyncDb;
    const q = (req.query.q as string || '').trim();
    if (!q) {
      return void res.json({ success: true, data: [] });
    }

    const matchExpr = ftsMatchExpr(q);
    let results: unknown[];

    if (matchExpr) {
      try {
        results = await adb.all<AnyRow>(
            `SELECT c.id, c.code, c.first_name, c.last_name, c.phone, c.mobile, c.email, c.organization,
                    c.customer_group_id, cg.name AS customer_group_name,
                    cg.discount_pct AS group_discount_pct, cg.discount_type AS group_discount_type,
                    cg.auto_apply AS group_auto_apply
             FROM customers c
             INNER JOIN customers_fts fts ON fts.rowid = c.id
             LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
             WHERE fts.customers_fts MATCH ? AND c.is_deleted = 0
             LIMIT 10`,
          matchExpr);
      } catch {
        // FTS can fail on odd characters – fall back to LIKE
        results = likeSearch(req.db, q);
      }
    } else {
      results = likeSearch(req.db, q);
    }

    res.json({ success: true, data: results });
  }),
);

function likeSearch(db: any, q: string) {
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
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const groups = await adb.all<AnyRow>('SELECT * FROM customer_groups ORDER BY name');
    res.json({ success: true, data: groups });
  }),
);

// ---------------------------------------------------------------------------
// POST /groups – Create customer group
// ---------------------------------------------------------------------------
router.post(
  '/groups',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const { name, discount_pct, discount_type, auto_apply, description } = req.body;
    if (!name) throw new AppError('Group name is required');

    const pct = discount_pct ?? 0;
    if (typeof pct !== 'number' || pct < 0 || pct > 100) {
      throw new AppError('discount_pct must be between 0 and 100', 400);
    }

    const result = await adb.run(
        `INSERT INTO customer_groups (name, discount_pct, discount_type, auto_apply, description) VALUES (?, ?, ?, ?, ?)`,
      name, pct, discount_type ?? 'percentage', auto_apply !== undefined ? (auto_apply ? 1 : 0) : 1, description ?? null);

    const group = await adb.get<AnyRow>('SELECT * FROM customer_groups WHERE id = ?', result.lastInsertRowid);
    res.status(201).json({ success: true, data: group });
  }),
);

// ---------------------------------------------------------------------------
// PUT /groups/:id – Update customer group
// ---------------------------------------------------------------------------
router.put(
  '/groups/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const { id } = req.params;
    const { name, discount_pct, discount_type, auto_apply, description } = req.body;

    const existing = await adb.get<AnyRow>('SELECT * FROM customer_groups WHERE id = ?', Number(id));
    if (!existing) throw new AppError('Customer group not found', 404);

    if (discount_pct !== undefined && (typeof discount_pct !== 'number' || discount_pct < 0 || discount_pct > 100)) {
      throw new AppError('discount_pct must be between 0 and 100', 400);
    }

    await adb.run(
      `UPDATE customer_groups SET name = ?, discount_pct = ?, discount_type = ?, auto_apply = ?, description = ?, updated_at = datetime('now') WHERE id = ?`,
      name ?? (existing as any).name,
      discount_pct ?? (existing as any).discount_pct,
      discount_type ?? (existing as any).discount_type,
      auto_apply !== undefined ? (auto_apply ? 1 : 0) : (existing as any).auto_apply,
      description !== undefined ? description : (existing as any).description,
      Number(id),
    );

    const group = await adb.get<AnyRow>('SELECT * FROM customer_groups WHERE id = ?', Number(id));
    res.json({ success: true, data: group });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /groups/:id – Delete customer group
// ---------------------------------------------------------------------------
router.delete(
  '/groups/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const { id } = req.params;

    const existing = await adb.get<AnyRow>('SELECT * FROM customer_groups WHERE id = ?', Number(id));
    if (!existing) throw new AppError('Customer group not found', 404);

    // Unlink customers first
    await adb.run('UPDATE customers SET customer_group_id = NULL WHERE customer_group_id = ?', Number(id));
    await adb.run('DELETE FROM customer_groups WHERE id = ?', Number(id));

    res.json({ success: true, data: { message: 'Group deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// POST /import-csv – Bulk create customers from CSV data
// SEC-H8: Admin or manager role required for bulk import operations
// ---------------------------------------------------------------------------
router.post(
  '/import-csv',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin' && req.user?.role !== 'manager') throw new AppError('Admin or manager access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    const { items, skip_duplicates } = req.body;
    if (!Array.isArray(items) || items.length === 0) throw new AppError('items array is required', 400);
    if (items.length > 500) throw new AppError('Maximum 500 customers per import', 400);

    const results: { created: number; skipped: number; errors: { row: number; error: string }[] } = { created: 0, skipped: 0, errors: [] };

    // Pre-build lookup sets for duplicate detection when skip_duplicates is enabled.
    // Checks normalized phone, mobile, and lowercase email against existing customers.
    const existingPhones = new Set<string>();
    const existingEmails = new Set<string>();
    if (skip_duplicates) {
      const [allPhones, allEmails] = await Promise.all([
        adb.all<{ phone: string }>(
          "SELECT phone FROM customers WHERE phone IS NOT NULL AND phone != '' UNION SELECT mobile FROM customers WHERE mobile IS NOT NULL AND mobile != ''"
        ),
        adb.all<{ email: string }>(
          "SELECT LOWER(email) AS email FROM customers WHERE email IS NOT NULL AND email != ''"
        ),
      ]);
      for (const r of allPhones) existingPhones.add(r.phone);
      for (const r of allEmails) existingEmails.add(r.email);
    }

    const importCustomers = db.transaction(() => {
      for (let i = 0; i < items.length; i++) {
        const row = items[i];
        try {
          if (!row.first_name) { results.errors.push({ row: i + 1, error: 'first_name is required' }); continue; }
          const phone = normalizePhone(row.phone) || null;
          const mobile = normalizePhone(row.mobile) || null;
          const email = row.email ? row.email.trim().toLowerCase() : null;

          // Optional duplicate check: skip row if phone, mobile, or email already exists
          if (skip_duplicates) {
            if ((phone && existingPhones.has(phone)) ||
                (mobile && existingPhones.has(mobile)) ||
                (email && existingEmails.has(email))) {
              results.skipped++;
              continue;
            }
          }

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

          // Track newly created entries so subsequent rows in the same batch
          // are also checked against earlier rows (not just pre-existing DB records)
          if (skip_duplicates) {
            if (phone) existingPhones.add(phone);
            if (mobile) existingPhones.add(mobile);
            if (email) existingEmails.add(email);
          }
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
// POST /merge – Merge/deduplicate two customers
// ENR-C1: Move all tickets, invoices, SMS, assets from merge_id → keep_id.
//         Merge phone numbers and emails (avoid duplicates). Soft-delete merged.
// ---------------------------------------------------------------------------
router.post(
  '/merge',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    const { keep_id, merge_id } = req.body;

    if (!keep_id || !merge_id) throw new AppError('keep_id and merge_id are required', 400);
    if (keep_id === merge_id) throw new AppError('Cannot merge a customer into itself', 400);

    const [keepCustomer, mergeCustomer] = await Promise.all([
      adb.get<AnyRow>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', Number(keep_id)),
      adb.get<AnyRow>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', Number(merge_id)),
    ]);
    if (!keepCustomer) throw new AppError('Keep customer not found', 404);
    if (!mergeCustomer) throw new AppError('Merge customer not found', 404);

    const mergeTransaction = db.transaction(() => {
      const kid = Number(keep_id);
      const mid = Number(merge_id);

      // Move tickets
      db.prepare('UPDATE tickets SET customer_id = ? WHERE customer_id = ?').run(kid, mid);

      // Move invoices
      db.prepare('UPDATE invoices SET customer_id = ? WHERE customer_id = ?').run(kid, mid);

      // Move estimates
      db.prepare('UPDATE estimates SET customer_id = ? WHERE customer_id = ?').run(kid, mid);

      // Move SMS messages — match by merge customer's phone numbers
      const mergePhones: string[] = [];
      if (mergeCustomer.phone) mergePhones.push(normalizePhone(mergeCustomer.phone));
      if (mergeCustomer.mobile) mergePhones.push(normalizePhone(mergeCustomer.mobile));
      const mergeExtraPhones = db.prepare('SELECT phone FROM customer_phones WHERE customer_id = ?').all(mid) as { phone: string }[];
      for (const p of mergeExtraPhones) {
        const norm = normalizePhone(p.phone);
        if (norm) mergePhones.push(norm);
      }
      // Update SMS conv_phone to keep customer's primary phone where applicable
      // (SMS are matched by phone, so we just ensure they can be found via keep's phones)

      // Move assets
      db.prepare('UPDATE customer_assets SET customer_id = ? WHERE customer_id = ?').run(kid, mid);

      // Move loaner history
      db.prepare('UPDATE loaner_history SET customer_id = ? WHERE customer_id = ?').run(kid, mid);

      // Merge phone numbers (avoid duplicates)
      const keepPhoneSet = new Set<string>();
      if (keepCustomer.phone) keepPhoneSet.add(normalizePhone(keepCustomer.phone));
      if (keepCustomer.mobile) keepPhoneSet.add(normalizePhone(keepCustomer.mobile));
      const keepExtraPhones = db.prepare('SELECT phone FROM customer_phones WHERE customer_id = ?').all(kid) as { phone: string }[];
      for (const p of keepExtraPhones) keepPhoneSet.add(p.phone);

      const mergePhoneRows = db.prepare('SELECT * FROM customer_phones WHERE customer_id = ?').all(mid) as AnyRow[];
      const insertPhone = db.prepare('INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, 0)');
      for (const p of mergePhoneRows) {
        if (!keepPhoneSet.has(p.phone)) {
          insertPhone.run(kid, p.phone, p.label || '');
          keepPhoneSet.add(p.phone);
        }
      }
      // Also add merge customer's main phone/mobile if not already present
      if (mergeCustomer.phone && !keepPhoneSet.has(normalizePhone(mergeCustomer.phone))) {
        insertPhone.run(kid, normalizePhone(mergeCustomer.phone), 'merged');
      }
      if (mergeCustomer.mobile && !keepPhoneSet.has(normalizePhone(mergeCustomer.mobile))) {
        insertPhone.run(kid, normalizePhone(mergeCustomer.mobile), 'merged');
      }

      // Merge email addresses (avoid duplicates)
      const keepEmailSet = new Set<string>();
      if (keepCustomer.email) keepEmailSet.add(keepCustomer.email.toLowerCase());
      const keepExtraEmails = db.prepare('SELECT email FROM customer_emails WHERE customer_id = ?').all(kid) as { email: string }[];
      for (const e of keepExtraEmails) keepEmailSet.add(e.email.toLowerCase());

      const mergeEmailRows = db.prepare('SELECT * FROM customer_emails WHERE customer_id = ?').all(mid) as AnyRow[];
      const insertEmail = db.prepare('INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, 0)');
      for (const e of mergeEmailRows) {
        if (!keepEmailSet.has(e.email.toLowerCase())) {
          insertEmail.run(kid, e.email, e.label || '');
          keepEmailSet.add(e.email.toLowerCase());
        }
      }
      if (mergeCustomer.email && !keepEmailSet.has(mergeCustomer.email.toLowerCase())) {
        insertEmail.run(kid, mergeCustomer.email, 'merged');
      }

      // Merge tags (combine, deduplicate)
      const keepTags: string[] = JSON.parse(keepCustomer.tags || '[]');
      const mergeTags: string[] = JSON.parse(mergeCustomer.tags || '[]');
      const combinedTags = [...new Set([...keepTags, ...mergeTags])];
      db.prepare('UPDATE customers SET tags = ? WHERE id = ?').run(JSON.stringify(combinedTags), kid);

      // Soft-delete the merged customer
      db.prepare("UPDATE customers SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?").run(mid);

      // Delete merge customer's phone/email records (data already merged)
      db.prepare('DELETE FROM customer_phones WHERE customer_id = ?').run(mid);
      db.prepare('DELETE FROM customer_emails WHERE customer_id = ?').run(mid);

      return {
        tickets_moved: db.prepare('SELECT changes() AS n').get() as AnyRow,
      };
    });

    mergeTransaction();

    audit(db, 'customer_merged', req.user!.id, req.ip || 'unknown', {
      keep_id: Number(keep_id),
      merge_id: Number(merge_id),
    });

    // Return the updated keep customer
    const [result, phones, emails] = await Promise.all([
      adb.get<AnyRow>(
        `SELECT c.*, cg.name AS customer_group_name
         FROM customers c
         LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
         WHERE c.id = ?`,
        Number(keep_id)),
      adb.all<AnyRow>('SELECT * FROM customer_phones WHERE customer_id = ?', Number(keep_id)),
      adb.all<AnyRow>('SELECT * FROM customer_emails WHERE customer_id = ?', Number(keep_id)),
    ]);

    res.json({
      success: true,
      data: { ...(result as AnyRow), phones, emails, message: `Customer ${merge_id} merged into ${keep_id}` },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /bulk-tag – Add a tag to multiple customers at once
// ENR-C4: Customer segmentation/bulk tagging
// ---------------------------------------------------------------------------
router.post(
  '/bulk-tag',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const { customer_ids, tag } = req.body;

    if (!Array.isArray(customer_ids) || customer_ids.length === 0) {
      throw new AppError('customer_ids array is required', 400);
    }
    if (!tag || typeof tag !== 'string' || tag.trim().length === 0) {
      throw new AppError('tag is required', 400);
    }
    if (customer_ids.length > 500) {
      throw new AppError('Maximum 500 customers per bulk tag operation', 400);
    }

    const trimmedTag = tag.trim();
    let updated = 0;

    const bulkTag = db.transaction(() => {
      for (const id of customer_ids) {
        const customer = db.prepare('SELECT id, tags FROM customers WHERE id = ? AND is_deleted = 0').get(Number(id)) as AnyRow | undefined;
        if (!customer) continue;

        const currentTags: string[] = JSON.parse(customer.tags || '[]');
        if (currentTags.includes(trimmedTag)) continue;

        const newTags = [...currentTags, trimmedTag];
        db.prepare("UPDATE customers SET tags = ?, updated_at = datetime('now') WHERE id = ?")
          .run(JSON.stringify(newTags), Number(id));
        updated++;
      }
    });

    bulkTag();

    res.json({
      success: true,
      data: { updated, tag: trimmedTag, total_requested: customer_ids.length },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /archive-inactive – Mark customers as inactive if no recent activity
// ENR-C9: Inactive customer archival
// ---------------------------------------------------------------------------
router.post(
  '/archive-inactive',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const adb = req.asyncDb;
    const { months } = req.body;

    if (!months || typeof months !== 'number' || months < 1 || months > 120) {
      throw new AppError('months must be a number between 1 and 120', 400);
    }

    // Find customers with no tickets or invoices in the last N months
    // and who are currently active and not deleted
    const cutoffDate = `-${months} months`;

    const result = await adb.run(`
      UPDATE customers SET is_active = 0, updated_at = datetime('now')
      WHERE is_deleted = 0
        AND is_active = 1
        AND id NOT IN (
          SELECT DISTINCT customer_id FROM tickets
          WHERE is_deleted = 0 AND created_at >= datetime('now', ?)
        )
        AND id NOT IN (
          SELECT DISTINCT customer_id FROM invoices
          WHERE created_at >= datetime('now', ?)
        )
    `, cutoffDate, cutoffDate);

    audit(req.db, 'customers_archived', req.user!.id, req.ip || 'unknown', {
      months,
      archived_count: result.changes,
    });

    res.json({
      success: true,
      data: { archived_count: result.changes, months },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /bulk-sms – Send SMS to multiple customers
// ENR-C10: Rate limited to 50 recipients per call
// ---------------------------------------------------------------------------
router.post(
  '/bulk-sms',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const { customer_ids, message, template_id } = req.body;

    if (!Array.isArray(customer_ids) || customer_ids.length === 0) {
      throw new AppError('customer_ids array is required', 400);
    }
    if (customer_ids.length > 50) {
      throw new AppError('Maximum 50 recipients per bulk SMS', 400);
    }

    let body = message || '';

    // Resolve template if provided
    let template: AnyRow | undefined;
    if (template_id && !body) {
      template = await adb.get<AnyRow>('SELECT * FROM sms_templates WHERE id = ? AND is_active = 1', Number(template_id));
      if (!template) throw new AppError('Template not found', 404);
    }

    if (!body && !template) {
      throw new AppError('message or template_id is required', 400);
    }

    const storePhoneRow = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'store_phone'");
    const storePhone = storePhoneRow?.value || '';
    const providerName = getSmsProvider().name;

    const results: { sent: number; failed: number; skipped: number; errors: { customer_id: number; error: string }[] } = {
      sent: 0, failed: 0, skipped: 0, errors: [],
    };

    for (const id of customer_ids) {
      const customer = await adb.get<AnyRow>(
        'SELECT id, first_name, last_name, phone, mobile, sms_opt_in FROM customers WHERE id = ? AND is_deleted = 0',
        Number(id));

      if (!customer) {
        results.skipped++;
        continue;
      }

      const phone = customer.mobile || customer.phone;
      if (!phone) {
        results.skipped++;
        results.errors.push({ customer_id: Number(id), error: 'No phone number' });
        continue;
      }

      // Build message body (with template substitution if applicable)
      let msgBody = body;
      if (template) {
        const vars: Record<string, string> = {
          first_name: customer.first_name || '',
          last_name: customer.last_name || '',
          name: `${customer.first_name || ''} ${customer.last_name || ''}`.trim(),
        };
        msgBody = template.content.replace(/\{\{(\w+)\}\}/g, (_: string, key: string) => vars[key] ?? `{{${key}}}`);
      }

      const convPhone = normalizePhone(phone);

      try {
        // Store outbound message
        const msgResult = await adb.run(`
          INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, user_id)
          VALUES (?, ?, ?, ?, 'sending', 'outbound', ?, 'customer', ?, ?)
        `, storePhone, phone, convPhone, msgBody, providerName, Number(id), userId);

        const msgId = msgResult.lastInsertRowid;

        const providerResult = await sendSms(phone, msgBody, storePhone);

        if (providerResult.success) {
          await adb.run("UPDATE sms_messages SET status = 'sent', provider_message_id = ?, updated_at = datetime('now') WHERE id = ?",
            providerResult.providerId || null, msgId);
          results.sent++;
        } else {
          await adb.run("UPDATE sms_messages SET status = 'failed', error = ?, updated_at = datetime('now') WHERE id = ?",
            providerResult.error || 'Unknown error', msgId);
          results.failed++;
          results.errors.push({ customer_id: Number(id), error: providerResult.error || 'Send failed' });
        }
      } catch (err: unknown) {
        results.failed++;
        const errMsg = err instanceof Error ? err.message : 'Unknown error';
        results.errors.push({ customer_id: Number(id), error: errMsg });
      }
    }

    res.json({ success: true, data: results });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create customer
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const input: CreateCustomerInput = req.body;

    if (!input.first_name) {
      throw new AppError('first_name is required');
    }

    // SEC-M10: Enforce max lengths on text inputs
    input.first_name = maxLen(input.first_name, 100)!;
    input.last_name = maxLen(input.last_name, 100);
    input.email = maxLen(input.email, 255);
    input.phone = maxLen(input.phone, 30);
    input.mobile = maxLen(input.mobile as string | undefined, 30);
    input.address1 = maxLen(input.address1, 500);
    input.city = maxLen(input.city, 100);
    input.state = maxLen(input.state, 100);
    input.organization = maxLen(input.organization, 200);
    input.comments = maxLen(input.comments as string | undefined, 5000);

    // Validate primary email format
    if (input.email && !isValidEmail(input.email)) {
      throw new AppError('Invalid email format', 400);
    }

    // Validate additional emails
    if (input.emails?.length) {
      for (const e of input.emails) {
        if (e.email && !isValidEmail(e.email)) {
          throw new AppError(`Invalid email format: ${e.email}`, 400);
        }
      }
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

    const [customer, phones, emails] = await Promise.all([
      adb.get<AnyRow>(
        `SELECT c.*, cg.name AS customer_group_name,
                cg.discount_pct AS group_discount_pct, cg.discount_type AS group_discount_type,
                cg.auto_apply AS group_auto_apply
         FROM customers c
         LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
         WHERE c.id = ?`,
        customerId),
      adb.all<AnyRow>('SELECT * FROM customer_phones WHERE customer_id = ?', customerId),
      adb.all<AnyRow>('SELECT * FROM customer_emails WHERE customer_id = ?', customerId),
    ]);

    // Fire automations (async, non-blocking)
    runAutomations(db, 'customer_created', { customer: { ...(customer as any), phones, emails } });

    res.status(201).json({
      success: true,
      data: { ...(customer as any), phones, emails },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /repeat – Repeat customers (3+ tickets in last 12 months)
// ---------------------------------------------------------------------------
router.get(
  '/repeat',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const minTickets = parseInt(req.query.min_tickets as string, 10) || 3;
    const months = parseInt(req.query.months as string, 10) || 12;

    const customers = await adb.all<AnyRow>(`
      SELECT c.id, c.first_name, c.last_name, c.email, c.phone, c.mobile,
             c.organization, c.code,
             COUNT(t.id) AS ticket_count,
             MAX(t.created_at) AS last_ticket_date,
             MIN(t.created_at) AS first_ticket_date
      FROM customers c
      JOIN tickets t ON t.customer_id = c.id AND t.is_deleted = 0
      WHERE c.is_deleted = 0
        AND t.created_at > datetime('now', ?)
      GROUP BY c.id
      HAVING COUNT(t.id) >= ?
      ORDER BY ticket_count DESC
    `, `-${months} months`, minTickets);

    res.json({ success: true, data: customers });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Customer detail
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);

    const customer = await adb.get<AnyRow>(
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
      id);

    if (!customer) throw new AppError('Customer not found', 404);

    const [phones, emails, assets, rfmData] = await Promise.all([
      adb.all<AnyRow>('SELECT * FROM customer_phones WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM customer_emails WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM customer_assets WHERE customer_id = ? ORDER BY created_at DESC', id),
      adb.get<any>(`
        SELECT
          MAX(t.created_at) AS last_visit,
          COUNT(DISTINCT t.id) AS visit_count,
          COALESCE(SUM(i.total), 0) AS total_spent
        FROM tickets t
        LEFT JOIN invoices i ON i.ticket_id = t.id AND i.status != 'void'
        WHERE t.customer_id = ? AND t.is_deleted = 0
      `, id),
    ]);

    let healthScore = 0;
    let healthLabel = 'new';

    if (rfmData) {
      // Recency: 0-40 points (last visit within 30/60/90/180 days)
      if (rfmData.last_visit) {
        const daysSince = Math.floor((Date.now() - new Date(rfmData.last_visit).getTime()) / 86_400_000);
        if (daysSince <= 30) healthScore += 40;
        else if (daysSince <= 60) healthScore += 30;
        else if (daysSince <= 90) healthScore += 20;
        else if (daysSince <= 180) healthScore += 10;
      }

      // Frequency: 0-30 points (number of visits)
      const visits = rfmData.visit_count || 0;
      if (visits >= 10) healthScore += 30;
      else if (visits >= 5) healthScore += 25;
      else if (visits >= 3) healthScore += 15;
      else if (visits >= 1) healthScore += 5;

      // Monetary: 0-30 points (total spent)
      const spent = rfmData.total_spent || 0;
      if (spent >= 1000) healthScore += 30;
      else if (spent >= 500) healthScore += 25;
      else if (spent >= 200) healthScore += 15;
      else if (spent >= 50) healthScore += 5;

      // Classify
      if (healthScore >= 80) healthLabel = 'champion';
      else if (healthScore >= 60) healthLabel = 'loyal';
      else if (healthScore >= 40) healthLabel = 'promising';
      else if (healthScore >= 20) healthLabel = 'at_risk';
      else if (rfmData.visit_count > 0) healthLabel = 'needs_attention';
      else healthLabel = 'new';
    }

    res.json({
      success: true,
      data: {
        ...(customer as any),
        phones,
        emails,
        assets,
        health_score: healthScore,
        health_label: healthLabel,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update customer
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const input: UpdateCustomerInput = req.body;

    const existing = await adb.get<any>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Customer not found', 404);

    // Validate primary email format
    if (input.email !== undefined && input.email && !isValidEmail(input.email)) {
      throw new AppError('Invalid email format', 400);
    }

    // Validate additional emails
    if (input.emails?.length) {
      for (const e of input.emails) {
        if (e.email && !isValidEmail(e.email)) {
          throw new AppError(`Invalid email format: ${e.email}`, 400);
        }
      }
    }

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
    const [customer, phones, emails] = await Promise.all([
      adb.get<AnyRow>(
        `SELECT c.*, cg.name AS customer_group_name,
                cg.discount_pct AS group_discount_pct,
                cg.discount_type AS group_discount_type,
                cg.auto_apply AS group_auto_apply,
                (SELECT COUNT(*) FROM tickets t WHERE t.customer_id = c.id AND t.is_deleted = 0) AS ticket_count,
                (SELECT COALESCE(SUM(i.total), 0) FROM invoices i WHERE i.customer_id = c.id) AS total_invoiced
         FROM customers c
         LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
         WHERE c.id = ?`,
        id),
      adb.all<AnyRow>('SELECT * FROM customer_phones WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM customer_emails WHERE customer_id = ?', id),
    ]);

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
    const adb = req.asyncDb;
    const id = Number(req.params.id);

    const existing = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Customer not found', 404);

    // Prevent deleting customers with open tickets
    const [openTicketsRow, unpaidInvoicesRow] = await Promise.all([
      adb.get<{ n: number }>(`
        SELECT COUNT(*) AS n FROM tickets t
        JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.customer_id = ? AND t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      `, id),
      adb.get<{ n: number }>(`
        SELECT COUNT(*) AS n FROM invoices
        WHERE customer_id = ? AND status IN ('unpaid', 'partial') AND status != 'void'
      `, id),
    ]);

    const openTickets = (openTicketsRow as { n: number }).n;
    if (openTickets > 0) {
      throw new AppError(`Cannot delete customer with ${openTickets} open ticket${openTickets > 1 ? 's' : ''}. Close or reassign them first.`, 400);
    }

    // Prevent deleting customers with unpaid invoices
    const unpaidInvoices = (unpaidInvoicesRow as { n: number }).n;
    if (unpaidInvoices > 0) {
      throw new AppError(`Cannot delete customer with ${unpaidInvoices} unpaid invoice${unpaidInvoices > 1 ? 's' : ''}. Settle or void them first.`, 400);
    }

    await adb.run(`UPDATE customers SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?`, id);
    audit(req.db, 'customer_deleted', req.user!.id, req.ip || 'unknown', { customer_id: id });

    res.json({ success: true, data: { message: 'Customer deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/analytics – Customer lifetime analytics
// ---------------------------------------------------------------------------
router.get(
  '/:id/analytics',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const stats = await adb.get<any>(`
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
    `, id);

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
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const existing = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    const { total } = await adb.get<{ total: number }>(
      'SELECT COUNT(*) as total FROM tickets WHERE customer_id = ? AND is_deleted = 0',
      customerId) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const rows = await adb.all<any>(
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
      customerId, pageSize, offset);

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
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const existing = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    const { total } = await adb.get<{ total: number }>(
      'SELECT COUNT(*) as total FROM invoices WHERE customer_id = ?',
      customerId) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const invoices = await adb.all<AnyRow>(
        `SELECT * FROM invoices
         WHERE customer_id = ?
         ORDER BY created_at DESC
         LIMIT ? OFFSET ?`,
      customerId, pageSize, offset);

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
// GET /:id/communications – Unified timeline: SMS + call logs + emails
// ENR-C5: Merged timeline sorted by date descending
// ---------------------------------------------------------------------------
router.get(
  '/:id/communications',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const typeFilter = (req.query.type as string || '').toLowerCase(); // 'sms', 'call', 'email', or '' for all

    const existing = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    // Collect all normalised phone numbers for this customer
    const [customer, extraPhones, extraEmails] = await Promise.all([
      adb.get<AnyRow>('SELECT phone, mobile, email FROM customers WHERE id = ?', customerId),
      adb.all<{ phone: string }>('SELECT phone FROM customer_phones WHERE customer_id = ?', customerId),
      adb.all<{ email: string }>('SELECT email FROM customer_emails WHERE customer_id = ?', customerId),
    ]);

    const phoneSet = new Set<string>();
    if (customer.phone) phoneSet.add(normalizePhone(customer.phone));
    if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
    for (const p of extraPhones) {
      const norm = normalizePhone(p.phone);
      if (norm) phoneSet.add(norm);
    }

    const emailSet = new Set<string>();
    if (customer.email) emailSet.add(customer.email.toLowerCase());
    for (const e of extraEmails) {
      if (e.email) emailSet.add(e.email.toLowerCase());
    }

    const phones = Array.from(phoneSet);
    const emails = Array.from(emailSet);
    const phonePlaceholders = phones.map(() => '?').join(', ');
    const emailPlaceholders = emails.map(() => '?').join(', ');

    // Build UNION ALL query for merged timeline
    const unionParts: string[] = [];
    const countParts: string[] = [];
    const unionParams: unknown[] = [];
    const countParams: unknown[] = [];

    // SMS messages
    if ((!typeFilter || typeFilter === 'sms') && phones.length > 0) {
      unionParts.push(`
        SELECT id, 'sms' AS comm_type, direction, from_number AS from_addr, to_number AS to_addr,
               message AS content, NULL AS subject, status, created_at
        FROM sms_messages WHERE conv_phone IN (${phonePlaceholders})
      `);
      countParts.push(`SELECT COUNT(*) AS n FROM sms_messages WHERE conv_phone IN (${phonePlaceholders})`);
      unionParams.push(...phones);
      countParams.push(...phones);
    }

    // Call logs
    if ((!typeFilter || typeFilter === 'call') && phones.length > 0) {
      unionParts.push(`
        SELECT id, 'call' AS comm_type, direction, from_number AS from_addr, to_number AS to_addr,
               transcription AS content, NULL AS subject, status, created_at
        FROM call_logs WHERE conv_phone IN (${phonePlaceholders})
      `);
      countParts.push(`SELECT COUNT(*) AS n FROM call_logs WHERE conv_phone IN (${phonePlaceholders})`);
      unionParams.push(...phones);
      countParams.push(...phones);
    }

    // Email messages (match on to_address or from_address)
    if ((!typeFilter || typeFilter === 'email') && emails.length > 0) {
      unionParts.push(`
        SELECT id, 'email' AS comm_type, 'outbound' AS direction, from_address AS from_addr, to_address AS to_addr,
               body AS content, subject, status, created_at
        FROM email_messages WHERE LOWER(to_address) IN (${emailPlaceholders}) OR LOWER(from_address) IN (${emailPlaceholders})
      `);
      countParts.push(`SELECT COUNT(*) AS n FROM email_messages WHERE LOWER(to_address) IN (${emailPlaceholders}) OR LOWER(from_address) IN (${emailPlaceholders})`);
      unionParams.push(...emails, ...emails);
      countParams.push(...emails, ...emails);
    }

    if (unionParts.length === 0) {
      return void res.json({
        success: true,
        data: {
          communications: [],
          pagination: { page, per_page: pageSize, total: 0, total_pages: 0 },
        },
      });
    }

    // Total count across all sources — parallelize count queries
    const countPromises: Promise<{ n: number } | undefined>[] = [];
    let paramOffset = 0;
    for (const sql of countParts) {
      const paramCount = (sql.match(/\?/g) || []).length;
      const params = countParams.slice(paramOffset, paramOffset + paramCount);
      countPromises.push(adb.get<{ n: number }>(sql, ...params));
      paramOffset += paramCount;
    }
    const countRows = await Promise.all(countPromises);
    let totalCount = 0;
    for (const row of countRows) {
      totalCount += row?.n ?? 0;
    }

    const totalPages = Math.ceil(totalCount / pageSize);
    const offset = (page - 1) * pageSize;

    const unionSql = `
      SELECT * FROM (${unionParts.join(' UNION ALL ')})
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;

    const communications = await adb.all<AnyRow>(unionSql, ...unionParams, pageSize, offset);

    res.json({
      success: true,
      data: {
        communications,
        pagination: { page, per_page: pageSize, total: totalCount, total_pages: totalPages },
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
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);

    const existing = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    const assets = await adb.all<AnyRow>(
      'SELECT * FROM customer_assets WHERE customer_id = ? ORDER BY created_at DESC',
      customerId);

    res.json({ success: true, data: assets });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/assets – Add asset
// ---------------------------------------------------------------------------
router.post(
  '/:id/assets',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);
    const { name, device_type, serial, imei, color, notes } = req.body;

    const existing = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerId);
    if (!existing) throw new AppError('Customer not found', 404);

    if (!name) throw new AppError('Asset name is required');

    const result = await adb.run(
        `INSERT INTO customer_assets (customer_id, name, device_type, serial, imei, color, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      customerId, name, device_type ?? null, serial ?? null, imei ?? null, color ?? null, notes ?? null);

    const asset = await adb.get<AnyRow>('SELECT * FROM customer_assets WHERE id = ?', result.lastInsertRowid);
    res.status(201).json({ success: true, data: asset });
  }),
);

// ---------------------------------------------------------------------------
// PUT /assets/:assetId – Update asset
// ---------------------------------------------------------------------------
router.put(
  '/assets/:assetId',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const assetId = Number(req.params.assetId);
    const { name, device_type, serial, imei, color, notes } = req.body;

    const existing = await adb.get<any>('SELECT * FROM customer_assets WHERE id = ?', assetId);
    if (!existing) throw new AppError('Asset not found', 404);

    await adb.run(
      `UPDATE customer_assets
       SET name = ?, device_type = ?, serial = ?, imei = ?, color = ?, notes = ?, updated_at = datetime('now')
       WHERE id = ?`,
      name ?? existing.name,
      device_type !== undefined ? device_type : existing.device_type,
      serial !== undefined ? serial : existing.serial,
      imei !== undefined ? imei : existing.imei,
      color !== undefined ? color : existing.color,
      notes !== undefined ? notes : existing.notes,
      assetId,
    );

    const asset = await adb.get<AnyRow>('SELECT * FROM customer_assets WHERE id = ?', assetId);
    res.json({ success: true, data: asset });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /assets/:assetId – Delete asset
// ---------------------------------------------------------------------------
router.delete(
  '/assets/:assetId',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const assetId = Number(req.params.assetId);

    const existing = await adb.get<AnyRow>('SELECT id FROM customer_assets WHERE id = ?', assetId);
    if (!existing) throw new AppError('Asset not found', 404);

    await adb.run('DELETE FROM customer_assets WHERE id = ?', assetId);

    res.json({ success: true, data: { message: 'Asset deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/export – GDPR data portability export
// ENR-C3: Returns all customer data as JSON
// ---------------------------------------------------------------------------
router.get(
  '/:id/export',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);

    const customer = await adb.get<AnyRow>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', id);
    if (!customer) throw new AppError('Customer not found', 404);

    // First batch: independent reads that don't depend on each other
    const [phones, emails, assets, tickets, invoices, estimates, loanerHistory] = await Promise.all([
      adb.all<AnyRow>('SELECT * FROM customer_phones WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM customer_emails WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM customer_assets WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM tickets WHERE customer_id = ? AND is_deleted = 0', id),
      adb.all<AnyRow>('SELECT * FROM invoices WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM estimates WHERE customer_id = ?', id),
      adb.all<AnyRow>('SELECT * FROM loaner_history WHERE customer_id = ?', id),
    ]);

    // Ticket-related data (depends on tickets result)
    const ticketIds = tickets.map((t) => t.id);
    let ticketNotes: AnyRow[] = [];
    let ticketDevices: AnyRow[] = [];
    if (ticketIds.length > 0) {
      const ticketPlaceholders = ticketIds.map(() => '?').join(', ');
      [ticketNotes, ticketDevices] = await Promise.all([
        adb.all<AnyRow>(`SELECT * FROM ticket_notes WHERE ticket_id IN (${ticketPlaceholders})`, ...ticketIds),
        adb.all<AnyRow>(`SELECT * FROM ticket_devices WHERE ticket_id IN (${ticketPlaceholders})`, ...ticketIds),
      ]);
    }

    // SMS messages (by phone)
    const phoneSet = new Set<string>();
    if (customer.phone) phoneSet.add(normalizePhone(customer.phone));
    if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
    for (const p of phones as AnyRow[]) {
      const norm = normalizePhone(p.phone);
      if (norm) phoneSet.add(norm);
    }
    const phoneList = Array.from(phoneSet);
    let smsMessages: AnyRow[] = [];
    if (phoneList.length > 0) {
      const phonePlaceholders = phoneList.map(() => '?').join(', ');
      smsMessages = await adb.all<AnyRow>(`SELECT * FROM sms_messages WHERE conv_phone IN (${phonePlaceholders})`, ...phoneList);
    }

    // Email messages
    const emailSet = new Set<string>();
    if (customer.email) emailSet.add(customer.email.toLowerCase());
    for (const e of emails as AnyRow[]) {
      if (e.email) emailSet.add(e.email.toLowerCase());
    }
    const emailList = Array.from(emailSet);
    let emailMessages: AnyRow[] = [];
    if (emailList.length > 0) {
      const emailPlaceholders = emailList.map(() => '?').join(', ');
      emailMessages = await adb.all<AnyRow>(
        `SELECT * FROM email_messages WHERE LOWER(to_address) IN (${emailPlaceholders}) OR LOWER(from_address) IN (${emailPlaceholders})`,
        ...emailList, ...emailList);
    }

    const exportData = {
      exported_at: new Date().toISOString(),
      customer,
      phones,
      emails,
      assets,
      tickets,
      ticket_notes: ticketNotes,
      ticket_devices: ticketDevices,
      invoices,
      estimates,
      sms_messages: smsMessages,
      email_messages: emailMessages,
      loaner_history: loanerHistory,
    };

    audit(req.db, 'customer_data_exported', req.user!.id, req.ip || 'unknown', { customer_id: id });

    res.json({ success: true, data: exportData });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id/gdpr-erase – GDPR erasure (hard delete all customer data)
// ENR-C3: Admin-only, requires password confirmation
// ---------------------------------------------------------------------------
router.delete(
  '/:id/gdpr-erase',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const { password } = req.body;

    if (!password) throw new AppError('Password confirmation is required for GDPR erasure', 400);

    // Verify admin password
    const [adminUser, customer] = await Promise.all([
      adb.get<AnyRow>('SELECT password_hash FROM users WHERE id = ?', req.user!.id),
      adb.get<AnyRow>('SELECT * FROM customers WHERE id = ?', id),
    ]);
    if (!adminUser) throw new AppError('User not found', 404);

    const passwordValid = bcrypt.compareSync(password, adminUser.password_hash);
    if (!passwordValid) throw new AppError('Invalid password', 401);

    if (!customer) throw new AppError('Customer not found', 404);

    const eraseTransaction = db.transaction(() => {
      // Delete customer phones and emails
      db.prepare('DELETE FROM customer_phones WHERE customer_id = ?').run(id);
      db.prepare('DELETE FROM customer_emails WHERE customer_id = ?').run(id);

      // Delete customer assets
      db.prepare('DELETE FROM customer_assets WHERE customer_id = ?').run(id);

      // Delete loaner history for this customer
      db.prepare('DELETE FROM loaner_history WHERE customer_id = ?').run(id);

      // Anonymize ticket references (keep tickets for business records but remove customer link)
      db.prepare("UPDATE tickets SET customer_id = 0 WHERE customer_id = ?").run(id);

      // Anonymize invoice references
      db.prepare("UPDATE invoices SET customer_id = 0 WHERE customer_id = ?").run(id);

      // Anonymize estimate references
      db.prepare("UPDATE estimates SET customer_id = 0 WHERE customer_id = ?").run(id);

      // Delete SMS messages linked to customer's phone numbers
      const phoneSet = new Set<string>();
      if (customer.phone) phoneSet.add(normalizePhone(customer.phone));
      if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
      if (phoneSet.size > 0) {
        const phoneList = Array.from(phoneSet);
        const phonePlaceholders = phoneList.map(() => '?').join(', ');
        db.prepare(`DELETE FROM sms_messages WHERE conv_phone IN (${phonePlaceholders})`).run(...phoneList);
        db.prepare(`DELETE FROM call_logs WHERE conv_phone IN (${phonePlaceholders})`).run(...phoneList);
      }

      // Delete email messages
      const emailSet = new Set<string>();
      if (customer.email) emailSet.add(customer.email.toLowerCase());
      if (emailSet.size > 0) {
        const emailList = Array.from(emailSet);
        const emailPlaceholders = emailList.map(() => '?').join(', ');
        db.prepare(`DELETE FROM email_messages WHERE LOWER(to_address) IN (${emailPlaceholders}) OR LOWER(from_address) IN (${emailPlaceholders})`)
          .run(...emailList, ...emailList);
      }

      // Hard delete the customer record
      db.prepare('DELETE FROM customers WHERE id = ?').run(id);
    });

    eraseTransaction();

    audit(db, 'customer_gdpr_erased', req.user!.id, req.ip || 'unknown', {
      customer_id: id,
      customer_name: `${customer.first_name} ${customer.last_name}`.trim(),
    });

    res.json({
      success: true,
      data: { message: `All data for customer ${id} has been permanently erased` },
    });
  }),
);

export default router;
