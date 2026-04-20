import fs from 'fs';
import path from 'path';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requirePermission } from '../middleware/auth.js';
import { normalizePhone } from '../utils/phone.js';
import { generateOrderId } from '../utils/format.js';
import { runAutomations } from '../services/automations.js';
import { audit } from '../utils/audit.js';
import { shouldAuditCustomerView } from '../utils/customerViewAudit.js';
import { sendSms, getSmsProvider } from '../services/smsProvider.js';
import {
  validateEmail,
  validatePhoneDigits,
  validateRequiredString,
} from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import type { CreateCustomerInput, UpdateCustomerInput } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { config } from '../config.js';
import { requireStepUpTotp } from '../middleware/stepUpTotp.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';

type AnyRow = Record<string, any>;

const log = createLogger('customers');

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const maxLen = (val: string | undefined, max: number) => val && val.length > max ? val.slice(0, max) : val;

/**
 * Normalise a phone input and enforce length/format via `validatePhoneDigits`.
 * Returns the normalised digit string, or null when the input was empty.
 * Throws `AppError` when the client sent non-empty garbage like "test test"
 * whose normalised form is empty or shorter than 10 digits (V1).
 *
 * Pass `fieldName` to produce clearer error messages when there are multiple
 * phone fields on the same record (phone vs mobile).
 */
function normaliseAndValidatePhone(
  raw: unknown,
  fieldName = 'phone',
): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'string') {
    throw new AppError(`${fieldName} must be a string`, 400);
  }
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const digits = normalizePhone(trimmed) || '';
  // `normalizePhone` strips everything that is not a digit. If the client
  // sent something non-empty that collapsed to an empty string (e.g.
  // "test test") or to a too-short sequence, reject instead of silently
  // storing NULL.
  return validatePhoneDigits(digits, fieldName, true);
}

const CUSTOMER_COLUMNS = [
  'first_name', 'last_name', 'title', 'organization', 'type',
  'email', 'phone', 'mobile',
  'address1', 'address2', 'city', 'state', 'postcode', 'country',
  'contact_person', 'contact_relation',
  'referred_by', 'customer_group_id',
  'tax_number', 'tax_class_id',
  'email_opt_in', 'sms_opt_in',
  'sms_consent_marketing', 'sms_consent_transactional',
  'sms_quiet_hours_start', 'sms_quiet_hours_end',
  'comments', 'source', 'tags',
] as const;

/** Sanitise an FTS5 MATCH term – double-quote each token so special chars are safe. */
function ftsMatchExpr(keyword: string): string {
  // DA-3: bound the raw input BEFORE regex/split/map run so a multi-megabyte
  // ?keyword= query cannot lock the event loop. 200 chars is enough for any
  // realistic customer search — typical is under 40.
  const bounded = typeof keyword === 'string' ? keyword.slice(0, 200) : '';
  // Strip all non-alphanumeric except spaces and hyphens to prevent FTS injection.
  // Regex has no nested quantifiers — linear time, not ReDoS-vulnerable.
  const cleaned = bounded.replace(/[^a-zA-Z0-9\s\-@.]/g, '').trim();
  const tokens = cleaned.split(/\s+/).filter(Boolean).slice(0, 16);
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
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);
    const keyword = (req.query.keyword as string || '').trim();
    const groupId = req.query.group_id ? parseInt(req.query.group_id as string, 10) : null;
    const sortBy = (req.query.sort_by as string) || 'created_at';
    const sortOrder = (req.query.sort_order as string || 'DESC').toUpperCase() === 'ASC' ? 'ASC' : 'DESC';
    const includeStats = req.query.include_stats === '1';
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();
    const hasOpenTickets = req.query.has_open_tickets as string | undefined;

    // PROD21: Whitelist sortable columns. `safeSortBy` is spliced into SQL
    // below (`ORDER BY ${orderColumn} ${sortOrder}`) so both the column and
    // direction MUST come from a static allow-list — never from req.*
    // directly. `sortOrder` is constrained to ASC/DESC, and `allowedSorts`
    // is the only source of column names. Any unknown value falls back to
    // 'created_at'.
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
        // Phone search: match digits against phone/mobile columns (strip formatting).
        // `digits` is already stripped to [0-9] by the regex above so there is no
        // LIKE wildcard to escape, but we still route through escapeLike to stay
        // consistent and defensive if the upstream pattern ever changes.
        conditions.push(`(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.phone, ' ', ''), '-', ''), '(', ''), ')', ''), '+', '') LIKE ? ESCAPE '\\' OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.mobile, ' ', ''), '-', ''), '(', ''), ')', ''), '+', '') LIKE ? ESCAPE '\\')`);
        const digitPattern = `%${escapeLike(digits.slice(-10))}%`; // last 10 digits (strip country code)
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

    // SEC-H55: audit PII-accessing list scan. One row per page (not per
    // customer) with the id list in details — keeps audit_logs small while
    // retaining the forensic link "user X saw customers [a, b, c] at time T".
    // Coalesced 5 minutes per (user, kind, filter-fingerprint): the same
    // scan repeated inside the window writes once. Scrolling to a new page
    // or changing filters produces a distinct fingerprint → fresh row.
    if (customers.length > 0) {
      const userId = req.user?.id ?? null;
      const filterFingerprint = JSON.stringify({
        kw: keyword || null,
        gid: groupId ?? null,
        sort: `${safeSortBy}:${sortOrder}`,
        stats: includeStats ? 1 : 0,
        from: fromDate || null,
        to: toDate || null,
        open: hasOpenTickets ?? null,
        off: offset,
        ps: pageSize,
      });
      const coalesceKey = `${userId ?? 'anon'}:list-with-stats:${filterFingerprint}`;
      if (shouldAuditCustomerView(coalesceKey)) {
        audit(req.db, 'customer_viewed', userId, req.ip || 'unknown', {
          via: 'list-with-stats',
          tenant: req.tenantSlug ?? null,
          count: customers.length,
          customer_ids: customers.map((c) => Number((c as AnyRow).id)).filter(Boolean),
          page,
          per_page: pageSize,
          include_stats: includeStats,
        });
      }
    }

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
        results = await likeSearch(adb, q);
      }
    } else {
      results = await likeSearch(adb, q);
    }

    res.json({ success: true, data: results });
  }),
);

