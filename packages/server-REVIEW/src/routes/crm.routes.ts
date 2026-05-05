/**
 * CRM routes — Customer Relationships enrichment (audit §49)
 *
 * Endpoints:
 *   GET    /crm/customers/:id/health-score
 *   POST   /crm/customers/:id/health-score/recalculate
 *   GET    /crm/customers/:id/ltv-tier
 *   GET    /crm/customers/:id/photo-mementos     — last 12 months of repair photos
 *   GET    /crm/customers/:id/wallet-pass        — HTML fallback or .pkpass
 *   POST   /crm/customers/:id/referral-code      — mint if not exists
 *   POST   /crm/customers/:id/subscription       — create service subscription
 *
 *   GET    /crm/segments                         — list segments
 *   POST   /crm/segments                         — create segment
 *   GET    /crm/segments/:id
 *   PATCH  /crm/segments/:id
 *   DELETE /crm/segments/:id
 *   POST   /crm/segments/:id/refresh             — re-evaluate rule
 *   GET    /crm/segments/:id/members             — paginated
 *
 * Rules:
 *   - auth middleware mounted at index.ts
 *   - every mutating endpoint writes an audit() row
 *   - segment rule engine supports a small safe subset (comparison ops only)
 *   - read-only endpoints are cheap enough to skip segment refresh; clients
 *     call POST /crm/segments/:id/refresh explicitly.
 */

import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateJsonPayload,
  validatePositiveAmount,
  validateIsoDate,
  validateTextLength,
} from '../utils/validate.js';
import {
  recalculateCustomerHealth,
  computeLtvTier,
} from '../services/customerHealthScore.js';
import {
  generateWalletPassId,
  loadWalletPassData,
  renderWalletPassHtml,
  getPkPassConfig,
  generatePkPass,
} from '../services/walletPass.js';
import type { AsyncDb } from '../db/async-db.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';

const log = createLogger('crm');
const router = Router();

// SEC (post-enrichment audit §6): role gates.
//   - health score / LTV / photo mementos reads: manager or admin
//   - segment CRUD + refresh: admin only (marketing policy)
//   - wallet pass + referral code: any logged-in user
// Normalize a stored photo path for client exposure. Strip any occurrence of
// `/uploads/` (or Windows `\uploads\`) prefix and return the relative tail so
// the client can prepend its own `/uploads/` base. Falls back to the raw
// basename if no `/uploads/` segment is present. Prevents absolute server
// paths from leaking into the JSON response.
function sanitizeUploadPath(raw: string): string {
  if (!raw) return '';
  const normalized = raw.replace(/\\/g, '/');
  const idx = normalized.lastIndexOf('/uploads/');
  if (idx !== -1) return normalized.slice(idx + '/uploads/'.length);
  const lastSlash = normalized.lastIndexOf('/');
  if (lastSlash !== -1) return normalized.slice(lastSlash + 1);
  return normalized;
}

function requireManagerOrAdmin(req: any): void {
  const role = req?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}
function requireAdminCrm(req: any): void {
  if (req?.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
  }
}

// -----------------------------------------------------------------------------
// Type helpers
// -----------------------------------------------------------------------------

interface SegmentRow {
  id: number;
  name: string;
  description: string | null;
  rule_json: string;
  is_auto: number;
  last_refreshed_at: string | null;
  member_count: number;
  created_at: string;
}

type ComparisonOp = '>' | '>=' | '<' | '<=' | '=' | '!=';
/** Single-condition leaf: { field: { op: value } } */
interface SegmentRuleLeaf {
  [field: string]: { [op in ComparisonOp]?: string | number };
}
/**
 * Compound rule: { op: 'and'|'or', conditions: SegmentRuleLeaf[] }
 * Allows multi-condition segments like "LTV > 50000 AND days-since > 90".
 * The flat legacy form (single or multi-field object) is still accepted for
 * backward compatibility with seeded auto-segments.
 */
