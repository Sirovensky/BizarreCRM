/**
 * Campaigns routes — Marketing automations (audit §49 — ideas 3, 4, 5, 10)
 *
 * Endpoints:
 *   GET    /campaigns
 *   POST   /campaigns
 *   GET    /campaigns/:id
 *   PATCH  /campaigns/:id
 *   DELETE /campaigns/:id
 *   POST   /campaigns/:id/run-now            — dispatches to segment now
 *   POST   /campaigns/:id/preview            — dry-run, returns count + sample
 *   GET    /campaigns/:id/stats              — sent/replied/converted counts
 *   POST   /campaigns/review-request/trigger — hook from ticket pickup event
 *   POST   /campaigns/birthday/dispatch      — daily cron helper
 *   POST   /campaigns/winback/dispatch       — daily cron helper
 *   POST   /campaigns/churn-warning/dispatch — daily cron helper
 *
 * TCPA compliance:
 *   Marketing SMS blasts: customers must have sms_opt_in = 1 AND
 *     sms_consent_marketing = 1 (migration 063, strict TCPA marketing consent).
 *   Transactional SMS (review-request trigger): gated on sms_opt_in only;
 *     sms_consent_marketing exempted under prior-business-relationship rule.
 *   Email: gated on email_opt_in = 1 (email_consent_marketing not yet added).
 *   These rules are enforced in `fetchEligibleRecipients()` and in the
 *   churn-warning dispatch path; they cannot be overridden by a campaign.
 *
 * All send operations call sendSmsTenant() and inspect the response. If the
 * provider returns success=false OR the factory silently fell back to console
 * (see L2 in critical audit), the campaign_send row is marked status='failed'
 * with the reason in .response. No lying about success.
 */

import crypto from 'crypto';
import { Router, Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { escapeHtml } from '../utils/escape.js';
import {
  validateRequiredString,
  validateEnum,
  validateTextLength,
  validateJsonPayload,
  validateIntegerQuantity,
} from '../utils/validate.js';
import {
  sendSmsTenant,
  isProviderRealOrSimulated,
  getSmsProvider,
} from '../services/smsProvider.js';
import { sendEmail, isEmailConfigured } from '../services/email.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { refreshSegmentMembership } from './crm.routes.js';

// SCAN-1039: mass-dispatch endpoints can fire SMS/email to thousands of
// recipients in one call. Rate-limit per-user so even an admin can't
// accidentally loop a dispatch and burn a month of SMS credit. 3/min is
// generous — legitimate use rarely goes above once per several minutes.
const CAMPAIGN_DISPATCH_MAX = 3;
const CAMPAIGN_DISPATCH_WINDOW_MS = 60_000;
function rateLimitCampaignDispatch(req: Request): void {
  const key = String(req.user?.id ?? 'anon');
  const rl = consumeWindowRate(req.db, 'campaign_dispatch', key, CAMPAIGN_DISPATCH_MAX, CAMPAIGN_DISPATCH_WINDOW_MS);
  if (!rl.allowed) throw new AppError('Too many campaign dispatches — please wait a minute before retrying', 429);
}
import type { AsyncDb } from '../db/async-db.js';

const log = createLogger('campaigns');
const router = Router();

// SEC (post-enrichment audit §6): every marketing campaign can send mass
// SMS / email — admin only per audit scope. Keeping this as a single
// inline gate simplifies audit review.
function requireAdminCampaigns(req: any): void {
  if (req?.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
  }
}

// -----------------------------------------------------------------------------
// Shared types
// -----------------------------------------------------------------------------

const CAMPAIGN_TYPES = [
  'birthday',
  'winback',
  'review_request',
  'churn_warning',
  'service_subscription',
  'custom',
] as const;
type CampaignType = (typeof CAMPAIGN_TYPES)[number];

const CAMPAIGN_CHANNELS = ['sms', 'email', 'both'] as const;
type CampaignChannel = (typeof CAMPAIGN_CHANNELS)[number];

const CAMPAIGN_STATUSES = ['draft', 'active', 'paused', 'archived'] as const;
type CampaignStatus = (typeof CAMPAIGN_STATUSES)[number];

interface CampaignRow {
  id: number;
  name: string;
  type: CampaignType;
  segment_id: number | null;
  channel: CampaignChannel;
  template_subject: string | null;
  template_body: string;
  trigger_rule_json: string | null;
  status: CampaignStatus;
  sent_count: number;
  replied_count: number;
  converted_count: number;
  created_at: string;
  last_run_at: string | null;
}

interface RecipientRow {
  id: number;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  mobile: string | null;
  birthday?: string | null;
  last_interaction_at?: string | null;
  customer_created_at?: string | null;
  invoice_number?: string | null;
  sms_opt_in: number;
  email_opt_in: number;
  /** TCPA strict marketing consent (migration 063). Required = 1 for bulk marketing sends. */
  sms_consent_marketing: number;
}

type TriggerRuleObject = Record<string, unknown>;

function parseCampaignTriggerRule(campaign: Pick<CampaignRow, 'trigger_rule_json'>): TriggerRuleObject {
  if (!campaign.trigger_rule_json) return {};
  try {
    const parsed = JSON.parse(campaign.trigger_rule_json);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as TriggerRuleObject;
    }
  } catch {
    // Malformed JSON should have been rejected on write. Treat old/corrupt
    // rows as "use defaults" so dispatch remains available instead of taking
    // the campaign worker down.
  }
  return {};
}