async function likeSearch(adb: AsyncDb, q: string) {
  // Escape %, _, \ so a user typing a raw wildcard can't widen the match
  // (enumeration / DoS). ESCAPE '\' makes SQLite honour the backslashes
  // inserted by escapeLike().
  const like = `%${escapeLike(q)}%`;
  return adb.all<AnyRow>(
    `SELECT c.id, c.code, c.first_name, c.last_name, c.phone, c.mobile, c.email, c.organization,
            c.customer_group_id, cg.name AS customer_group_name,
            cg.discount_pct AS group_discount_pct, cg.discount_type AS group_discount_type,
            cg.auto_apply AS group_auto_apply
     FROM customers c
     LEFT JOIN customer_groups cg ON cg.id = c.customer_group_id
     WHERE c.is_deleted = 0
       AND (c.first_name LIKE ? ESCAPE '\\' OR c.last_name LIKE ? ESCAPE '\\' OR c.phone LIKE ? ESCAPE '\\' OR c.mobile LIKE ? ESCAPE '\\' OR c.email LIKE ? ESCAPE '\\' OR c.organization LIKE ? ESCAPE '\\')
     LIMIT 10`,
    like, like, like, like, like, like,
  );
}

// ---------------------------------------------------------------------------
// Customer group CRUD lives in settings.routes.ts (/api/v1/settings/customer-groups).
// Use settingsApi on the frontend for all group operations.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// POST /import-csv – Bulk create customers from CSV data
// SEC-H8: Admin or manager role required for bulk import operations
// SEC-H25: gate behind settings.import_export permission in the middleware chain.
// The inline role check below is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.post(
  '/import-csv',
  requirePermission('settings.import_export'),
  asyncHandler(async (req, res) => {
    // Defence-in-depth: requirePermission above is authoritative.
    if (req.user?.role !== 'admin' && req.user?.role !== 'manager') throw new AppError('Admin or manager access required', 403);
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

    for (let i = 0; i < items.length; i++) {
      const row = items[i];
      try {
        // V4: Apply the same validation used by POST /. Bad rows are reported
        // per-row in the errors array instead of being silently accepted.
        const firstName = validateRequiredString(row.first_name, 'first_name', 100);

        // Phone/mobile: only validate if the row actually sent something.
        // CSVs often only populate one of the two and an empty field is fine.
        let phone: string | null = null;
        let mobile: string | null = null;
        if (row.phone !== undefined && row.phone !== null && String(row.phone).trim() !== '') {
          phone = normaliseAndValidatePhone(String(row.phone), 'phone');
        }
        if (row.mobile !== undefined && row.mobile !== null && String(row.mobile).trim() !== '') {
          mobile = normaliseAndValidatePhone(String(row.mobile), 'mobile');
        }

        const email = validateEmail(row.email, 'email', false);

        // Optional duplicate check: skip row if phone, mobile, or email already exists
        if (skip_duplicates) {
          if ((phone && existingPhones.has(phone)) ||
              (mobile && existingPhones.has(mobile)) ||
              (email && existingEmails.has(email))) {
            results.skipped++;
            continue;
          }
        }

        const result = await adb.run(`
          INSERT INTO customers (first_name, last_name, email, phone, mobile, organization, city, state, postcode, address1, source)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
          firstName, row.last_name || '', email, phone, mobile,
          row.organization || null, row.city || null, row.state || null, row.postcode || null,
          row.address1 || null, 'csv_import',
        );
        const customerId = result.lastInsertRowid as number;
        const code = generateOrderId('C', customerId);
        await adb.run('UPDATE customers SET code = ? WHERE id = ?', code, customerId);
        results.created++;

        // Track newly created entries so subsequent rows in the same batch
        // are also checked against earlier rows (not just pre-existing DB records)
        if (skip_duplicates) {
          if (phone) existingPhones.add(phone);
          if (mobile) existingPhones.add(mobile);
          if (email) existingEmails.add(email);
        }
      } catch (err: unknown) {
        // V4 + E1: only the validator messages (AppError) are safe to echo
        // back to the client. Anything else (DB errors, programmer errors)
        // is logged server-side and replaced with a generic string so we
        // do not leak schema / stack / SQL text through the import report.
        if (err instanceof AppError) {
          results.errors.push({ row: i + 1, error: err.message });
        } else {
          log.error('Customer CSV import row failed', {
            row: i + 1,
            error: err instanceof Error ? err.message : String(err),
          });
          results.errors.push({ row: i + 1, error: 'Row rejected due to a server error' });
        }
      }
    }

    res.json({ success: true, data: results });
  }),
);

// ---------------------------------------------------------------------------
// POST /merge – Merge/deduplicate two customers
// ENR-C1: Move all tickets, invoices, SMS, assets from merge_id → keep_id.
//         Merge phone numbers and emails (avoid duplicates). Soft-delete merged.
// SEC-H25: merge is a destructive bulk operation — gate behind customers.merge.
// The inline role check below is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.post(
  '/merge',
  requirePermission('customers.merge'),
  asyncHandler(async (req, res) => {
    // Defence-in-depth: requirePermission above is authoritative.
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const adb = req.asyncDb;
    const { keep_id, merge_id } = req.body;

    if (!keep_id || !merge_id) throw new AppError('keep_id and merge_id are required', 400);
    const kid = Number(keep_id);
    const mid = Number(merge_id);
    if (!Number.isFinite(kid) || !Number.isFinite(mid) || !Number.isInteger(kid) || !Number.isInteger(mid) || kid <= 0 || mid <= 0) {
      throw new AppError('keep_id and merge_id must be positive integers', 400);
    }
    if (kid === mid) throw new AppError('Cannot merge a customer into itself', 400);

    const [keepCustomer, mergeCustomer] = await Promise.all([
      adb.get<AnyRow>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', kid),
      adb.get<AnyRow>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', mid),
    ]);
    if (!keepCustomer) throw new AppError('Keep customer not found', 404);
    if (!mergeCustomer) throw new AppError('Merge customer not found', 404);

    // Move tickets
    await adb.run('UPDATE tickets SET customer_id = ? WHERE customer_id = ?', kid, mid);

    // Move invoices
    await adb.run('UPDATE invoices SET customer_id = ? WHERE customer_id = ?', kid, mid);

    // Move estimates
    await adb.run('UPDATE estimates SET customer_id = ? WHERE customer_id = ?', kid, mid);

    // Move SMS messages — match by merge customer's phone numbers
    // @audit-fixed: skip empty/undefined results from normalizePhone() so the array
    // doesn't carry stray "" / undefined entries downstream (and so the unused
    // mergePhones list is at least sane if a future change starts using it).
    const mergePhones: string[] = [];
    const pushPhone = (raw: unknown) => {
      const norm = raw ? normalizePhone(String(raw)) : '';
      if (norm) mergePhones.push(norm);
    };
    if (mergeCustomer.phone) pushPhone(mergeCustomer.phone);
    if (mergeCustomer.mobile) pushPhone(mergeCustomer.mobile);
    const mergeExtraPhones = await adb.all<{ phone: string }>('SELECT phone FROM customer_phones WHERE customer_id = ?', mid);
    for (const p of mergeExtraPhones) pushPhone(p.phone);
    // Update SMS conv_phone to keep customer's primary phone where applicable
    // (SMS are matched by phone, so we just ensure they can be found via keep's phones)

    // Move assets
    await adb.run('UPDATE customer_assets SET customer_id = ? WHERE customer_id = ?', kid, mid);

    // Move loaner history
    await adb.run('UPDATE loaner_history SET customer_id = ? WHERE customer_id = ?', kid, mid);

    // Merge phone numbers (avoid duplicates)
    const keepPhoneSet = new Set<string>();
    if (keepCustomer.phone) keepPhoneSet.add(normalizePhone(keepCustomer.phone));
    if (keepCustomer.mobile) keepPhoneSet.add(normalizePhone(keepCustomer.mobile));
    const keepExtraPhones = await adb.all<{ phone: string }>('SELECT phone FROM customer_phones WHERE customer_id = ?', kid);
    for (const p of keepExtraPhones) keepPhoneSet.add(p.phone);

    const mergePhoneRows = await adb.all<AnyRow>('SELECT * FROM customer_phones WHERE customer_id = ?', mid);
    for (const p of mergePhoneRows) {
      if (!keepPhoneSet.has(p.phone)) {
        await adb.run('INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, 0)', kid, p.phone, p.label || '');
        keepPhoneSet.add(p.phone);
      }
    }
    // Also add merge customer's main phone/mobile if not already present
    if (mergeCustomer.phone && !keepPhoneSet.has(normalizePhone(mergeCustomer.phone))) {
      await adb.run('INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, 0)', kid, normalizePhone(mergeCustomer.phone), 'merged');
    }
    if (mergeCustomer.mobile && !keepPhoneSet.has(normalizePhone(mergeCustomer.mobile))) {
      await adb.run('INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, 0)', kid, normalizePhone(mergeCustomer.mobile), 'merged');
    }

    // Merge email addresses (avoid duplicates)
    const keepEmailSet = new Set<string>();
    if (keepCustomer.email) keepEmailSet.add(keepCustomer.email.toLowerCase());
    const keepExtraEmails = await adb.all<{ email: string }>('SELECT email FROM customer_emails WHERE customer_id = ?', kid);
    for (const e of keepExtraEmails) keepEmailSet.add(e.email.toLowerCase());

    const mergeEmailRows = await adb.all<AnyRow>('SELECT * FROM customer_emails WHERE customer_id = ?', mid);
    for (const e of mergeEmailRows) {
      if (!keepEmailSet.has(e.email.toLowerCase())) {
        await adb.run('INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, 0)', kid, e.email, e.label || '');
        keepEmailSet.add(e.email.toLowerCase());
      }
    }
    if (mergeCustomer.email && !keepEmailSet.has(mergeCustomer.email.toLowerCase())) {
      await adb.run('INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, 0)', kid, mergeCustomer.email, 'merged');
    }

    // Merge tags (combine, deduplicate)
    // @audit-fixed: parseTags helper — JSON.parse without try/catch used to crash
    // the merge for any customer whose tags column held legacy non-JSON content.
    const parseTags = (raw: unknown): string[] => {
      if (!raw) return [];
      try {
        const v = JSON.parse(String(raw));
        return Array.isArray(v) ? v.filter((t) => typeof t === 'string') : [];
      } catch { return []; }
    };
    const keepTags = parseTags(keepCustomer.tags);
    const mergeTags = parseTags(mergeCustomer.tags);
    const combinedTags = [...new Set([...keepTags, ...mergeTags])];
    await adb.run('UPDATE customers SET tags = ? WHERE id = ?', JSON.stringify(combinedTags), kid);

    // Soft-delete the merged customer
    await adb.run("UPDATE customers SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?", mid);

    // Delete merge customer's phone/email records (data already merged)
    await adb.run('DELETE FROM customer_phones WHERE customer_id = ?', mid);
    await adb.run('DELETE FROM customer_emails WHERE customer_id = ?', mid);

    audit(req.db, 'customer_merged', req.user!.id, req.ip || 'unknown', {
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
// SEC-H25: gate behind customers.bulk_tag permission.
// ---------------------------------------------------------------------------
router.post(
  '/bulk-tag',
  requirePermission('customers.bulk_tag'),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
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

    for (const id of customer_ids) {
      // @audit-fixed: validate id and skip non-numeric entries silently rather
      // than letting Number("abc") = NaN flow into SQL.
      const cid = Number(id);
      if (!Number.isInteger(cid) || cid <= 0) continue;
      const customer = await adb.get<AnyRow>('SELECT id, tags FROM customers WHERE id = ? AND is_deleted = 0', cid);
      if (!customer) continue;

      // @audit-fixed: parseTags fallback — malformed legacy JSON used to crash
      // the bulk-tag loop on the first bad row.
      let currentTags: string[];
      try {
        const parsed = JSON.parse(customer.tags || '[]');
        currentTags = Array.isArray(parsed) ? parsed.filter((t: unknown) => typeof t === 'string') : [];
      } catch { currentTags = []; }
      if (currentTags.includes(trimmedTag)) continue;

      const newTags = [...currentTags, trimmedTag];
      await adb.run("UPDATE customers SET tags = ?, updated_at = datetime('now') WHERE id = ?",
        JSON.stringify(newTags), cid);
      updated++;
    }

    res.json({
      success: true,
      data: { updated, tag: trimmedTag, total_requested: customer_ids.length },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /archive-inactive – Mark customers as inactive if no recent activity
// ENR-C9: Inactive customer archival
// SEC-H25: archiving customers is a bulk write — gate behind customers.archive.
// The inline role check below is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.post(
  '/archive-inactive',
  requirePermission('customers.archive'),
  asyncHandler(async (req, res) => {
    // Defence-in-depth: requirePermission above is authoritative.
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
// R3: hard cap of 1000 recipients per request. Campaigns with > 100
// recipients must send `confirmed_large_send: true` as a double-check so
// an accidental "click all customers + send" cannot quietly fan out to
// hundreds of people before the caller can cancel.
// ---------------------------------------------------------------------------
const BULK_SMS_HARD_CAP = 1000;
const BULK_SMS_CONFIRM_THRESHOLD = 100;

// SEC-H25: bulk SMS broadcast is a privileged communication — gate behind sms.send.
router.post(
  '/bulk-sms',
  requirePermission('sms.send'),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const { customer_ids, message, template_id, confirmed_large_send } = req.body;

    if (!Array.isArray(customer_ids) || customer_ids.length === 0) {
      throw new AppError('customer_ids array is required', 400);
    }
    if (customer_ids.length > BULK_SMS_HARD_CAP) {
      throw new AppError(
        `Maximum ${BULK_SMS_HARD_CAP} recipients per bulk SMS request`,
        400,
      );
    }
    if (
      customer_ids.length > BULK_SMS_CONFIRM_THRESHOLD &&
      confirmed_large_send !== true
    ) {
      throw new AppError(
        `Large send (> ${BULK_SMS_CONFIRM_THRESHOLD} recipients) requires confirmed_large_send: true`,
        400,
      );
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

      // ENR-SMS2: Validate SMS opt-in for bulk/broadcast messages
      if (!customer.sms_opt_in) {
        results.skipped++;
        results.errors.push({ customer_id: Number(id), error: 'SMS opt-in not enabled' });
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
        // E1: Do not echo raw error messages from the DB / SMS provider to
        // the client. Log the real error server-side and return a generic
        // message for each failed recipient.
        results.failed++;
        log.error('Bulk SMS send failed for customer', {
          customer_id: Number(id),
          error: err instanceof Error ? err.message : String(err),
        });
        results.errors.push({ customer_id: Number(id), error: 'Send failed' });
      }
    }

    res.json({ success: true, data: results });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create customer
// SEC-H25: creating a customer is a write operation — gate behind customers.create.
// ---------------------------------------------------------------------------
router.post(
  '/',
  requirePermission('customers.create'),
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const input: CreateCustomerInput = req.body;

    // V3: Reject whitespace-only / missing first_name. validateRequiredString
    // trims and enforces a max length after trimming (SEC-M10).
    input.first_name = validateRequiredString(input.first_name, 'first_name', 100);

    // SEC-M10: Enforce max lengths on the remaining text inputs.
    input.last_name = maxLen(input.last_name, 100);
    input.phone = maxLen(input.phone, 30);
    input.mobile = maxLen(input.mobile as string | undefined, 30);
    input.address1 = maxLen(input.address1, 500);
    input.city = maxLen(input.city, 100);
    input.state = maxLen(input.state, 100);
    input.organization = maxLen(input.organization, 200);
    input.comments = maxLen(input.comments as string | undefined, 5000);

    // V2: Validate primary email with the shared validator. It returns the
    // trimmed, lowercased form or null. Emails longer than 255 chars are
    // rejected inside the validator (it caps at 254).
    const primaryEmail = validateEmail(input.email, 'email', false);
    input.email = primaryEmail ?? undefined;

    // Validate additional emails using the same validator.
    if (input.emails?.length) {
      for (const e of input.emails) {
        if (e.email) {
          e.email = validateEmail(e.email, 'email', true) as string;
        }
      }
    }

    // V1: Normalise + enforce length on primary phones. Garbage like
    // "test test" used to collapse to an empty string and be stored as NULL.
    const phone = normaliseAndValidatePhone(input.phone, 'phone');
    const mobile = normaliseAndValidatePhone(input.mobile, 'mobile');

    // Also validate any additional phone entries.
    if (input.phones?.length) {
      for (const p of input.phones) {
        if (p.phone) {
          p.phone = normaliseAndValidatePhone(p.phone, 'phone') as string;
        }
      }
    }

    // Check for duplicate phone numbers (warn, don't block — unless force_create is false)
    if (!input.force_create) {
      const phoneToCheck = mobile || phone;
      if (phoneToCheck) {
        const existing = await adb.get<AnyRow>(`
          SELECT c.id, c.first_name, c.last_name FROM customers c
          WHERE c.is_deleted = 0 AND (c.phone = ? OR c.mobile = ?)
          LIMIT 1
        `, phoneToCheck, phoneToCheck);
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
        const existing = await adb.get<AnyRow>(`
          SELECT c.id, c.first_name, c.last_name FROM customers c
          WHERE c.is_deleted = 0 AND LOWER(c.email) = ?
          LIMIT 1
        `, emailToCheck);
        if (existing) {
          throw new AppError(
            `Email already belongs to ${existing.first_name} ${existing.last_name || ''} (ID: ${existing.id}). Send force_create: true to override.`,
            409,
          );
        }
      }
    }

    const result = await adb.run(
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
    await adb.run('UPDATE customers SET code = ? WHERE id = ?', code, customerId);

    // Phones
    if (input.phones?.length) {
      for (const p of input.phones) {
        await adb.run(
          'INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, ?)',
          customerId, normalizePhone(p.phone), p.label ?? '', p.is_primary ? 1 : 0);
      }
    }

    // Emails
    if (input.emails?.length) {
      for (const e of input.emails) {
        await adb.run(
          'INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, ?)',
          customerId, e.email, e.label ?? '', e.is_primary ? 1 : 0);
      }
    }

    // FTS – the trigger handles this automatically on INSERT, but if we updated code
    // after insert, we should re-sync. The UPDATE trigger on customers should fire,
    // so FTS is already up to date after the code UPDATE above.

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

    // SEC-H55: audit single-customer PII read. Coalesced 5 min per (user,
    // customer) — refreshing the detail page a dozen times writes once.
    const userId = req.user?.id ?? null;
    const viewCoalesceKey = `${userId ?? 'anon'}:get-by-id:${id}`;
    if (shouldAuditCustomerView(viewCoalesceKey)) {
      audit(req.db, 'customer_viewed', userId, req.ip || 'unknown', {
        via: 'get-by-id',
        tenant: req.tenantSlug ?? null,
        customer_id: id,
      });
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
// SEC-H25: updating a customer is a write operation — gate behind customers.edit.
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  requirePermission('customers.edit'),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const input: UpdateCustomerInput = req.body;

    const existing = await adb.get<any>('SELECT * FROM customers WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Customer not found', 404);

    // CROSS12: lock the seeded "Walk-in Customer" row against edit. Renaming
    // or otherwise mutating this row would break every historical ticket
    // that references it. Match by name today (no is_system column yet —
    // tracked as a migration follow-up). 409 Conflict signals a policy
    // reject rather than missing/invalid.
    if (
      (existing.first_name ?? '').trim() === 'Walk-in' &&
      (existing.last_name ?? '').trim() === 'Customer'
    ) {
      throw new AppError(
        'The Walk-in Customer record is seeded and cannot be edited. Create a new customer instead.',
        409,
      );
    }

    // V3: If first_name is being updated, require a non-empty trimmed value.
    if ('first_name' in input) {
      (input as any).first_name = validateRequiredString(
        (input as any).first_name,
        'first_name',
        100,
      );
    }

    // V2: Validate primary email with the shared validator. Undefined means
    // "not provided" — skip. Empty string means "clear the email".
    if (input.email !== undefined) {
      const normalized = validateEmail(input.email, 'email', false);
      (input as any).email = normalized;
    }

    // Validate additional emails with the shared validator.
    if (input.emails?.length) {
      for (const e of input.emails) {
        if (e.email) {
          e.email = validateEmail(e.email, 'email', true) as string;
        }
      }
    }

    // V1: Validate primary phones with the same rules used on create.
    if ('phone' in input) {
      (input as any).phone = normaliseAndValidatePhone((input as any).phone, 'phone');
    }
    if ('mobile' in input) {
      (input as any).mobile = normaliseAndValidatePhone((input as any).mobile, 'mobile');
    }
    if (input.phones?.length) {
      for (const p of input.phones) {
        if (p.phone) {
          p.phone = normaliseAndValidatePhone(p.phone, 'phone') as string;
        }
      }
    }

    // Build dynamic SET clause from provided fields.
    // PROD21: `col` is iterated from the readonly `CUSTOMER_COLUMNS` tuple
    // defined at the top of this file — it is NEVER taken from req.body
    // directly. Values always go through a ? placeholder; only the column
    // name is spliced. Adding a new column requires editing CUSTOMER_COLUMNS
    // which is the single source of truth for the customers allow-list.
    const sets: string[] = [];
    const values: unknown[] = [];

    for (const col of CUSTOMER_COLUMNS) {
      if (col in input) {
        let val = (input as any)[col];

        if (col === 'phone' || col === 'mobile') {
          // Already validated + normalised above. Keep null when the field
          // was explicitly cleared.
          val = val ?? null;
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
      await adb.run(`UPDATE customers SET ${sets.join(', ')} WHERE id = ?`, ...values);
    }

    // Replace phones
    if (input.phones !== undefined) {
      await adb.run('DELETE FROM customer_phones WHERE customer_id = ?', id);
      if (input.phones?.length) {
        for (const p of input.phones) {
          await adb.run(
            'INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, ?)',
            id, normalizePhone(p.phone), p.label ?? '', p.is_primary ? 1 : 0);
        }
      }
    }

    // Replace emails
    if (input.emails !== undefined) {
      await adb.run('DELETE FROM customer_emails WHERE customer_id = ?', id);
      if (input.emails?.length) {
        for (const e of input.emails) {
          await adb.run(
            'INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, ?)',
            id, e.email, e.label ?? '', e.is_primary ? 1 : 0);
        }
      }
    }

    // FTS is updated via the UPDATE trigger on the customers table

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
// SEC-H23: admin/manager only + name-typing CSRF (body.confirm_name must match
// the customer's full name). The typing requirement defeats drive-by CSRF and
// mis-click deletes from other tabs — the attacker needs to know the exact
// name before they can destroy the row.
// SEC-H25: gate behind customers.delete permission. The inline role check below
// is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  requirePermission('customers.delete'),
  asyncHandler(async (req, res) => {
    // Defence-in-depth: requirePermission above is authoritative.
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager role required to delete customers', 403);
    }

    const adb = req.asyncDb;
    const id = Number(req.params.id);

    const existing = await adb.get<AnyRow>(
      'SELECT id, first_name, last_name FROM customers WHERE id = ? AND is_deleted = 0',
      id,
    );
    if (!existing) throw new AppError('Customer not found', 404);

    // SEC-H23: name-typing confirmation — block CSRF/misclick.
    const confirmRaw = typeof req.body?.confirm_name === 'string' ? req.body.confirm_name : '';
    const expected = `${existing.first_name ?? ''} ${existing.last_name ?? ''}`.trim();
    const confirm = confirmRaw.trim();
    if (!confirm || confirm !== expected) {
      throw new AppError(
        'confirm_name must exactly match the customer\'s full name (first + last)',
        400,
      );
    }

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
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);

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
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);

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
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);
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
    if (customer?.phone) phoneSet.add(normalizePhone(customer.phone));
    if (customer?.mobile) phoneSet.add(normalizePhone(customer.mobile));
    for (const p of extraPhones) {
      const norm = normalizePhone(p.phone);
      if (norm) phoneSet.add(norm);
    }

    const emailSet = new Set<string>();
    if (customer?.email) emailSet.add(customer.email.toLowerCase());
    for (const e of extraEmails) {
      if (e.email) emailSet.add(e.email.toLowerCase());
    }

    // DA-5: SQLite caps bound parameters at 32766 (or 999 on older builds).
    // Cap phone/email lists at 500 each so a pathological customer (thousands
    // of contact rows) cannot crash the driver mid-query. 500 covers every
    // real-world customer by many orders of magnitude.
    const VAR_CAP = 500;
    const phones = Array.from(phoneSet).slice(0, VAR_CAP);
    const emails = Array.from(emailSet).slice(0, VAR_CAP);
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
// SEC-H25: adding an asset modifies customer record — gate behind customers.edit.
// ---------------------------------------------------------------------------
router.post(
  '/:id/assets',
  requirePermission('customers.edit'),
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
// SEC-H25: updating an asset modifies customer record — gate behind customers.edit.
// ---------------------------------------------------------------------------
router.put(
  '/assets/:assetId',
  requirePermission('customers.edit'),
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
// SEC-H25: deleting an asset modifies customer record — gate behind customers.edit.
// ---------------------------------------------------------------------------
router.delete(
  '/assets/:assetId',
  requirePermission('customers.edit'),
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
// SEC-H56: Step-up TOTP required before any PII export.
// ---------------------------------------------------------------------------
router.get(
  '/:id/export',
  requireStepUpTotp('GET /customers/:id/export'),
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
    // DA-5: cap IN-list size so a customer with thousands of phone/email
    // rows cannot exceed SQLite's bound-parameter limit mid-query.
    const VAR_CAP = 500;
    const phoneList = Array.from(phoneSet).slice(0, VAR_CAP);
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
    const emailList = Array.from(emailSet).slice(0, VAR_CAP);
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
// SEC-H25: GDPR erasure is the most destructive customer action — gate behind
// customers.gdpr_erase (admin-only by default). The inline role check below is
// kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.delete(
  '/:id/gdpr-erase',
  requirePermission('customers.gdpr_erase'),
  asyncHandler(async (req, res) => {
    // Defence-in-depth: requirePermission above is authoritative.
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
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

    // Delete customer phones and emails
    await adb.run('DELETE FROM customer_phones WHERE customer_id = ?', id);
    await adb.run('DELETE FROM customer_emails WHERE customer_id = ?', id);

    // Delete customer assets
    await adb.run('DELETE FROM customer_assets WHERE customer_id = ?', id);

    // Delete loaner history for this customer
    await adb.run('DELETE FROM loaner_history WHERE customer_id = ?', id);

    // SEC-H58: Scrub on-disk ticket photos BEFORE NULLing customer_id on
    // tickets (below). Once that UPDATE runs, `WHERE customer_id = ?` returns
    // zero rows and we'd silently skip all photos. One missing file must not
    // abort the entire erasure.
    {
      const customerTickets = await adb.all<AnyRow>(
        'SELECT id FROM tickets WHERE customer_id = ?',
        id,
      );
      if (customerTickets.length > 0) {
        const ticketPlaceholders = customerTickets.map(() => '?').join(', ');
        const ticketIds = customerTickets.map((t) => t.id);

        interface PhotoRow { id: number; file_path: string }
        const photos = await adb.all<PhotoRow>(
          `SELECT tp.id, tp.file_path
           FROM ticket_photos tp
           JOIN ticket_devices td ON td.id = tp.ticket_device_id
           WHERE td.ticket_id IN (${ticketPlaceholders})`,
          ...ticketIds,
        );

        const tenantSlug: string = (req as any).tenantSlug ?? '';
        const uploadsBase = tenantSlug
          ? path.join(config.uploadsPath, tenantSlug)
          : config.uploadsPath;
        const resolvedBase = path.resolve(uploadsBase);

        for (const photo of photos) {
          const absPath = path.resolve(path.join(uploadsBase, photo.file_path));

          // SEC: Reject any path that escapes the uploads directory.
          if (!absPath.startsWith(resolvedBase + path.sep) && absPath !== resolvedBase) {
            log.warn('gdpr-erase: path traversal rejected', {
              customerId: id,
              photoId: photo.id,
              filePath: photo.file_path,
            });
            continue;
          }

          try {
            fs.unlinkSync(absPath);
          } catch (err: unknown) {
            const code = (err as NodeJS.ErrnoException).code;
            if (code !== 'ENOENT') {
              log.warn('gdpr-erase: photo unlink failed (continuing)', {
                customerId: id,
                photoId: photo.id,
                filePath: photo.file_path,
                error: err instanceof Error ? err.message : String(err),
              });
            }
            // ENOENT or non-fatal error: proceed to next photo.
          }
        }

        // Remove ticket_photos rows for all customer tickets. The ticket_devices
        // ON DELETE CASCADE would remove these too when tickets are eventually
        // deleted, but the tickets rows are NULLed (not deleted) here, so we
        // clean up explicitly to avoid dangling rows.
        if (photos.length > 0) {
          const photoIds = photos.map((p) => p.id);
          const photoPlaceholders = photoIds.map(() => '?').join(', ');
          await adb.run(
            `DELETE FROM ticket_photos WHERE id IN (${photoPlaceholders})`,
            ...photoIds,
          );
        }

        // SEC-H53: Explicit FTS scrub for tickets_fts (contentless, content='').
        // The tickets_fts_au trigger fires when we UPDATE tickets SET customer_id = NULL
        // below and already zeroes customer_name; however, for a contentless FTS5
        // table the trigger path can silently no-op if the rowid was never inserted
        // (e.g. imported rows that pre-date migration 008).  Belt-and-suspenders:
        // delete every customer ticket rowid from the FTS index now, before the
        // UPDATE that would race the trigger.
        for (const t of customerTickets) {
          // FTS5 delete command: first delete the old entry …
          await adb.run(
            `INSERT INTO tickets_fts(tickets_fts, rowid, order_id, device_names, customer_name, notes_text, labels)
             VALUES ('delete', ?, '', '', '', '', '')`,
            t.id,
          );
          // … then reinsert with customer_name blanked so searches on the name
          // no longer surface this ticket while all other searchable fields remain.
          // Use the same subquery pattern as the tickets_fts_au trigger so
          // device_names and notes_text are populated from the child tables.
          const ticketRow = await adb.get<AnyRow>('SELECT * FROM tickets WHERE id = ?', t.id);
          if (ticketRow) {
            const deviceNames = (await adb.all<{ device_name: string }>(
              'SELECT device_name FROM ticket_devices WHERE ticket_id = ?', t.id,
            )).map((r) => r.device_name).join(', ');
            const notesText = (await adb.all<{ content: string }>(
              'SELECT content FROM ticket_notes WHERE ticket_id = ?', t.id,
            )).map((r) => r.content).join(' ');
            await adb.run(
              `INSERT INTO tickets_fts(rowid, order_id, device_names, customer_name, notes_text, labels)
               VALUES (?, ?, ?, '', ?, ?)`,
              t.id,
              ticketRow.order_id ?? '',
              deviceNames,
              notesText,
              ticketRow.labels ?? '',
            );
          }
        }
      }
    }

    // SEC-H53: Explicit FTS scrub for customers_fts (content='customers').
    // The customers_fts_delete trigger fires when we DELETE FROM customers below,
    // which would normally remove the entry.  We issue the delete explicitly here
    // so the FTS index is clean even if the trigger is missing or re-created.
    await adb.run(
      `INSERT INTO customers_fts(customers_fts, rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
       VALUES ('delete', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id,
      customer.first_name ?? '',
      customer.last_name ?? '',
      customer.email ?? '',
      customer.phone ?? '',
      customer.mobile ?? '',
      customer.organization ?? '',
      customer.city ?? '',
      customer.postcode ?? '',
      customer.tags ?? '',
    );

    // D1: Set child rows' customer_id to NULL instead of 0. Writing 0 used
    // to leak a synthetic orphan id into every join and break FK semantics.
    // Invoices have been nullable since migration 013. Tickets and estimates
    // were made nullable in migration 074.
    await adb.run('UPDATE tickets SET customer_id = NULL WHERE customer_id = ?', id);
    await adb.run('UPDATE invoices SET customer_id = NULL WHERE customer_id = ?', id);
    await adb.run('UPDATE estimates SET customer_id = NULL WHERE customer_id = ?', id);

    // D3: customer_relationships has no CASCADE on customer_id_a/b, so we
    // clean it up here from application code as part of the erasure.
    await adb.run(
      'DELETE FROM customer_relationships WHERE customer_id_a = ? OR customer_id_b = ?',
      id,
      id,
    );

    // Delete SMS messages linked to customer's phone numbers
    const phoneSet = new Set<string>();
    if (customer.phone) phoneSet.add(normalizePhone(customer.phone));
    if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
    if (phoneSet.size > 0) {
      const phoneList = Array.from(phoneSet);
      const phonePlaceholders = phoneList.map(() => '?').join(', ');
      await adb.run(`DELETE FROM sms_messages WHERE conv_phone IN (${phonePlaceholders})`, ...phoneList);
      await adb.run(`DELETE FROM call_logs WHERE conv_phone IN (${phonePlaceholders})`, ...phoneList);
    }

    // Delete email messages
    const emailSet = new Set<string>();
    if (customer.email) emailSet.add(customer.email.toLowerCase());
    if (emailSet.size > 0) {
      const emailList = Array.from(emailSet);
      const emailPlaceholders = emailList.map(() => '?').join(', ');
      await adb.run(`DELETE FROM email_messages WHERE LOWER(to_address) IN (${emailPlaceholders}) OR LOWER(from_address) IN (${emailPlaceholders})`,
        ...emailList, ...emailList);
    }

    // Hard delete the customer record
    await adb.run('DELETE FROM customers WHERE id = ?', id);

    // SEC-H53: Strip PII from audit_log.details JSON for all rows that
    // reference this customer.  We retain customer_id so the audit chain
    // stays anchored (compliance requirement) but remove the human-readable
    // fields that constitute personal data.
    //
    // PII keys observed in audit() calls across the codebase:
    //   customer_name  — customer_gdpr_erased, (customer_deleted uses only customer_id)
    //   phone          — sms_opt_out
    //   customer_email — (none currently, guarded for future-proofing)
    //   customer_phone — (none currently, guarded for future-proofing)
    //   customer_last_name — (none currently, guarded for future-proofing)
    await adb.run(
      `UPDATE audit_logs
          SET details = JSON_REMOVE(
                JSON_REMOVE(
                  JSON_REMOVE(
                    JSON_REMOVE(
                      JSON_REMOVE(details,
                        '$.customer_name'),
                      '$.customer_email'),
                    '$.customer_phone'),
                  '$.customer_last_name'),
                '$.phone')
        WHERE JSON_EXTRACT(details, '$.customer_id') = ?`,
      id,
    );

    // SEC-H53: SMS suppression list — the sms_suppression table does not
    // exist in the current schema (verified: grep of all migrations returns
    // no CREATE TABLE sms_suppression).  Skip this step.  If the table is
    // added in a future migration, insert the customer's phones here.

    // SEC-H53: Stripe per-customer deletion — stripe_customer_id lives on
    // the tenants table (one per shop), not on individual CRM customers.
    // There is no Stripe identity to delete for a single erased contact.

    audit(req.db, 'customer_gdpr_erased', req.user!.id, req.ip || 'unknown', {
      customer_id: id,
      // SEC-H53: intentionally omit customer_name from the audit record so
      // the erased record is self-consistent (the details JSON we just
      // scrubbed above never had a name to begin with for future erasures).
    });

    res.json({
      success: true,
      data: { message: `All data for customer ${id} has been permanently erased` },
    });
  }),
);

// ---------------------------------------------------------------------------
// ENR-C7: Related/family accounts
// ---------------------------------------------------------------------------

// POST /:id/relationships — link two customers
// SEC-H25: linking customers modifies customer records — gate behind customers.edit.
router.post(
  '/:id/relationships',
  requirePermission('customers.edit'),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const customerIdA = parseInt(req.params.id as string, 10);
    const { customer_id, relationship_type } = req.body;
    const customerIdB = parseInt(customer_id, 10);

    if (!customerIdA || !customerIdB) throw new AppError('Both customer IDs are required', 400);
    if (customerIdA === customerIdB) throw new AppError('Cannot link a customer to themselves', 400);

    const relType = typeof relationship_type === 'string' && relationship_type.trim()
      ? relationship_type.trim()
      : 'family';

    // Verify both customers exist
    const [custA, custB] = await Promise.all([
      adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerIdA),
      adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerIdB),
    ]);
    if (!custA) throw new AppError('Customer not found', 404);
    if (!custB) throw new AppError('Related customer not found', 404);

    // Check for existing link (either direction)
    const existing = await adb.get<AnyRow>(
      `SELECT id FROM customer_relationships
       WHERE (customer_id_a = ? AND customer_id_b = ?)
          OR (customer_id_a = ? AND customer_id_b = ?)`,
      customerIdA, customerIdB, customerIdB, customerIdA,
    );
    if (existing) throw new AppError('Relationship already exists', 409);

    const result = await adb.run(
      `INSERT INTO customer_relationships (customer_id_a, customer_id_b, relationship_type)
       VALUES (?, ?, ?)`,
      customerIdA, customerIdB, relType,
    );

    const relationship = await adb.get<AnyRow>(
      'SELECT * FROM customer_relationships WHERE id = ?',
      result.lastInsertRowid,
    );

    res.status(201).json({ success: true, data: relationship });
  }),
);