interface SegmentRuleCompound {
  op: 'and' | 'or';
  conditions: SegmentRuleLeaf[];
}
type SegmentRule = SegmentRuleLeaf | SegmentRuleCompound;

// -----------------------------------------------------------------------------
// Health score endpoints
// -----------------------------------------------------------------------------

router.get(
  '/customers/:id/health-score',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const row = await adb.get<{
      health_score: number | null;
      health_tier: string | null;
      last_interaction_at: string | null;
      lifetime_value_cents: number | null;
    }>(
      `SELECT health_score, health_tier, last_interaction_at, lifetime_value_cents
         FROM customers WHERE id = ?`,
      id,
    );
    if (!row) throw new AppError('Customer not found', 404);

    res.json({
      success: true,
      data: {
        score: row.health_score,
        tier: row.health_tier,
        last_interaction_at: row.last_interaction_at,
        lifetime_value_cents: row.lifetime_value_cents ?? 0,
      },
    });
  }),
);

router.post(
  '/customers/:id/health-score/recalculate',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const result = await recalculateCustomerHealth(adb, id);
    if (!result) throw new AppError('Customer not found', 404);

    audit(db, 'customer_health_recalculated', req.user!.id, req.ip || 'unknown', {
      customer_id: id,
      score: result.score.score,
      tier: result.score.tier,
    });

    res.json({
      success: true,
      data: {
        score: result.score.score,
        tier: result.score.tier,
        recency_points: result.score.recencyPoints,
        frequency_points: result.score.frequencyPoints,
        monetary_points: result.score.monetaryPoints,
        ltv_tier: result.ltvTier,
        lifetime_value_cents: result.lifetimeValueCents,
        last_interaction_at: result.lastInteractionAt,
      },
    });
  }),
);

// -----------------------------------------------------------------------------
// LTV tier
// -----------------------------------------------------------------------------

router.get(
  '/customers/:id/ltv-tier',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const row = await adb.get<{
      ltv_tier: string | null;
      lifetime_value_cents: number | null;
    }>(
      `SELECT ltv_tier, lifetime_value_cents FROM customers WHERE id = ?`,
      id,
    );
    if (!row) throw new AppError('Customer not found', 404);

    const cents = row.lifetime_value_cents ?? 0;
    const tier = row.ltv_tier ?? computeLtvTier(cents);

    res.json({
      success: true,
      data: { tier, lifetime_value_cents: cents },
    });
  }),
);

// -----------------------------------------------------------------------------
// Photo mementos — last 12 months of repair photos
// -----------------------------------------------------------------------------

interface MementoRow {
  photo_id: number;
  file_path: string;
  caption: string | null;
  created_at: string;
  ticket_id: number;
  order_id: string;
  device_name: string | null;
}

router.get(
  '/customers/:id/photo-mementos',
  asyncHandler(async (req, res) => {
    // S20-C1: Any-staff PII read. A low-privilege technician could previously
    // enumerate all customers' repair photos. Restrict to manager/admin to
    // match health-score/ltv gating.
    requireManagerOrAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const photos = await adb.all<MementoRow>(
      `SELECT
         tp.id           AS photo_id,
         tp.file_path    AS file_path,
         tp.caption      AS caption,
         tp.created_at   AS created_at,
         td.ticket_id    AS ticket_id,
         t.order_id      AS order_id,
         td.device_name  AS device_name
       FROM ticket_photos tp
       JOIN ticket_devices td ON td.id = tp.ticket_device_id
       JOIN tickets t ON t.id = td.ticket_id
       WHERE t.customer_id = ?
         AND tp.created_at >= datetime('now','-12 months')
         AND t.is_deleted = 0
       ORDER BY tp.created_at DESC
       LIMIT 200`,
      id,
    );

    // Strip any absolute/server-specific prefix before returning — clients
    // only need the basename-or-relative path under `/uploads/`. Previously
    // raw `file_path` values (e.g. `C:\var\data\uploads\foo.jpg` on Windows
    // or absolute POSIX paths) could leak server filesystem layout.
    const sanitized = photos.map((row) => ({
      ...row,
      file_path: sanitizeUploadPath(row.file_path),
    }));

    res.json({ success: true, data: sanitized });
  }),
);