function triggerInt(rule: TriggerRuleObject, keys: readonly string[], fallback: number, min: number, max: number): number {
  for (const key of keys) {
    const value = rule[key];
    const parsed = typeof value === 'number' ? value : (typeof value === 'string' ? Number(value) : NaN);
    if (Number.isFinite(parsed)) {
      return Math.max(min, Math.min(max, Math.floor(parsed)));
    }
  }
  return fallback;
}

function birthdayDaysBefore(campaign: CampaignRow): number {
  return triggerInt(parseCampaignTriggerRule(campaign), ['days_before', 'birthday_days_before'], 7, 0, 30);
}

function winbackInactiveDays(campaign: CampaignRow): number {
  return triggerInt(parseCampaignTriggerRule(campaign), ['inactive_days', 'last_interaction_days'], 90, 1, 730);
}

function unpaidInvoiceDays(campaign: CampaignRow): number {
  return triggerInt(parseCampaignTriggerRule(campaign), ['unpaid_days', 'days_overdue', 'invoice_age_days'], 14, 1, 365);
}

const BIRTHDAY_DAYS_UNTIL_SQL = `
  CAST((
    julianday(
      CASE
        WHEN date(strftime('%Y','now') || '-' || c.birthday) >= date('now')
          THEN date(strftime('%Y','now') || '-' || c.birthday)
        ELSE date(printf('%04d-%s', CAST(strftime('%Y','now') AS INTEGER) + 1, c.birthday))
      END
    ) - julianday(date('now'))
  ) AS INTEGER)
`;

const CUSTOMER_LAST_ACTIVITY_SQL = `COALESCE((
  SELECT MAX(ts) FROM (
    SELECT c.last_interaction_at AS ts
    UNION ALL
      SELECT MAX(t.created_at) AS ts
        FROM tickets t
       WHERE t.customer_id = c.id
         AND t.is_deleted = 0
    UNION ALL
      SELECT MAX(i.created_at) AS ts
        FROM invoices i
       WHERE i.customer_id = c.id
         AND COALESCE(i.status,'') != 'void'
  )
), c.created_at)`;

function marketingChannelWhere(channel: CampaignChannel): string {
  const smsContactable = `
    (COALESCE(c.sms_opt_in,0) = 1
      AND COALESCE(c.sms_consent_marketing,0) = 1
      AND COALESCE(NULLIF(c.mobile,''), NULLIF(c.phone,'')) IS NOT NULL)
  `;
  const emailContactable = `
    (COALESCE(c.email_opt_in,0) = 1
      AND NULLIF(c.email,'') IS NOT NULL)
  `;
  if (channel === 'sms') return smsContactable;
  if (channel === 'email') return emailContactable;
  return `(${smsContactable} OR ${emailContactable})`;
}

function duplicateSuppressionWhere(windowSql: string): string {
  return `NOT EXISTS (
    SELECT 1 FROM campaign_sends cs
     WHERE cs.campaign_id = ?
       AND cs.customer_id = c.id
       AND cs.status = 'sent'
       AND cs.sent_at >= datetime('now','-${windowSql}')
  )`;
}