// GET /:id/relationships — get linked customers
router.get(
  '/:id/relationships',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const customerId = parseInt(req.params.id as string, 10);
    if (!customerId) throw new AppError('Invalid customer ID', 400);

    const rows = await adb.all<AnyRow>(
      `SELECT cr.id AS relationship_id, cr.relationship_type, cr.created_at AS linked_at,
              CASE WHEN cr.customer_id_a = ? THEN cr.customer_id_b ELSE cr.customer_id_a END AS related_customer_id,
              c.first_name, c.last_name, c.email, c.phone, c.mobile, c.organization, c.code
       FROM customer_relationships cr
       JOIN customers c ON c.id = CASE WHEN cr.customer_id_a = ? THEN cr.customer_id_b ELSE cr.customer_id_a END
       WHERE (cr.customer_id_a = ? OR cr.customer_id_b = ?)
         AND c.is_deleted = 0
       ORDER BY cr.created_at DESC`,
      customerId, customerId, customerId, customerId,
    );

    res.json({ success: true, data: rows });
  }),
);

// DELETE /relationships/:relId — remove link
// SEC-H25: removing a customer relationship is a write — gate behind customers.edit.
router.delete(
  '/relationships/:relId',
  requirePermission('customers.edit'),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const relId = parseInt(req.params.relId as string, 10);
    if (!relId) throw new AppError('Invalid relationship ID', 400);

    const existing = await adb.get<AnyRow>(
      'SELECT id FROM customer_relationships WHERE id = ?',
      relId,
    );
    if (!existing) throw new AppError('Relationship not found', 404);

    await adb.run('DELETE FROM customer_relationships WHERE id = ?', relId);

    res.json({ success: true, data: { message: 'Relationship removed' } });
  }),
);