// -----------------------------------------------------------------------------
// Wallet pass (HTML fallback or .pkpass)
// -----------------------------------------------------------------------------

router.get(
  '/customers/:id/wallet-pass',
  asyncHandler(async (req, res) => {
    // S20-C1: Wallet pass exposes PII (name, loyalty balance, referral
    // code, tiers). Previously any authenticated staff member could fetch
    // any customer's pass by incrementing the numeric id — a clear PII
    // enumeration risk. Restrict to manager/admin to match the rest of
    // the customer-reading endpoints on this router. Customers themselves
    // retrieve their own pass via the portal session routes, not via
    // /api/v1/crm/*.
    requireManagerOrAdmin(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    // Lazily mint the pass id on first access. This is also the unguessable
    // URL identifier going forward — future deep-linking routes should use it.
    const current = await adb.get<{ wallet_pass_id: string | null }>(
      `SELECT wallet_pass_id FROM customers WHERE id = ?`,
      id,
    );
    if (!current) throw new AppError('Customer not found', 404);

    if (!current.wallet_pass_id) {
      const newId = generateWalletPassId();
      await adb.run(
        `UPDATE customers SET wallet_pass_id = ? WHERE id = ? AND wallet_pass_id IS NULL`,
        newId,
        id,
      );
      audit(db, 'wallet_pass_minted', req.user!.id, req.ip || 'unknown', {
        customer_id: id,
        pass_id: newId,
      });
    }

    const data = await loadWalletPassData(adb, id);
    if (!data) throw new AppError('Customer not found', 404);

    const config = await getPkPassConfig(adb);
    const wantPkpass = String(req.query.format || '').toLowerCase() === 'pkpass';

    if (wantPkpass && config.enabled) {
      try {
        const buf = await generatePkPass(data);
        res.setHeader('Content-Type', 'application/vnd.apple.pkpass');
        res.setHeader('Content-Disposition', `attachment; filename="pass-${data.passId}.pkpass"`);
        res.end(buf);
        return;
      } catch (err) {
        log.warn('pkpass generation failed, falling back to HTML', {
          customer_id: id,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end(renderWalletPassHtml(data));
  }),
);

// -----------------------------------------------------------------------------
// Referral code generator
// -----------------------------------------------------------------------------

function mintReferralCode(firstName: string | null): string {
  const prefix = (firstName || 'BIZ').replace(/[^a-zA-Z]/g, '').slice(0, 4).toUpperCase() || 'BIZ';
  const suffix = crypto.randomBytes(3).toString('hex').toUpperCase();
  return `${prefix}-${suffix}`;
}

router.post(
  '/customers/:id/referral-code',
  asyncHandler(async (req, res) => {
    // S20-C1: Referral code POSTs touch a PII-adjacent table (referrals) and
    // are an anti-abuse surface. Restrict to manager/admin so cashiers can't
    // mint codes for arbitrary customers.
    requireManagerOrAdmin(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const customer = await adb.get<{ first_name: string | null }>(
      `SELECT first_name FROM customers WHERE id = ?`,
      id,
    );
    if (!customer) throw new AppError('Customer not found', 404);

    const existing = await adb.get<{ referral_code: string }>(
      `SELECT referral_code FROM referrals
         WHERE referrer_customer_id = ?
         ORDER BY created_at DESC LIMIT 1`,
      id,
    );
    if (existing) {
      res.json({ success: true, data: { referral_code: existing.referral_code, reused: true } });
      return;
    }

    // S20-C3: INSERT + UNIQUE(referral_code) collision-catch. The prior
    // version already tried to retry on error but kept the value of `code`
    // inside the `try` scope unreachable on the final iteration. Regenerate
    // on every failure so the caller sees a distinct code on retry.
    let code = '';
    for (let i = 0; i < 5; i += 1) {
      const candidate = mintReferralCode(customer.first_name);
      try {
        await adb.run(
          `INSERT INTO referrals (referrer_customer_id, referral_code) VALUES (?, ?)`,
          id,
          candidate,
        );
        code = candidate;
        break;
      } catch (err) {
        const msg = err instanceof Error ? err.message.toLowerCase() : '';
        if (!(msg.includes('unique') || msg.includes('constraint'))) throw err;
        // else retry with a freshly-minted code
      }
    }
    if (!code) {
      throw new AppError('Could not generate unique referral code, please retry', 500);
    }

    audit(db, 'referral_code_created', req.user!.id, req.ip || 'unknown', {
      customer_id: id,
      referral_code: code,
    });

    res.status(201).json({ success: true, data: { referral_code: code, reused: false } });
  }),
);

// -----------------------------------------------------------------------------
// Service subscriptions
// -----------------------------------------------------------------------------

router.post(
  '/customers/:id/subscription',
  asyncHandler(async (req, res) => {
    // Recurring billing plan — manager/admin only.
    requireManagerOrAdmin(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const planName = validateRequiredString(body.plan_name, 'plan_name', 100);
    const monthly = validatePositiveAmount(body.monthly_amount, 'monthly_amount');
    const nextBillingDate = validateIsoDate(body.next_billing_date, 'next_billing_date', true)!;

    const exists = await adb.get<{ id: number }>(`SELECT id FROM customers WHERE id = ?`, id);
    if (!exists) throw new AppError('Customer not found', 404);

    // card_token is an opaque reference from the payment processor; bound it
    // so a 10MB string can't DoS the insert.
    const cardToken =
      body.card_token !== undefined && body.card_token !== null
        ? validateTextLength(body.card_token as string, 255, 'card_token') || null
        : null;
    const result = await adb.run(
      `INSERT INTO service_subscriptions
         (customer_id, plan_name, monthly_cents, next_billing_date, card_token)
       VALUES (?, ?, ?, ?, ?)`,
      id,
      planName,
      Math.round(monthly * 100),
      nextBillingDate,
      cardToken,
    );

    audit(db, 'service_subscription_created', req.user!.id, req.ip || 'unknown', {
      customer_id: id,
      subscription_id: result.lastInsertRowid,
      plan_name: planName,
      monthly_cents: Math.round(monthly * 100),
    });

    res.status(201).json({
      success: true,
      data: {
        id: result.lastInsertRowid,
        customer_id: id,
        plan_name: planName,
        monthly_cents: Math.round(monthly * 100),
        next_billing_date: nextBillingDate,
        status: 'active',
      },
    });
  }),
);

router.get(
  '/customers/:id/subscriptions',
  asyncHandler(async (req, res) => {
    // S20-C1: Subscriptions include opaque card tokens and billing data —
    // manager/admin only. Matches the POST /subscription gate already
    // present.
    requireManagerOrAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid customer id', 400);

    const rows = await adb.all(
      `SELECT * FROM service_subscriptions WHERE customer_id = ? ORDER BY created_at DESC`,
      id,
    );
    res.json({ success: true, data: rows });
  }),
);

// -----------------------------------------------------------------------------
// Segments — CRUD + refresh
// -----------------------------------------------------------------------------

router.get(
  '/segments',
  asyncHandler(async (req, res) => {
    // Segment list is admin-only (marketing targeting metadata).
    requireAdminCrm(req);
    const adb = req.asyncDb;
    const rows = await adb.all<SegmentRow>(
      `SELECT * FROM customer_segments ORDER BY is_auto DESC, id ASC`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/segments',
  asyncHandler(async (req, res) => {
    requireAdminCrm(req);
    const db = req.db;
    const adb = req.asyncDb;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const name = validateRequiredString(body.name, 'name', 100);
    const description =
      body.description !== undefined && body.description !== null
        ? validateTextLength(body.description as string, 500, 'description') || null
        : null;
    const ruleJson = validateJsonPayload(body.rule ?? body.rule_json, 'rule', 8_192);
    const isAuto = body.is_auto === false ? 0 : 1;

    // Smoke-test the rule by parsing it so callers see errors immediately.
    parseSegmentRule(ruleJson);

    const result = await adb.run(
      `INSERT INTO customer_segments (name, description, rule_json, is_auto)
       VALUES (?, ?, ?, ?)`,
      name,
      description,
      ruleJson,
      isAuto,
    );

    audit(db, 'segment_created', req.user!.id, req.ip || 'unknown', {
      segment_id: result.lastInsertRowid,
      name,
    });

    res.status(201).json({
      success: true,
      data: {
        id: result.lastInsertRowid,
        name,
        description,
        rule_json: ruleJson,
        is_auto: isAuto,
        member_count: 0,
      },
    });
  }),
);

router.get(
  '/segments/:id',
  asyncHandler(async (req, res) => {
    requireAdminCrm(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid segment id', 400);
    const row = await adb.get<SegmentRow>(
      `SELECT * FROM customer_segments WHERE id = ?`,
      id,
    );
    if (!row) throw new AppError('Segment not found', 404);
    res.json({ success: true, data: row });
  }),
);

router.patch(
  '/segments/:id',
  asyncHandler(async (req, res) => {
    requireAdminCrm(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid segment id', 400);
    const existing = await adb.get<SegmentRow>(
      `SELECT * FROM customer_segments WHERE id = ?`,
      id,
    );
    if (!existing) throw new AppError('Segment not found', 404);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const fields: string[] = [];
    const params: unknown[] = [];

    if (body.name !== undefined) {
      fields.push('name = ?');
      params.push(validateRequiredString(body.name, 'name', 100));
    }
    if (body.description !== undefined) {
      fields.push('description = ?');
      params.push(
        body.description === null
          ? null
          : validateTextLength(body.description as string, 500, 'description') || null,
      );
    }
    if (body.rule !== undefined || body.rule_json !== undefined) {
      const ruleJson = validateJsonPayload(body.rule ?? body.rule_json, 'rule', 8_192);
      parseSegmentRule(ruleJson);
      fields.push('rule_json = ?');
      params.push(ruleJson);
    }
    if (body.is_auto !== undefined) {
      fields.push('is_auto = ?');
      params.push(body.is_auto ? 1 : 0);
    }

    if (fields.length === 0) throw new AppError('No fields to update', 400);
    params.push(id);
    await adb.run(`UPDATE customer_segments SET ${fields.join(', ')} WHERE id = ?`, ...params);

    audit(db, 'segment_updated', req.user!.id, req.ip || 'unknown', { segment_id: id });

    const updated = await adb.get<SegmentRow>(
      `SELECT * FROM customer_segments WHERE id = ?`,
      id,
    );
    res.json({ success: true, data: updated });
  }),
);

router.delete(
  '/segments/:id',
  asyncHandler(async (req, res) => {
    requireAdminCrm(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid segment id', 400);
    const existing = await adb.get<{ id: number }>(
      `SELECT id FROM customer_segments WHERE id = ?`,
      id,
    );
    if (!existing) throw new AppError('Segment not found', 404);
    await adb.run(`DELETE FROM customer_segments WHERE id = ?`, id);
    audit(db, 'segment_deleted', req.user!.id, req.ip || 'unknown', { segment_id: id });
    res.json({ success: true, data: { id } });
  }),
);

router.post(
  '/segments/:id/refresh',
  asyncHandler(async (req, res) => {
    requireAdminCrm(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid segment id', 400);
    const segment = await adb.get<SegmentRow>(
      `SELECT * FROM customer_segments WHERE id = ?`,
      id,
    );
    if (!segment) throw new AppError('Segment not found', 404);

    const memberCount = await refreshSegmentMembership(adb, segment);

    audit(db, 'segment_refreshed', req.user!.id, req.ip || 'unknown', {
      segment_id: id,
      member_count: memberCount,
    });

    res.json({
      success: true,
      data: { segment_id: id, member_count: memberCount },
    });
  }),
);

router.get(
  '/segments/:id/members',
  asyncHandler(async (req, res) => {
    requireAdminCrm(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid segment id', 400);
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 50);
    const offset = (page - 1) * pageSize;

    const [countRow, members] = await Promise.all([
      adb.get<{ total: number }>(
        `SELECT COUNT(*) AS total FROM customer_segment_members WHERE segment_id = ?`,
        id,
      ),
      adb.all(
        `SELECT c.id, c.first_name, c.last_name, c.email, c.phone,
                c.health_tier, c.ltv_tier, c.lifetime_value_cents, c.sms_opt_in, c.email_opt_in
           FROM customer_segment_members m
           JOIN customers c ON c.id = m.customer_id
          WHERE m.segment_id = ?
          ORDER BY m.added_at DESC
          LIMIT ? OFFSET ?`,
        id,
        pageSize,
        offset,
      ),
    ]);

    res.json({
      success: true,
      data: {
        members,
        pagination: {
          page,
          per_page: pageSize,
          total: countRow?.total ?? 0,
          total_pages: Math.ceil((countRow?.total ?? 0) / pageSize),
        },
      },
    });
  }),
);

// -----------------------------------------------------------------------------
// Segment rule engine (intentionally tiny + safe)
// -----------------------------------------------------------------------------

const SEGMENT_OPS: readonly ComparisonOp[] = ['>', '>=', '<', '<=', '=', '!='];

/**
 * Whitelisted field → SQL expression map. Keeps the rule engine from being
 * a SQL injection vector — only known columns (or derived expressions) can
 * be referenced by a rule.
 */
const SEGMENT_FIELD_EXPRESSIONS: Record<string, string> = {
  lifetime_value_cents: 'COALESCE(c.lifetime_value_cents,0)',
  health_score: 'COALESCE(c.health_score,0)',
  health_tier: 'COALESCE(c.health_tier,\'\')',
  ltv_tier: 'COALESCE(c.ltv_tier,\'\')',
  tickets_12mo:
    "(SELECT COUNT(*) FROM tickets t WHERE t.customer_id = c.id AND t.is_deleted = 0 " +
    "AND t.created_at >= datetime('now','-12 months'))",
  last_interaction_days:
    "CAST((julianday('now') - julianday(COALESCE(c.last_interaction_at, c.created_at))) AS INTEGER)",
  birthday_window_days:
    // Days until next anniversary of the MM-DD birthday (simple, works for
    // the current year only — good enough for a 7-day window cron).
    "CAST(ABS(julianday(strftime('%Y','now') || '-' || c.birthday) - julianday('now')) AS INTEGER)",
};

/** Validate a single leaf rule object (flat field-op-value form). */
function validateLeaf(leaf: unknown, context: string): SegmentRuleLeaf {
  if (!leaf || typeof leaf !== 'object' || Array.isArray(leaf)) {
    throw new AppError(`${context} must be an object`, 400);
  }
  const rule = leaf as SegmentRuleLeaf;
  for (const field of Object.keys(rule)) {
    if (!(field in SEGMENT_FIELD_EXPRESSIONS)) {
      throw new AppError(`rule field '${field}' is not allowed`, 400);
    }
    const ops = rule[field];
    if (!ops || typeof ops !== 'object') throw new AppError(`rule field '${field}' must be an object`, 400);
    for (const op of Object.keys(ops)) {
      if (!SEGMENT_OPS.includes(op as ComparisonOp)) {
        throw new AppError(`rule op '${op}' is not allowed`, 400);
      }
    }
  }
  return rule;
}

function parseSegmentRule(ruleJson: string): SegmentRule {
  let parsed: unknown;
  try {
    parsed = JSON.parse(ruleJson);
  } catch {
    throw new AppError('rule must be valid JSON', 400);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new AppError('rule must be an object', 400);
  }
  // Detect compound form: { op: 'and'|'or', conditions: [...] }
  const obj = parsed as Record<string, unknown>;
  if ('op' in obj && 'conditions' in obj) {
    if (obj.op !== 'and' && obj.op !== 'or') {
      throw new AppError("rule.op must be 'and' or 'or'", 400);
    }
    if (!Array.isArray(obj.conditions) || obj.conditions.length === 0) {
      throw new AppError('rule.conditions must be a non-empty array', 400);
    }
    if (obj.conditions.length > 10) {
      throw new AppError('rule.conditions may not exceed 10 entries', 400);
    }
    const conditions = obj.conditions.map((c: unknown, i: number) =>
      validateLeaf(c, `rule.conditions[${i}]`),
    );
    return { op: obj.op as 'and' | 'or', conditions };
  }
  // Legacy flat form: { field: { op: value }, ... }
  return validateLeaf(parsed, 'rule');
}

/**
 * Build WHERE clauses for a single leaf rule (flat field-op-value form).
 */
function buildLeafWhere(leaf: SegmentRuleLeaf): { clauses: string[]; params: unknown[] } {
  const clauses: string[] = [];
  const params: unknown[] = [];
  for (const [field, ops] of Object.entries(leaf)) {
    const expr = SEGMENT_FIELD_EXPRESSIONS[field];
    if (!expr) continue;
    for (const [op, value] of Object.entries(ops)) {
      if (!SEGMENT_OPS.includes(op as ComparisonOp)) continue;
      // Ensure birthday_window_days NULL → excluded.
      if (field === 'birthday_window_days') {
        clauses.push(`(c.birthday IS NOT NULL AND ${expr} ${op} ?)`);
      } else {
        clauses.push(`(${expr} ${op} ?)`);
      }
      params.push(value);
    }
  }
  return { clauses, params };
}

/**
 * Translate a parsed rule into a parameterised WHERE clause over customers c.
 * Returns { whereSql, params }. Never splices user strings into SQL directly.
 * Supports both the flat legacy form and the compound { op, conditions } form.
 */
function buildSegmentWhere(rule: SegmentRule): { whereSql: string; params: unknown[] } {
  // Compound form: { op: 'and'|'or', conditions: [...] }
  if ('op' in rule && 'conditions' in rule) {
    const compound = rule as SegmentRuleCompound;
    const allClauses: string[] = [];
    const allParams: unknown[] = [];
    for (const leaf of compound.conditions) {
      const { clauses, params } = buildLeafWhere(leaf);
      allClauses.push(...clauses);
      allParams.push(...params);
    }
    if (allClauses.length === 0) return { whereSql: '1=1', params: [] };
    const joiner = compound.op === 'or' ? ' OR ' : ' AND ';
    return { whereSql: allClauses.join(joiner), params: allParams };
  }
  // Legacy flat form
  const { clauses, params } = buildLeafWhere(rule as SegmentRuleLeaf);
  if (clauses.length === 0) return { whereSql: '1=1', params: [] };
  return { whereSql: clauses.join(' AND '), params };
}

/**
 * Rebuild the membership list for a segment. Deletes old members and inserts
 * the fresh set. Returns the new member count.
 */
export async function refreshSegmentMembership(
  adb: AsyncDb,
  segment: SegmentRow,
): Promise<number> {
  const rule = parseSegmentRule(segment.rule_json);
  const { whereSql, params } = buildSegmentWhere(rule);

  const matched = await adb.all<{ id: number }>(
    `SELECT c.id FROM customers c WHERE ${whereSql}`,
    ...params,
  );

  // Simple rebuild: delete + insert. Safe because the table is small and
  // segment_id is indexed.
  await adb.run(`DELETE FROM customer_segment_members WHERE segment_id = ?`, segment.id);

  for (const row of matched) {
    try {
      await adb.run(
        `INSERT OR IGNORE INTO customer_segment_members (segment_id, customer_id) VALUES (?, ?)`,
        segment.id,
        row.id,
      );
    } catch (err) {
      log.warn('Failed to insert segment member', {
        segment_id: segment.id,
        customer_id: row.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  await adb.run(
    `UPDATE customer_segments
        SET member_count = ?, last_refreshed_at = datetime('now')
      WHERE id = ?`,
    matched.length,
    segment.id,
  );

  return matched.length;
}

// ---------------------------------------------------------------------------
// Customer review moderation — GET /crm/reviews, PATCH /crm/reviews/:id
// ---------------------------------------------------------------------------

/**
 * GET /crm/reviews
 * List all customer_reviews (newest first), with customer + ticket context.
 * Query params: page, pagesize (default 25), rating (1-5 filter), replied (true|false)
 */
router.get(
  '/reviews',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 25);
    const ratingFilter = req.query.rating ? parseInt(req.query.rating as string, 10) : null;
    const repliedFilter = req.query.replied as string | undefined;

    const conditions: string[] = [];
    const params: unknown[] = [];

    if (ratingFilter !== null && Number.isInteger(ratingFilter) && ratingFilter >= 1 && ratingFilter <= 5) {
      conditions.push('r.rating = ?');
      params.push(ratingFilter);
    }
    if (repliedFilter === 'true') {
      conditions.push('r.responded_at IS NOT NULL');
    } else if (repliedFilter === 'false') {
      conditions.push('r.responded_at IS NULL');
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const { total } = await adb.get<{ total: number }>(
      `SELECT COUNT(*) as total FROM customer_reviews r ${whereClause}`,
      ...params,
    ) as { total: number };

    const offset = (page - 1) * pageSize;
    const reviews = await adb.all<Record<string, unknown>>(
      `SELECT r.*,
         c.first_name AS customer_first_name, c.last_name AS customer_last_name,
         t.order_id AS ticket_order_id
       FROM customer_reviews r
       LEFT JOIN customers c ON c.id = r.customer_id
       LEFT JOIN tickets  t ON t.id = r.ticket_id
       ${whereClause}
       ORDER BY r.created_at DESC
       LIMIT ? OFFSET ?`,
      ...params,
      pageSize,
      offset,
    );

    res.json({
      success: true,
      data: {
        reviews,
        pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
      },
    });
  }),
);

/**
 * PATCH /crm/reviews/:id
 * Reply to a review (sets `response` + `responded_at`) or mark it public_posted.
 * Body: { response?: string; public_posted?: boolean }
 */
router.patch(
  '/reviews/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const db = req.db;
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid review ID', 400);

    const existing = await adb.get<Record<string, unknown>>(
      'SELECT * FROM customer_reviews WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Review not found', 404);

    const { response, public_posted } = req.body as { response?: unknown; public_posted?: unknown };

    const updatedResponse = response !== undefined
      ? validateTextLength(String(response), 2000, 'response')
      : (existing.response as string | null);

    const updatedPublicPosted = public_posted !== undefined
      ? (public_posted ? 1 : 0)
      : (existing.public_posted as number);

    // Set responded_at only when a reply text is newly provided
    const respondedAt = (response !== undefined && String(response).trim().length > 0)
      ? "datetime('now')"
      : null;

    await adb.run(
      `UPDATE customer_reviews
          SET response = ?,
              responded_at = ${respondedAt ?? 'responded_at'},
              public_posted = ?
        WHERE id = ?`,
      updatedResponse,
      updatedPublicPosted,
      id,
    );

    audit(db, 'review_replied', req.user!.id, req.ip || 'unknown', { review_id: id });

    const updated = await adb.get<Record<string, unknown>>(
      'SELECT * FROM customer_reviews WHERE id = ?',
      id,
    );
    res.json({ success: true, data: updated });
  }),
);

export default router;
