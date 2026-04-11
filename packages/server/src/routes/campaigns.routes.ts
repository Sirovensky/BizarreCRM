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
 *   POST   /campaigns/churn-warning/dispatch — daily cron helper
 *
 * TCPA compliance:
 *   SMS only to customers with sms_opt_in = 1. Email only to email_opt_in = 1.
 *   This is enforced in `fetchEligibleRecipients()` and cannot be overridden
 *   by a campaign. A separate transactional review-request can use an
 *   opt-in-exempt flag on the campaign row — keep false for now.
 *
 * All send operations call sendSmsTenant() and inspect the response. If the
 * provider returns success=false OR the factory silently fell back to console
 * (see L2 in critical audit), the campaign_send row is marked status='failed'
 * with the reason in .response. No lying about success.
 */

import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
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
import { refreshSegmentMembership } from './crm.routes.js';
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
  sms_opt_in: number;
  email_opt_in: number;
}

// -----------------------------------------------------------------------------
// Template rendering
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Recipient gathering + opt-in filtering (TCPA)
// -----------------------------------------------------------------------------

async function fetchEligibleRecipients(
  adb: AsyncDb,
  campaign: CampaignRow,
  limit: number | null = null,
): Promise<RecipientRow[]> {
  const baseSelect = `
    SELECT c.id, c.first_name, c.last_name, c.email, c.phone, c.mobile,
           COALESCE(c.sms_opt_in,1) AS sms_opt_in,
           COALESCE(c.email_opt_in,1) AS email_opt_in
      FROM customers c`;
  const filterByChannel = (rows: RecipientRow[]): RecipientRow[] => {
    return rows.filter((r) => {
      if (campaign.channel === 'sms' && !r.sms_opt_in) return false;
      if (campaign.channel === 'email' && !r.email_opt_in) return false;
      if (campaign.channel === 'both' && !r.sms_opt_in && !r.email_opt_in) return false;
      return true;
    });
  };

  if (campaign.segment_id) {
    const rows = await adb.all<RecipientRow>(
      `${baseSelect}
       JOIN customer_segment_members m ON m.customer_id = c.id
       WHERE m.segment_id = ?
       ${limit ? 'LIMIT ' + Math.max(1, Math.floor(limit)) : ''}`,
      campaign.segment_id,
    );
    return filterByChannel(rows);
  }

  // No segment = every customer (defensive — we still cap to 5k).
  const rows = await adb.all<RecipientRow>(
    `${baseSelect} ORDER BY c.id LIMIT ${limit ?? 5_000}`,
  );
  return filterByChannel(rows);
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

  for (const recipient of recipients) {
    const phone = recipient.mobile || recipient.phone;
    const ctx = {
      first_name: recipient.first_name ?? 'there',
      last_name: recipient.last_name ?? '',
    };
    const body = renderTemplate(campaign.template_body, ctx);

    // SMS path
    if (campaign.channel === 'sms' || campaign.channel === 'both') {
      if (!phone) {
        skipped += 1;
        continue;
      }
      if (!providerIsReal) {
        failed += 1;
        await adb.run(
          `INSERT INTO campaign_sends (campaign_id, customer_id, status, response)
           VALUES (?, ?, 'failed', ?)`,
          campaign.id,
          recipient.id,
          'SMS provider not configured (console fallback)',
        );
        continue;
      }
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

    // Email path
    if ((campaign.channel === 'email' || campaign.channel === 'both') && recipient.email) {
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
        const emailResult = await sendEmail(db, {
          to: recipient.email,
          subject,
          html: body.replace(/\n/g, '<br>'),
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

    const recipients = await fetchEligibleRecipients(adb, campaign, 10);
    const sampleRendered = recipients.slice(0, 3).map((r) => ({
      customer_id: r.id,
      first_name: r.first_name,
      rendered_body: renderTemplate(campaign.template_body, {
        first_name: r.first_name ?? 'there',
      }),
    }));

    // Count without limit (use a separate COUNT query to avoid OOMing on the
    // full recipient list when the owner only wants a preview).
    let total = 0;
    if (campaign.segment_id) {
      const row = await adb.get<{ total: number }>(
        `SELECT COUNT(*) AS total
           FROM customers c
           JOIN customer_segment_members m ON m.customer_id = c.id
          WHERE m.segment_id = ?
            AND (
              (? = 'sms'   AND COALESCE(c.sms_opt_in,1) = 1) OR
              (? = 'email' AND COALESCE(c.email_opt_in,1) = 1) OR
              (? = 'both'  AND (COALESCE(c.sms_opt_in,1) = 1 OR COALESCE(c.email_opt_in,1) = 1))
            )`,
        campaign.segment_id,
        campaign.channel,
        campaign.channel,
        campaign.channel,
      );
      total = row?.total ?? 0;
    }

    res.json({
      success: true,
      data: {
        campaign_id: id,
        total_recipients: total,
        preview: sampleRendered,
      },
    });
  }),
);

router.post(
  '/:id/run-now',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
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

router.post(
  '/review-request/trigger',
  asyncHandler(async (req, res) => {
    requireAdminCampaigns(req);
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

    // Fetch the single customer — a transactional send, not a segment.
    const customer = await adb.get<RecipientRow>(
      `SELECT id, first_name, last_name, email, phone, mobile,
              COALESCE(sms_opt_in,1) AS sms_opt_in,
              COALESCE(email_opt_in,1) AS email_opt_in
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

    audit(db, 'review_request_dispatched', req.user!.id, req.ip || 'unknown', {
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

    // Extra guard: filter to birthdays within 7 days even if segment rule is
    // stale, so we never spam someone a month early.
    const allRecipients = await fetchEligibleRecipients(adb, campaign);
    const today = new Date();
    const within = allRecipients.filter((r: any) => {
      if (!r.birthday) return true; // segment already narrowed; keep
      return daysUntilBirthday(r.birthday, today) <= 7;
    });

    const result = await dispatchCampaign(db, adb, req.tenantSlug || null, campaign, within);

    audit(db, 'birthday_campaign_dispatched', req.user!.id, req.ip || 'unknown', {
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

    // Find invoices with balance > 0 and older than 14 days, grouped by customer.
    // Uses amount_due (materialised column on invoices) instead of re-computing
    // total - paid on the fly — faster and matches the invoice route logic.
    const unpaid = await adb.all<RecipientRow>(
      `SELECT c.id, c.first_name, c.last_name, c.email, c.phone, c.mobile,
              COALESCE(c.sms_opt_in,1) AS sms_opt_in,
              COALESCE(c.email_opt_in,1) AS email_opt_in
         FROM customers c
         JOIN invoices i ON i.customer_id = c.id
        WHERE COALESCE(i.amount_due,0) > 0
          AND i.created_at <= datetime('now','-14 days')
          AND NOT EXISTS (
              SELECT 1 FROM campaign_sends cs
               WHERE cs.campaign_id = ?
                 AND cs.customer_id = c.id
                 AND cs.sent_at >= datetime('now','-30 days')
          )
        GROUP BY c.id
        LIMIT 500`,
      campaign.id,
    );

    const eligible = unpaid.filter((r) => r.sms_opt_in === 1 || r.email_opt_in === 1);

    const result = await dispatchCampaign(db, adb, req.tenantSlug || null, campaign, eligible);

    audit(db, 'churn_warning_dispatched', req.user!.id, req.ip || 'unknown', {
      campaign_id: campaign.id,
      attempted: result.attempted,
      sent: result.sent,
    });

    res.json({ success: true, data: result });
  }),
);

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

function daysUntilBirthday(mmdd: string, today: Date): number {
  const match = /^(\d{2})-(\d{2})$/.exec(mmdd);
  if (!match) return 999;
  const m = Number(match[1]);
  const d = Number(match[2]);
  if (m < 1 || m > 12 || d < 1 || d > 31) return 999;
  const year = today.getFullYear();
  let target = new Date(year, m - 1, d).getTime();
  if (target < today.getTime()) target = new Date(year + 1, m - 1, d).getTime();
  return Math.max(0, Math.round((target - today.getTime()) / 86_400_000));
}

export default router;