function buildEligibleRecipientQuery(
  campaign: CampaignRow,
  opts: { count?: boolean; limit?: number | null } = {},
): { sql: string; params: unknown[] } {
  const where: string[] = ['c.is_deleted = 0', marketingChannelWhere(campaign.channel)];
  const joins: string[] = [];
  const whereParams: unknown[] = [];
  const selectParams: unknown[] = [];
  let extraSelect = '';

  if (campaign.segment_id) {
    joins.push('JOIN customer_segment_members m ON m.customer_id = c.id');
    where.push('m.segment_id = ?');
    whereParams.push(campaign.segment_id);
  }

  // WEB-UIUX-879: never request a review from a customer who got a refund
  // (credit-note invoice or refunds-table row) in the last 14 days. The
  // automated "How was your repair?" SMS is the worst possible follow-up
  // to a refund-issuing visit; risk = 1-star review + word-of-mouth churn.
  // Heuristic uses credit-note invoice rows (positive signal a refund just
  // happened); covers both native credit-note flow and POS-return flow.
  if (campaign.type === 'review_request') {
    where.push(`NOT EXISTS (
      SELECT 1 FROM invoices i
       WHERE i.customer_id = c.id
         AND (i.credit_note_for IS NOT NULL OR i.status = 'credit_note' OR i.status = 'refunded')
         AND julianday('now') - julianday(i.created_at) <= 14
    )`);
  }

  if (campaign.type === 'birthday') {
    const days = birthdayDaysBefore(campaign);
    where.push('c.birthday IS NOT NULL');
    where.push(`${BIRTHDAY_DAYS_UNTIL_SQL} BETWEEN 0 AND ?`);
    whereParams.push(days);
    where.push(duplicateSuppressionWhere('335 days'));
    whereParams.push(campaign.id);
  } else if (campaign.type === 'winback') {
    const inactiveDays = winbackInactiveDays(campaign);
    where.push(`CAST((julianday('now') - julianday(${CUSTOMER_LAST_ACTIVITY_SQL})) AS INTEGER) >= ?`);
    whereParams.push(inactiveDays);
    where.push(duplicateSuppressionWhere('30 days'));
    whereParams.push(campaign.id);
  } else if (campaign.type === 'churn_warning') {
    const unpaidDays = unpaidInvoiceDays(campaign);
    const invoiceAgePredicate = `
      i.customer_id = c.id
      AND COALESCE(i.amount_due,0) > 0
      AND COALESCE(i.status,'') NOT IN ('void','cancelled','paid')
      AND julianday(COALESCE(i.due_date, i.created_at)) <= julianday('now', ?)
    `;
    const ageModifier = `-${unpaidDays} days`;
    extraSelect = `, (
      SELECT i.order_id
        FROM invoices i
       WHERE ${invoiceAgePredicate}
       ORDER BY julianday(COALESCE(i.due_date, i.created_at)) ASC, i.id ASC
       LIMIT 1
    ) AS invoice_number`;
    selectParams.push(ageModifier);
    where.push(`EXISTS (SELECT 1 FROM invoices i WHERE ${invoiceAgePredicate})`);
    whereParams.push(ageModifier);
    where.push(duplicateSuppressionWhere('30 days'));
    whereParams.push(campaign.id);
  }

  const limit = opts.limit == null ? '' : ` LIMIT ${Math.max(1, Math.floor(opts.limit))}`;
  if (opts.count) {
    return {
      sql: `
        SELECT COUNT(*) AS total
          FROM customers c
          ${joins.join('\n')}
         WHERE ${where.join(' AND ')}
      `,
      params: whereParams,
    };
  }

  return {
    sql: `
      SELECT c.id, c.first_name, c.last_name, c.email, c.phone, c.mobile,
             c.birthday, c.last_interaction_at, c.created_at AS customer_created_at,
             COALESCE(c.sms_opt_in,0) AS sms_opt_in,
             COALESCE(c.email_opt_in,0) AS email_opt_in,
             COALESCE(c.sms_consent_marketing,0) AS sms_consent_marketing
             ${extraSelect}
        FROM customers c
        ${joins.join('\n')}
       WHERE ${where.join(' AND ')}
       ORDER BY c.id
       ${limit}
    `,
    params: [...selectParams, ...whereParams],
  };
}

async function countEligibleRecipients(adb: AsyncDb, campaign: CampaignRow): Promise<number> {
  const query = buildEligibleRecipientQuery(campaign, { count: true });
  const row = await adb.get<{ total: number }>(query.sql, ...query.params);
  return row?.total ?? 0;
}

// -----------------------------------------------------------------------------
// Template rendering
// -----------------------------------------------------------------------------

/**
 * Render a template with plain-text interpolation (for SMS / plain-text email bodies).
 * Values are inserted as-is — safe for plain-text but NOT for HTML.
 */
function renderTemplate(
  template: string,
  ctx: Record<string, string | number | null | undefined>,
): string {
  return template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, key) => {
    const v = ctx[key];
    if (v === null || v === undefined) return '';
    return String(v);
  });
}

/**
 * Render a template with HTML-escaped interpolation (for HTML email bodies).
 * SEC-1: Customer-supplied values (names, etc.) are escaped to prevent stored XSS
 * in email clients. The template itself (admin-authored) is NOT escaped.
 */
function renderTemplateHtml(
  template: string,
  ctx: Record<string, string | number | null | undefined>,
): string {
  return template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, key) => {
    const v = ctx[key];
    if (v === null || v === undefined) return '';
    return escapeHtml(String(v));
  });
}

// -----------------------------------------------------------------------------
// Recipient gathering + opt-in filtering (TCPA)
// -----------------------------------------------------------------------------

async function fetchEligibleRecipients(
  adb: AsyncDb,
  campaign: CampaignRow,
  limit: number | null = null,
): Promise<RecipientRow[]> {
  const query = buildEligibleRecipientQuery(campaign, { limit: limit ?? 5_000 });
  return adb.all<RecipientRow>(query.sql, ...query.params);
}

