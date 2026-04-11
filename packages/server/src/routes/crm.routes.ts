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

const log = createLogger('crm');
const router = Router();

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
interface SegmentRule {
  [field: string]: { [op in ComparisonOp]?: string | number };
}

// -----------------------------------------------------------------------------
// Health score endpoints
// -----------------------------------------------------------------------------

router.get(
  '/customers/:id/health-score',
  asyncHandler(async (req, res) => {
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

    res.json({ success: true, data: photos });
  }),
);

// -----------------------------------------------------------------------------
// Wallet pass (HTML fallback or .pkpass)
// -----------------------------------------------------------------------------

router.get(
  '/customers/:id/wallet-pass',
  asyncHandler(async (req, res) => {
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

    // Try a few times in case of uniqueness collisions on the short code.
    let code = mintReferralCode(customer.first_name);
    for (let i = 0; i < 5; i += 1) {
      try {
        await adb.run(
          `INSERT INTO referrals (referrer_customer_id, referral_code) VALUES (?, ?)`,
          id,
          code,
        );
        break;
      } catch (err) {
        if (i === 4) throw err;
        code = mintReferralCode(customer.first_name);
      }
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

    const result = await adb.run(
      `INSERT INTO service_subscriptions
         (customer_id, plan_name, monthly_cents, next_billing_date, card_token)
       VALUES (?, ?, ?, ?, ?)`,
      id,
      planName,
      Math.round(monthly * 100),
      nextBillingDate,
      typeof body.card_token === 'string' ? body.card_token : null,
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
    const db = req.db;
    const adb = req.asyncDb;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const name = validateRequiredString(body.name, 'name', 100);
    const description = typeof body.description === 'string' ? body.description.slice(0, 500) : null;
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
      params.push(typeof body.description === 'string' ? body.description.slice(0, 500) : null);
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
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid segment id', 400);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(200, Math.max(1, parseInt(req.query.pagesize as string, 10) || 50));
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
  const rule = parsed as SegmentRule;
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

/**
 * Translate a parsed rule into a parameterised WHERE clause over customers c.
 * Returns { whereSql, params }. Never splices user strings into SQL directly.
 */
function buildSegmentWhere(rule: SegmentRule): { whereSql: string; params: unknown[] } {
  const clauses: string[] = [];
  const params: unknown[] = [];
  for (const [field, ops] of Object.entries(rule)) {
    const expr = SEGMENT_FIELD_EXPRESSIONS[field];
    if (!expr) continue;
    for (const [op, value] of Object.entries(ops)) {
      if (!SEGMENT_OPS.includes(op as ComparisonOp)) continue;
      // Ensure birthday_window_days NULL → excluded (LIKE check below).
      if (field === 'birthday_window_days') {
        clauses.push(`(c.birthday IS NOT NULL AND ${expr} ${op} ?)`);
      } else {
        clauses.push(`(${expr} ${op} ?)`);
      }
      params.push(value);
    }
  }
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

export default router;