// ---------------------------------------------------------------------------
// Customer notes (CROSS9b) — multi-row, append-only per-customer notes.
// The existing customers.comments column stays as the single-line sticky
// note edited via Edit Profile; this is the timeline list + composer.
// ---------------------------------------------------------------------------

const MAX_NOTE_BODY_CHARS = 5000;

// GET /:id/notes — most-recent first
router.get(
  '/:id/notes',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);
    if (!Number.isFinite(customerId) || customerId <= 0) {
      throw new AppError('Invalid customer id', 400);
    }

    const existing = await adb.get<AnyRow>(
      'SELECT id FROM customers WHERE id = ? AND is_deleted = 0',
      customerId,
    );
    if (!existing) throw new AppError('Customer not found', 404);

    const notes = await adb.all<AnyRow>(
      `SELECT n.id, n.customer_id, n.author_user_id, n.body, n.created_at,
              u.username AS author_username
         FROM customer_notes n
         LEFT JOIN users u ON u.id = n.author_user_id
        WHERE n.customer_id = ?
        ORDER BY n.created_at DESC, n.id DESC
        LIMIT 500`,
      customerId,
    );

    res.json({ success: true, data: notes });
  }),
);

// POST /:id/notes — append a new note. Body capped at 5000 chars.
// SEC-H25: appending a customer note is a write — gate behind customers.edit.
router.post(
  '/:id/notes',
  requirePermission('customers.edit'),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const customerId = Number(req.params.id);
    if (!Number.isFinite(customerId) || customerId <= 0) {
      throw new AppError('Invalid customer id', 400);
    }

    const existing = await adb.get<AnyRow>(
      'SELECT id FROM customers WHERE id = ? AND is_deleted = 0',
      customerId,
    );
    if (!existing) throw new AppError('Customer not found', 404);

    const rawBody = req.body?.body;
    if (typeof rawBody !== 'string') {
      throw new AppError('body must be a string', 400);
    }
    const trimmed = rawBody.trim();
    if (!trimmed) throw new AppError('body is required', 400);
    if (trimmed.length > MAX_NOTE_BODY_CHARS) {
      throw new AppError(`body exceeds ${MAX_NOTE_BODY_CHARS} character limit`, 400);
    }

    const authorId = req.user?.id ?? null;

    const result = await adb.run(
      `INSERT INTO customer_notes (customer_id, author_user_id, body)
       VALUES (?, ?, ?)`,
      customerId, authorId, trimmed,
    );

    const note = await adb.get<AnyRow>(
      `SELECT n.id, n.customer_id, n.author_user_id, n.body, n.created_at,
              u.username AS author_username
         FROM customer_notes n
         LEFT JOIN users u ON u.id = n.author_user_id
        WHERE n.id = ?`,
      result.lastInsertRowid,
    );

    res.status(201).json({ success: true, data: note });
  }),
);

export default router;