async function refreshCampaignSegment(adb: AsyncDb, campaign: CampaignRow): Promise<number | null> {
  if (!campaign.segment_id) return null;
  const segment = await adb.get<any>(
    `SELECT * FROM customer_segments WHERE id = ?`,
    campaign.segment_id,
  );
  if (!segment) return null;
  return refreshSegmentMembership(adb, segment);
}

// -----------------------------------------------------------------------------
// Dispatch core — used by run-now, review-request trigger, birthday cron.
// -----------------------------------------------------------------------------

interface DispatchResult {
  readonly attempted: number;
  readonly sent: number;
  readonly failed: number;
  readonly skipped: number;
}

async function dispatchCampaign(
  db: any,
  adb: AsyncDb,
  tenantSlug: string | null,
  campaign: CampaignRow,
  recipients: readonly RecipientRow[],
): Promise<DispatchResult> {
  let sent = 0;
  let failed = 0;
  let skipped = 0;

  // Sanity: if the provider is console-only AND the channel is sms, we still
  // fail each recipient rather than pretending. This prevents the whole
  // L1-L4 "lies about success" class of bugs.
  const provider = getSmsProvider();
  const providerStatus = isProviderRealOrSimulated(provider);
  const providerIsReal = providerStatus.real;

  const canSendSms = (recipient: RecipientRow): boolean => {
    if (!recipient.sms_opt_in) return false;
    if (campaign.type === 'review_request') return true;
    return recipient.sms_consent_marketing === 1;
  };
  const canSendEmail = (recipient: RecipientRow): boolean => recipient.email_opt_in === 1;

  for (const recipient of recipients) {
    const phone = recipient.mobile || recipient.phone;
    const ctx = {
      first_name: recipient.first_name ?? 'there',
      last_name: recipient.last_name ?? '',
      invoice_number: recipient.invoice_number ?? '',
    };
    const body = renderTemplate(campaign.template_body, ctx);

    // SMS path
    if (campaign.channel === 'sms' || campaign.channel === 'both') {
      if (!phone || !canSendSms(recipient)) {
        skipped += 1;
        if (campaign.channel === 'sms') continue;
      } else if (!providerIsReal) {
        failed += 1;
        await adb.run(
          `INSERT INTO campaign_sends (campaign_id, customer_id, status, response)
           VALUES (?, ?, 'failed', ?)`,
          campaign.id,
          recipient.id,
          'SMS provider not configured (console fallback)',
        );
      } else {
        try {
          const result = await sendSmsTenant(db, tenantSlug, phone, body);
          if (result?.success) {
            sent += 1;
            await adb.run(
              `INSERT INTO campaign_sends (campaign_id, customer_id, status) VALUES (?, ?, 'sent')`,
              campaign.id,
              recipient.id,
            );
          } else {
            failed += 1;
            await adb.run(
              `INSERT INTO campaign_sends (campaign_id, customer_id, status, response) VALUES (?, ?, 'failed', ?)`,
              campaign.id,
              recipient.id,
              result?.error ?? 'unknown SMS provider error',
            );
          }
        } catch (err) {
          failed += 1;
          await adb.run(
            `INSERT INTO campaign_sends (campaign_id, customer_id, status, response) VALUES (?, ?, 'failed', ?)`,
            campaign.id,
            recipient.id,
            err instanceof Error ? err.message : String(err),
          );
        }
      }
    }

    // Email path
    if ((campaign.channel === 'email' || campaign.channel === 'both') && recipient.email && canSendEmail(recipient)) {
      if (!isEmailConfigured(db)) {
        failed += 1;
        // Record the failure reason so the stats endpoint surfaces "why
        // nothing sent" — previously we bumped failed++ without a row,
        // hiding the configuration problem from the admin.
        await adb.run(
          `INSERT INTO campaign_sends (campaign_id, customer_id, status, response) VALUES (?, ?, 'failed', ?)`,
          campaign.id,
          recipient.id,
          'SMTP not configured',
        );
        continue;
      }
      try {
        const subject = campaign.template_subject
          ? renderTemplate(campaign.template_subject, ctx)
          : campaign.name;
        // SEC-1: Use HTML-escaped body for the HTML version of the email.
        // The plain-text `body` (renderTemplate) is used for the text fallback.
        const htmlBody = renderTemplateHtml(campaign.template_body, ctx);
        const emailResult = await sendEmail(db, {
          to: recipient.email,
          subject,
          html: htmlBody.replace(/\n/g, '<br>'),
          text: body,
        });
        if (emailResult) {
          sent += 1;
          await adb.run(
            `INSERT INTO campaign_sends (campaign_id, customer_id, status) VALUES (?, ?, 'sent')`,
            campaign.id,
            recipient.id,
          );
        } else {
          failed += 1;
          await adb.run(
            `INSERT INTO campaign_sends (campaign_id, customer_id, status, response) VALUES (?, ?, 'failed', ?)`,
            campaign.id,
            recipient.id,
            'email transport returned false',
          );
        }
      } catch (err) {
        failed += 1;
        const errMsg = err instanceof Error ? err.message : String(err);
        log.warn('Campaign email send failed', {
          campaign_id: campaign.id,
          customer_id: recipient.id,
          error: errMsg,
        });
        await adb.run(
          `INSERT INTO campaign_sends (campaign_id, customer_id, status, response) VALUES (?, ?, 'failed', ?)`,
          campaign.id,
          recipient.id,
          errMsg,
        );
      }
    }
  }

  await adb.run(
    `UPDATE marketing_campaigns
        SET sent_count = sent_count + ?,
            last_run_at = datetime('now')
      WHERE id = ?`,
    sent,
    campaign.id,
  );

  return { attempted: recipients.length, sent, failed, skipped };
}

// -----------------------------------------------------------------------------
// CRUD
// -----------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const adb = req.asyncDb;
    const rows = await adb.all<CampaignRow>(
      `SELECT * FROM marketing_campaigns ORDER BY created_at DESC`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const db = req.db;
    const adb = req.asyncDb;
    const body = (req.body ?? {}) as Record<string, unknown>;

    const name = validateRequiredString(body.name, 'name', 100);
    const type = validateEnum(body.type, CAMPAIGN_TYPES, 'type')!;
    const channel = validateEnum(body.channel, CAMPAIGN_CHANNELS, 'channel')!;
    const template_body = validateRequiredString(body.template_body, 'template_body', 1600);
    const template_subject = validateTextLength(
      typeof body.template_subject === 'string' ? body.template_subject : undefined,
      200,
      'template_subject',
    ) || null;
    let segment_id: number | null = null;
    if (body.segment_id !== undefined && body.segment_id !== null) {
      segment_id = validateIntegerQuantity(body.segment_id, 'segment_id');
      const seg = await adb.get('SELECT id FROM customer_segments WHERE id = ?', segment_id);
      if (!seg) throw new AppError('Segment not found', 404);
    }
    // trigger_rule_json: allow either a string or an object. Use
    // validateJsonPayload to reject circular refs + >16KB blobs.
    let trigger_rule_json: string | null = null;
    if (body.trigger_rule_json !== undefined && body.trigger_rule_json !== null) {
      if (typeof body.trigger_rule_json === 'string') {
        // Re-parse so we canonicalise + enforce size bound via the validator.
        let parsed: unknown;
        try {
          parsed = JSON.parse(body.trigger_rule_json);
        } catch {
          throw new AppError('trigger_rule_json must be valid JSON', 400);
        }
        trigger_rule_json = validateJsonPayload(parsed, 'trigger_rule_json', 16_384);
      } else {
        trigger_rule_json = validateJsonPayload(
          body.trigger_rule_json,
          'trigger_rule_json',
          16_384,
        );
      }
    }

    const result = await adb.run(
      `INSERT INTO marketing_campaigns
         (name, type, segment_id, channel, template_subject, template_body, trigger_rule_json, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'draft')`,
      name,
      type,
      segment_id,
      channel,
      template_subject,
      template_body,
      trigger_rule_json,
    );

    audit(db, 'campaign_created', req.user!.id, req.ip || 'unknown', {
      campaign_id: result.lastInsertRowid,
      name,
      type,
    });

    res.status(201).json({
      success: true,
      data: {
        id: result.lastInsertRowid,
        name,
        type,
        segment_id,
        channel,
        template_subject,
        template_body,
        trigger_rule_json,
        status: 'draft',
      },
    });
  }),
);

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid campaign id', 400);
    const row = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE id = ?`,
      id,
    );
    if (!row) throw new AppError('Campaign not found', 404);
    res.json({ success: true, data: row });
  }),
);

router.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid campaign id', 400);
    const existing = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE id = ?`,
      id,
    );
    if (!existing) throw new AppError('Campaign not found', 404);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const fields: string[] = [];
    const params: unknown[] = [];

    if (body.name !== undefined) {
      fields.push('name = ?');
      params.push(validateRequiredString(body.name, 'name', 100));
    }
    if (body.channel !== undefined) {
      fields.push('channel = ?');
      params.push(validateEnum(body.channel, CAMPAIGN_CHANNELS, 'channel')!);
    }
    if (body.status !== undefined) {
      fields.push('status = ?');
      params.push(validateEnum(body.status, CAMPAIGN_STATUSES, 'status')!);
    }
    if (body.template_subject !== undefined) {
      fields.push('template_subject = ?');
      params.push(
        validateTextLength(
          typeof body.template_subject === 'string' ? body.template_subject : undefined,
          200,
          'template_subject',
        ) || null,
      );
    }
    if (body.template_body !== undefined) {
      fields.push('template_body = ?');
      params.push(validateRequiredString(body.template_body, 'template_body', 1600));
    }
    if (body.segment_id !== undefined) {
      fields.push('segment_id = ?');
      if (body.segment_id === null) {
        params.push(null);
      } else {
        const segId = validateIntegerQuantity(body.segment_id, 'segment_id');
        const seg = await adb.get('SELECT id FROM customer_segments WHERE id = ?', segId);
        if (!seg) throw new AppError('Segment not found', 404);
        params.push(segId);
      }
    }
    if (body.trigger_rule_json !== undefined) {
      fields.push('trigger_rule_json = ?');
      if (body.trigger_rule_json === null) {
        params.push(null);
      } else if (typeof body.trigger_rule_json === 'string') {
        let parsed: unknown;
        try {
          parsed = JSON.parse(body.trigger_rule_json);
        } catch {
          throw new AppError('trigger_rule_json must be valid JSON', 400);
        }
        params.push(validateJsonPayload(parsed, 'trigger_rule_json', 16_384));
      } else {
        params.push(
          validateJsonPayload(body.trigger_rule_json, 'trigger_rule_json', 16_384),
        );
      }
    }

    if (fields.length === 0) throw new AppError('No fields to update', 400);
    params.push(id);
    await adb.run(`UPDATE marketing_campaigns SET ${fields.join(', ')} WHERE id = ?`, ...params);

    audit(db, 'campaign_updated', req.user!.id, req.ip || 'unknown', { campaign_id: id });

    const updated = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE id = ?`,
      id,
    );
    res.json({ success: true, data: updated });
  }),
);

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid campaign id', 400);
    const existing = await adb.get<{ id: number }>(
      `SELECT id FROM marketing_campaigns WHERE id = ?`,
      id,
    );
    if (!existing) throw new AppError('Campaign not found', 404);
    await adb.run(`DELETE FROM marketing_campaigns WHERE id = ?`, id);
    audit(db, 'campaign_deleted', req.user!.id, req.ip || 'unknown', { campaign_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// -----------------------------------------------------------------------------
// Preview + run-now
// -----------------------------------------------------------------------------

router.post(
  '/:id/preview',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid campaign id', 400);
    const campaign = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE id = ?`,
      id,
    );
    if (!campaign) throw new AppError('Campaign not found', 404);

    const segmentTotal = await refreshCampaignSegment(adb, campaign);
    const recipients = await fetchEligibleRecipients(adb, campaign, 10);
    const sampleRendered = recipients.slice(0, 3).map((r) => ({
      customer_id: r.id,
      first_name: r.first_name,
      rendered_body: renderTemplate(campaign.template_body, {
        first_name: r.first_name ?? 'there',
      }),
    }));

    // Count without limit (use a separate COUNT query to avoid OOMing on the
    // full recipient list when the owner only wants a preview). This mirrors
    // the same trigger-rule predicate used by run-now and cron dispatch.
    const total = await countEligibleRecipients(adb, campaign);

    res.json({
      success: true,
      data: {
        campaign_id: id,
        total_recipients: total,
        segment_total: segmentTotal,
        preview: sampleRendered,
      },
    });
  }),
);

router.post(
  '/:id/run-now',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    rateLimitCampaignDispatch(req);
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid campaign id', 400);
    const campaign = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE id = ?`,
      id,
    );
    if (!campaign) throw new AppError('Campaign not found', 404);
    if (campaign.status === 'archived') throw new AppError('Cannot run an archived campaign', 400);

    // WEB-UIUX-701: per-campaign dispatch lock. The existing per-user
    // rateLimitCampaignDispatch guard caps 3/min/user, but two different
    // operators clicking the same campaign within 30s would both fire,
    // duplicating SMS to every recipient. Look at the last_run_at column
    // (also written below by dispatch) and reject when it's within
    // CAMPAIGN_RUN_LOCK_MS. Server-authoritative — no client coordination.
    //
    // BUGHUNT-2026-05-17: convert the read-then-check pattern to an
    // atomic CAS via guarded UPDATE — two parallel /run-now requests
    // could both pass the SELECT precheck (each saw "last_run_at was
    // 35s ago") and both proceed to dispatch, sending duplicate SMS
    // to every recipient. The guarded UPDATE serialises via SQLite's
    // writer lock; only one caller flips last_run_at, the loser sees
    // changes=0 and gets 429 before any dispatch work runs.
    const CAMPAIGN_RUN_LOCK_MS = 30_000;
    const claimResult = await adb.run(
      `UPDATE marketing_campaigns
          SET last_run_at = datetime('now')
        WHERE id = ?
          AND (last_run_at IS NULL OR datetime(last_run_at) <= datetime('now', '-' || ? || ' seconds'))`,
      id,
      Math.ceil(CAMPAIGN_RUN_LOCK_MS / 1000),
    );
    if (claimResult.changes === 0) {
      // Compute a friendly retry-after seconds based on the (newly re-read) last_run_at.
      const fresh = await adb.get<{ last_run_at: string | null }>(
        'SELECT last_run_at FROM marketing_campaigns WHERE id = ?',
        id,
      );
      const rawLast = fresh?.last_run_at ?? '';
      const normalized = rawLast && (rawLast.includes('T') || rawLast.endsWith('Z') || rawLast.includes('+'))
        ? rawLast
        : rawLast ? `${rawLast.replace(' ', 'T')}Z` : '';
      const lastRunMs = normalized ? new Date(normalized).getTime() : 0;
      const sinceMs = Number.isFinite(lastRunMs) && lastRunMs > 0 ? Date.now() - lastRunMs : 0;
      const waitS = Math.max(1, Math.ceil((CAMPAIGN_RUN_LOCK_MS - sinceMs) / 1000));
      throw new AppError(
        `This campaign was dispatched ${Math.round(sinceMs / 1000)}s ago. Wait ${waitS}s before running again so recipients don't get duplicate messages.`,
        429,
      );
    }

    await refreshCampaignSegment(adb, campaign);
    const recipients = await fetchEligibleRecipients(adb, campaign);
    const result = await dispatchCampaign(
      db,
      adb,
      req.tenantSlug || null,
      campaign,
      recipients,
    );

    audit(db, 'campaign_run_now', req.user!.id, req.ip || 'unknown', {
      campaign_id: id,
      attempted: result.attempted,
      sent: result.sent,
      failed: result.failed,
    });

    res.json({ success: true, data: result });
  }),
);

router.get(
  '/:id/stats',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!id || isNaN(id)) throw new AppError('Invalid campaign id', 400);

    const [row, breakdown] = await Promise.all([
      adb.get<CampaignRow>(`SELECT * FROM marketing_campaigns WHERE id = ?`, id),
      adb.all<{ status: string; n: number }>(
        `SELECT status, COUNT(*) AS n FROM campaign_sends
           WHERE campaign_id = ?
           GROUP BY status`,
        id,
      ),
    ]);
    if (!row) throw new AppError('Campaign not found', 404);

    const counts: Record<string, number> = { sent: 0, failed: 0, replied: 0, converted: 0 };
    for (const r of breakdown) counts[r.status] = r.n;

    res.json({
      success: true,
      data: {
        campaign: row,
        counts,
      },
    });
  }),
);

// -----------------------------------------------------------------------------
// Event-driven triggers
// -----------------------------------------------------------------------------

// SCAN-596: This route may be called by an internal server-to-server event
// (e.g. ticket-pickup webhook) in addition to admin UI users. Accept either
// an admin JWT (via requireAdminCampaigns) OR a pre-shared
// X-Internal-Service-Token header matching INTERNAL_SERVICE_TOKEN env var.
//
// If INTERNAL_SERVICE_TOKEN is not set in the environment, this route is
// admin-JWT-only and server-to-server callers must use an admin session.
// Set INTERNAL_SERVICE_TOKEN to a strong random secret to enable that path.
const INTERNAL_SERVICE_TOKEN = (process.env.INTERNAL_SERVICE_TOKEN ?? '').trim();
if (!INTERNAL_SERVICE_TOKEN) {
  // Warn at module load time so operators know the token path is disabled.
  // Using createLogger at module scope would create a circular import risk;
  // a single startup warning via console is acceptable here.
  // eslint-disable-next-line no-console
  console.warn(
    '[campaigns] INTERNAL_SERVICE_TOKEN not set — /review-request/trigger is admin-JWT-only',
  );
}

function requireAdminOrServiceToken(req: Request): void {
  // Fast path: admin JWT.
  if (req?.user?.role === 'admin') return;
  // Alternate path: internal service token (disabled if env var not set).
  // Use timingSafeEqual so a byte-by-byte timing attack can't recover the
  // token via repeated requests.
  if (INTERNAL_SERVICE_TOKEN) {
    const supplied = req.headers['x-internal-service-token'];
    if (typeof supplied === 'string') {
      const a = Buffer.from(supplied);
      const b = Buffer.from(INTERNAL_SERVICE_TOKEN);
      if (a.length === b.length && crypto.timingSafeEqual(a, b)) return;
    }
  }
  throw new AppError('Admin role or internal service token required', 403);
}

router.post(
  '/review-request/trigger',
  asyncHandler(async (req, res) => {
    requireAdminOrServiceToken(req);
    const db = req.db;
    const adb = req.asyncDb;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const ticketId = validateIntegerQuantity(body.ticket_id, 'ticket_id');

    const ticket = await adb.get<{
      id: number;
      customer_id: number;
      order_id: string;
    }>(`SELECT id, customer_id, order_id FROM tickets WHERE id = ?`, ticketId);
    if (!ticket) throw new AppError('Ticket not found', 404);

    const campaign = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE type = 'review_request' AND status = 'active' LIMIT 1`,
    );
    if (!campaign) {
      res.json({
        success: true,
        data: { sent: 0, message: 'No active review_request campaign' },
      });
      return;
    }

    // Fetch the single customer — a transactional send, not a segment blast.
    // SCAN-570: use COALESCE(...,0) so a missing opt-in defaults to opted-OUT.
    // Transactional review-request is exempt from strict sms_consent_marketing
    // (prior-business-relationship exemption), so we only gate on sms_opt_in here.
    const customer = await adb.get<RecipientRow>(
      `SELECT id, first_name, last_name, email, phone, mobile,
              COALESCE(sms_opt_in,0) AS sms_opt_in,
              COALESCE(email_opt_in,0) AS email_opt_in,
              COALESCE(sms_consent_marketing,0) AS sms_consent_marketing
         FROM customers WHERE id = ?`,
      ticket.customer_id,
    );
    if (!customer) throw new AppError('Customer not found', 404);

    const result = await dispatchCampaign(
      db,
      adb,
      req.tenantSlug || null,
      campaign,
      [customer],
    );

    // Called via INTERNAL_SERVICE_TOKEN as well, where req.user is undefined —
    // fall back to 0 (service actor sentinel) instead of throwing on null deref.
    audit(db, 'review_request_dispatched', req.user?.id ?? 0, req.ip || 'unknown', {
      campaign_id: campaign.id,
      ticket_id: ticketId,
      customer_id: customer.id,
      sent: result.sent,
    });

    res.json({ success: true, data: result });
  }),
);

router.post(
  '/birthday/dispatch',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    rateLimitCampaignDispatch(req);
    const db = req.db;
    const adb = req.asyncDb;

    const campaign = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE type = 'birthday' AND status = 'active' LIMIT 1`,
    );
    if (!campaign) {
      res.json({
        success: true,
        data: { sent: 0, message: 'No active birthday campaign' },
      });
      return;
    }

    if (campaign.segment_id) {
      const seg = await adb.get<any>(
        `SELECT * FROM customer_segments WHERE id = ?`,
        campaign.segment_id,
      );
      if (seg) await refreshSegmentMembership(adb, seg);
    }

    const recipients = await fetchEligibleRecipients(adb, campaign);
    const result = await dispatchCampaign(db, adb, req.tenantSlug || null, campaign, recipients);

    audit(db, 'birthday_campaign_dispatched', req.user!.id, req.ip || 'unknown', {
      campaign_id: campaign.id,
      attempted: result.attempted,
      sent: result.sent,
    });

    res.json({ success: true, data: result });
  }),
);

router.post(
  '/winback/dispatch',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    rateLimitCampaignDispatch(req);
    const db = req.db;
    const adb = req.asyncDb;

    const campaign = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE type = 'winback' AND status = 'active' LIMIT 1`,
    );
    if (!campaign) {
      res.json({
        success: true,
        data: { sent: 0, message: 'No active winback campaign' },
      });
      return;
    }

    if (campaign.segment_id) {
      const seg = await adb.get<any>(
        `SELECT * FROM customer_segments WHERE id = ?`,
        campaign.segment_id,
      );
      if (seg) await refreshSegmentMembership(adb, seg);
    }

    const recipients = await fetchEligibleRecipients(adb, campaign);
    const result = await dispatchCampaign(db, adb, req.tenantSlug || null, campaign, recipients);

    audit(db, 'winback_campaign_dispatched', req.user!.id, req.ip || 'unknown', {
      campaign_id: campaign.id,
      attempted: result.attempted,
      sent: result.sent,
    });

    res.json({ success: true, data: result });
  }),
);

router.post(
  '/churn-warning/dispatch',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
    rateLimitCampaignDispatch(req);
    const db = req.db;
    const adb = req.asyncDb;

    const campaign = await adb.get<CampaignRow>(
      `SELECT * FROM marketing_campaigns WHERE type = 'churn_warning' AND status = 'active' LIMIT 1`,
    );
    if (!campaign) {
      res.json({
        success: true,
        data: { sent: 0, message: 'No active churn_warning campaign' },
      });
      return;
    }

    const recipients = await fetchEligibleRecipients(adb, campaign, 500);
    const result = await dispatchCampaign(db, adb, req.tenantSlug || null, campaign, recipients);

    audit(db, 'churn_warning_dispatched', req.user!.id, req.ip || 'unknown', {
      campaign_id: campaign.id,
      attempted: result.attempted,
      sent: result.sent,
    });

    res.json({ success: true, data: result });
  }),
);

export default router;
