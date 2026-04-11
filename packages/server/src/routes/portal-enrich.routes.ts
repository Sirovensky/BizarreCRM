/**
 * Portal Enrichment Routes — mounted at `/portal/api/v2/`
 *
 * NEW routes for the customer portal enrichment described in
 * criticalaudit.md §45. Stays out of portal.routes.ts (owned by the prior
 * agent) by living in its own file and its own URL namespace.
 *
 * Auth: all routes use the same portal-session cookie/header as v1, decoded
 * here locally to avoid a hard import from portal.routes.ts.
 *
 * Response shape: every endpoint returns `{ success: true, data: X }`.
 */
import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import { qs } from '../utils/query.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();
const logger = createLogger('portal-enrich');

type AnyRow = Record<string, any>;

interface PortalRequest extends Request {
  portalCustomerId?: number;
  portalScope?: 'ticket' | 'full';
  portalTicketId?: number | null;
}

// ---------------------------------------------------------------------------
// Auth — mirrors portal.routes.ts. Accepts the same portal_sessions token
// from Authorization: Bearer <token> or the portalToken cookie. Never from
// query string.
// ---------------------------------------------------------------------------

async function portalAuth(
  req: PortalRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const adb = req.asyncDb;
  const authHeader = req.headers.authorization;
  const cookieToken = req.cookies?.portalToken as string | undefined;
  const token = authHeader?.startsWith('Bearer ')
    ? authHeader.slice(7)
    : cookieToken;

  if (!token) {
    res.status(401).json({ success: false, message: 'Authentication required' });
    return;
  }

  const session = await adb.get<AnyRow>(
    `SELECT customer_id, scope, ticket_id, token
       FROM portal_sessions
      WHERE token = ? AND expires_at > datetime('now')`,
    token,
  );

  if (!session) {
    res.status(401).json({ success: false, message: 'Session expired or invalid' });
    return;
  }

  req.portalCustomerId = session.customer_id;
  req.portalScope = session.scope as 'ticket' | 'full';
  req.portalTicketId = session.ticket_id;
  next();
}

/** Ticket-scope session may only read the ticket it was issued for. */
function requireTicketScopeMatches(
  req: PortalRequest,
  res: Response,
  next: NextFunction,
): void {
  if (req.portalScope === 'ticket') {
    const ticketId = parseInt(req.params.id as string, 10);
    if (isNaN(ticketId)) {
      res.status(400).json({ success: false, message: 'Invalid ticket ID' });
      return;
    }
    if (req.portalTicketId !== ticketId) {
      res.status(403).json({
        success: false,
        message: 'Access restricted to your tracked ticket',
      });
      return;
    }
  }
  next();
}

/** Customer-scoped endpoints — only full-scope sessions may read. */
function requireCustomerScopeMatches(
  req: PortalRequest,
  res: Response,
  next: NextFunction,
): void {
  const customerId = parseInt(req.params.id as string, 10);
  if (isNaN(customerId)) {
    res.status(400).json({ success: false, message: 'Invalid customer ID' });
    return;
  }
  if (req.portalCustomerId !== customerId) {
    res.status(403).json({ success: false, message: 'Access denied' });
    return;
  }
  next();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function getConfig(
  adb: AsyncDb,
  keys: readonly string[],
): Promise<Record<string, string>> {
  if (keys.length === 0) return {};
  const placeholders = keys.map(() => '?').join(',');
  const rows = await adb.all<AnyRow>(
    `SELECT key, value FROM store_config WHERE key IN (${placeholders})`,
    ...keys,
  );
  const out: Record<string, string> = {};
  for (const r of rows) out[r.key] = r.value;
  return out;
}

function safeInt(value: string | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

function escapeHtml(input: string): string {
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function generateCertificateNumber(): string {
  const hex = crypto.randomBytes(4).toString('hex').toUpperCase();
  const year = new Date().getUTCFullYear();
  return `WR-${year}-${hex}`;
}

function generateReferralCode(): string {
  return crypto.randomBytes(3).toString('hex').toUpperCase();
}

// ---------------------------------------------------------------------------
// GET /portal/api/v2/ticket/:id/timeline
// Ordered status-change history from ticket_history.
// ---------------------------------------------------------------------------
router.get(
  '/ticket/:id/timeline',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const ticket = await adb.get<AnyRow>(
      `SELECT id, customer_id, created_at FROM tickets WHERE id = ? AND is_deleted = 0`,
      ticketId,
    );
    if (!ticket) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }

    // Full-scope session must own the ticket's customer.
    if (req.portalScope === 'full' && ticket.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }

    const history = await adb.all<AnyRow>(
      `SELECT action, description, old_value, new_value, created_at
         FROM ticket_history
        WHERE ticket_id = ?
          AND action IN ('status_change', 'status_changed', 'created', 'parts_ordered', 'parts_arrived', 'completed', 'ready_for_pickup')
        ORDER BY created_at ASC`,
      ticketId,
    );

    // Seed with the check-in event if nothing else exists.
    const events = history.length
      ? history.map((h) => ({
          action: h.action,
          label: h.description || h.new_value || 'Status updated',
          from: h.old_value,
          to: h.new_value,
          at: h.created_at,
        }))
      : [
          {
            action: 'created',
            label: 'Checked in',
            from: null,
            to: null,
            at: ticket.created_at,
          },
        ];

    res.json({ success: true, data: { events } });
  }),
);

// ---------------------------------------------------------------------------
// GET /portal/api/v2/ticket/:id/queue-position
// Respects portal_queue_mode: 'none' | 'phones' | 'all'.
// ---------------------------------------------------------------------------
router.get(
  '/ticket/:id/queue-position',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const config = await getConfig(adb, ['portal_queue_mode']);
    const mode = (config.portal_queue_mode || 'phones').toLowerCase();

    if (mode === 'none') {
      res.json({ success: true, data: { enabled: false, reason: 'disabled' } });
      return;
    }

    const ticket = await adb.get<AnyRow>(
      `SELECT t.id, t.customer_id, t.status_id, t.created_at, ts.is_closed
         FROM tickets t
         LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.id = ? AND t.is_deleted = 0`,
      ticketId,
    );
    if (!ticket) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }
    if (req.portalScope === 'full' && ticket.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }
    if (ticket.is_closed) {
      res.json({ success: true, data: { enabled: true, position: 0, closed: true } });
      return;
    }

    // Check if this ticket has any phone devices
    const devices = await adb.all<AnyRow>(
      `SELECT device_type FROM ticket_devices WHERE ticket_id = ?`,
      ticketId,
    );
    const hasPhone = devices.some((d) =>
      (d.device_type || '').toLowerCase().includes('phone'),
    );

    if (mode === 'phones' && !hasPhone) {
      res.json({ success: true, data: { enabled: false, reason: 'phones_only' } });
      return;
    }

    // Queue position = number of open tickets created before this one.
    const filterClause =
      mode === 'phones'
        ? `AND EXISTS (SELECT 1 FROM ticket_devices td
                         WHERE td.ticket_id = t.id
                           AND LOWER(COALESCE(td.device_type, '')) LIKE '%phone%')`
        : '';

    const ahead = await adb.get<AnyRow>(
      `SELECT COUNT(*) AS n
         FROM tickets t
         LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.is_deleted = 0
          AND COALESCE(ts.is_closed, 0) = 0
          AND t.created_at < ?
          ${filterClause}`,
      ticket.created_at,
    );

    const position = (ahead?.n ?? 0) + 1;
    // Simple heuristic: 1h per ticket ahead.
    const etaHours = Math.max(1, position);

    res.json({
      success: true,
      data: {
        enabled: true,
        mode,
        position,
        eta_hours_min: etaHours,
        eta_hours_max: etaHours + 1,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /portal/api/v2/ticket/:id/tech
// Returns the assigned tech's display name + optional avatar. Respects
// the global portal_show_tech toggle AND the per-user portal_tech_visible
// opt-in.
// ---------------------------------------------------------------------------
router.get(
  '/ticket/:id/tech',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const config = await getConfig(adb, ['portal_show_tech']);
    const showTech = (config.portal_show_tech || 'true') === 'true';
    if (!showTech) {
      res.json({ success: true, data: { visible: false, reason: 'disabled' } });
      return;
    }

    const row = await adb.get<AnyRow>(
      `SELECT u.first_name, u.avatar_url, u.portal_tech_visible, t.customer_id
         FROM tickets t
         LEFT JOIN users u ON u.id = t.assigned_to
        WHERE t.id = ? AND t.is_deleted = 0`,
      ticketId,
    );
    if (!row) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }
    if (req.portalScope === 'full' && row.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }

    if (!row.first_name || row.portal_tech_visible !== 1) {
      res.json({ success: true, data: { visible: false, reason: 'no_consent' } });
      return;
    }

    res.json({
      success: true,
      data: {
        visible: true,
        first_name: row.first_name,
        avatar_url: row.avatar_url || null,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /portal/api/v2/ticket/:id/photos
// Returns only photos with customer_visible = 1. Includes a deletable flag
// so the frontend can show remove buttons on "after" photos inside the
// configured delete window.
// ---------------------------------------------------------------------------
router.get(
  '/ticket/:id/photos',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const ticket = await adb.get<AnyRow>(
      `SELECT customer_id FROM tickets WHERE id = ? AND is_deleted = 0`,
      ticketId,
    );
    if (!ticket) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }
    if (req.portalScope === 'full' && ticket.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }

    const config = await getConfig(adb, ['portal_after_photo_delete_hours']);
    const windowHours = safeInt(config.portal_after_photo_delete_hours, 24);

    const rows = await adb.all<AnyRow>(
      `SELECT photo_path, is_before, uploaded_at
         FROM ticket_photos_visibility
        WHERE ticket_id = ? AND customer_visible = 1
        ORDER BY is_before DESC, uploaded_at ASC`,
      ticketId,
    );

    const now = Date.now();
    const photos = rows.map((r) => {
      const uploadedAt = new Date(r.uploaded_at + 'Z').getTime();
      const ageHours = (now - uploadedAt) / (1000 * 60 * 60);
      const deletable =
        !r.is_before && windowHours > 0 && ageHours >= 0 && ageHours <= windowHours;
      return {
        path: r.photo_path,
        is_before: r.is_before === 1,
        uploaded_at: r.uploaded_at,
        deletable,
      };
    });

    res.json({
      success: true,
      data: {
        photos,
        delete_window_hours: windowHours,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /portal/api/v2/ticket/:id/photos/:path
// Customer removes an "after" photo inside the delete window. Flips
// customer_visible to 0 (audit-safe soft hide) rather than dropping the row.
// ---------------------------------------------------------------------------
router.delete(
  '/ticket/:id/photos',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const photoPath = (req.body?.photo_path || '').toString();
    if (!photoPath) {
      res.status(400).json({ success: false, message: 'photo_path required' });
      return;
    }

    const adb = req.asyncDb;
    const config = await getConfig(adb, ['portal_after_photo_delete_hours']);
    const windowHours = safeInt(config.portal_after_photo_delete_hours, 24);

    if (windowHours <= 0) {
      res.status(403).json({ success: false, message: 'Deletion disabled' });
      return;
    }

    const row = await adb.get<AnyRow>(
      `SELECT is_before, uploaded_at
         FROM ticket_photos_visibility
        WHERE ticket_id = ? AND photo_path = ? AND customer_visible = 1`,
      ticketId,
      photoPath,
    );
    if (!row) {
      res.status(404).json({ success: false, message: 'Photo not found' });
      return;
    }
    if (row.is_before === 1) {
      res.status(403).json({ success: false, message: 'Before photos cannot be removed' });
      return;
    }

    const ageHours =
      (Date.now() - new Date(row.uploaded_at + 'Z').getTime()) / (1000 * 60 * 60);
    if (ageHours > windowHours) {
      res.status(403).json({ success: false, message: 'Delete window has closed' });
      return;
    }

    await adb.run(
      `UPDATE ticket_photos_visibility
          SET customer_visible = 0
        WHERE ticket_id = ? AND photo_path = ?`,
      ticketId,
      photoPath,
    );

    logger.info('portal customer hid after-photo', { ticket_id: ticketId });
    res.json({ success: true, data: { hidden: true } });
  }),
);

// ---------------------------------------------------------------------------
// GET /portal/api/v2/ticket/:id/receipt.pdf
// GET /portal/api/v2/ticket/:id/warranty.pdf
// pdfkit/puppeteer are not installed — serve print-friendly HTML with
// Content-Type: text/html. Browsers can "Save as PDF" from print dialog.
// ---------------------------------------------------------------------------
router.get(
  '/ticket/:id/receipt.pdf',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const ticket = await adb.get<AnyRow>(
      `SELECT t.id, t.order_id, t.created_at, t.subtotal, t.discount,
              t.total_tax, t.total, t.customer_id, t.invoice_id,
              c.first_name, c.last_name, c.email, c.phone
         FROM tickets t
         LEFT JOIN customers c ON c.id = t.customer_id
        WHERE t.id = ? AND t.is_deleted = 0`,
      ticketId,
    );
    if (!ticket) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }
    if (req.portalScope === 'full' && ticket.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }

    const config = await getConfig(adb, [
      'store_name',
      'store_phone',
      'store_address',
      'store_city',
      'store_state',
      'store_zip',
    ]);

    const html = renderReceiptHtml(ticket, config);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="receipt-${ticket.order_id || ticketId}.html"`,
    );
    res.status(200).send(html);
  }),
);

router.get(
  '/ticket/:id/warranty.pdf',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const ticket = await adb.get<AnyRow>(
      `SELECT t.id, t.order_id, t.customer_id, t.created_at,
              c.first_name, c.last_name,
              ts.is_closed
         FROM tickets t
         LEFT JOIN customers c ON c.id = t.customer_id
         LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.id = ? AND t.is_deleted = 0`,
      ticketId,
    );
    if (!ticket) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }
    if (req.portalScope === 'full' && ticket.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }

    const config = await getConfig(adb, [
      'store_name',
      'store_phone',
      'store_address',
      'portal_warranty_default_days',
    ]);

    // Get-or-create the warranty certificate record (append-only).
    let cert = await adb.get<AnyRow>(
      `SELECT * FROM warranty_certificates WHERE ticket_id = ?`,
      ticketId,
    );
    if (!cert) {
      const warrantyDays = safeInt(config.portal_warranty_default_days, 90);
      const endDate = new Date();
      endDate.setUTCDate(endDate.getUTCDate() + warrantyDays);
      const certNumber = generateCertificateNumber();
      await adb.run(
        `INSERT INTO warranty_certificates
            (ticket_id, certificate_number, warranty_days, warranty_end_date)
          VALUES (?, ?, ?, ?)`,
        ticketId,
        certNumber,
        warrantyDays,
        endDate.toISOString().slice(0, 10),
      );
      cert = await adb.get<AnyRow>(
        `SELECT * FROM warranty_certificates WHERE ticket_id = ?`,
        ticketId,
      );
    }
    if (!cert) {
      res.status(500).json({ success: false, message: 'Failed to load warranty certificate' });
      return;
    }

    const html = renderWarrantyHtml(ticket, cert, config);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="warranty-${cert!.certificate_number}.html"`,
    );
    res.status(200).send(html);
  }),
);

// ---------------------------------------------------------------------------
// POST /portal/api/v2/ticket/:id/review
// ---------------------------------------------------------------------------
router.post(
  '/ticket/:id/review',
  portalAuth,
  requireTicketScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const ticketId = parseInt(qs(req.params.id), 10);
    const rating = parseInt(req.body?.rating, 10);
    const comment = (req.body?.comment || '').toString().slice(0, 2000);

    if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
      res.status(400).json({ success: false, message: 'rating must be 1..5' });
      return;
    }

    const adb = req.asyncDb;
    const ticket = await adb.get<AnyRow>(
      `SELECT customer_id FROM tickets WHERE id = ? AND is_deleted = 0`,
      ticketId,
    );
    if (!ticket) {
      res.status(404).json({ success: false, message: 'Ticket not found' });
      return;
    }
    if (req.portalScope === 'full' && ticket.customer_id !== req.portalCustomerId) {
      res.status(403).json({ success: false, message: 'Access denied' });
      return;
    }

    const config = await getConfig(adb, [
      'portal_review_threshold',
      'portal_google_review_url',
    ]);
    const threshold = safeInt(config.portal_review_threshold, 4);
    const googleUrl = config.portal_google_review_url || '';

    await adb.run(
      `INSERT INTO customer_reviews (ticket_id, customer_id, rating, comment)
          VALUES (?, ?, ?, ?)`,
      ticketId,
      ticket.customer_id,
      rating,
      comment || null,
    );

    logger.info('portal review submitted', { ticket_id: ticketId, rating });

    const forwardToPublic = rating >= threshold && googleUrl.length > 0;
    res.json({
      success: true,
      data: {
        stored: true,
        forward_url: forwardToPublic ? googleUrl : null,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /portal/api/v2/customer/:id/loyalty
// Returns points balance + recent transactions.
// ---------------------------------------------------------------------------
router.get(
  '/customer/:id/loyalty',
  portalAuth,
  requireCustomerScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    if (req.portalScope !== 'full') {
      res.status(403).json({ success: false, message: 'Full account required' });
      return;
    }
    const customerId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    const config = await getConfig(adb, [
      'portal_loyalty_enabled',
      'portal_loyalty_rate',
    ]);
    const enabled = (config.portal_loyalty_enabled || 'true') === 'true';
    if (!enabled) {
      res.json({ success: true, data: { enabled: false, points: 0, history: [] } });
      return;
    }

    const row = await adb.get<AnyRow>(
      `SELECT COALESCE(SUM(points), 0) AS balance
         FROM loyalty_points WHERE customer_id = ?`,
      customerId,
    );
    const history = await adb.all<AnyRow>(
      `SELECT points, reason, reference_type, created_at
         FROM loyalty_points
        WHERE customer_id = ?
        ORDER BY created_at DESC
        LIMIT 20`,
      customerId,
    );

    res.json({
      success: true,
      data: {
        enabled: true,
        points: row?.balance ?? 0,
        rate_per_dollar: safeInt(config.portal_loyalty_rate, 1),
        history,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /portal/api/v2/customer/:id/referral-code
// ---------------------------------------------------------------------------
router.post(
  '/customer/:id/referral-code',
  portalAuth,
  requireCustomerScopeMatches,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    if (req.portalScope !== 'full') {
      res.status(403).json({ success: false, message: 'Full account required' });
      return;
    }
    const customerId = parseInt(qs(req.params.id), 10);
    const adb = req.asyncDb;

    // Reuse an existing un-converted code if present.
    const existing = await adb.get<AnyRow>(
      `SELECT referral_code FROM referrals
        WHERE referrer_customer_id = ? AND converted_at IS NULL
        ORDER BY created_at DESC LIMIT 1`,
      customerId,
    );
    if (existing) {
      res.json({ success: true, data: { code: existing.referral_code, created: false } });
      return;
    }

    // Generate a unique code (retry up to 5 times on collision).
    let code = '';
    for (let i = 0; i < 5; i++) {
      const candidate = generateReferralCode();
      const taken = await adb.get<AnyRow>(
        `SELECT id FROM referrals WHERE referral_code = ?`,
        candidate,
      );
      if (!taken) {
        code = candidate;
        break;
      }
    }
    if (!code) {
      res.status(500).json({ success: false, message: 'Could not generate code' });
      return;
    }

    await adb.run(
      `INSERT INTO referrals (referrer_customer_id, referral_code) VALUES (?, ?)`,
      customerId,
      code,
    );
    logger.info('portal referral code issued', { customer_id: customerId });

    res.json({ success: true, data: { code, created: true } });
  }),
);

// ---------------------------------------------------------------------------
// GET /portal/api/v2/config — switchable portal features for the UI.
// Public to any authenticated portal session so the frontend can render
// the SLA banner, FAQ tooltips, queue mode etc. consistently.
// ---------------------------------------------------------------------------
router.get(
  '/config',
  portalAuth,
  asyncHandler(async (req: PortalRequest, res: Response) => {
    const adb = req.asyncDb;
    const config = await getConfig(adb, [
      'portal_queue_mode',
      'portal_show_tech',
      'portal_sla_enabled',
      'portal_sla_message',
      'portal_loyalty_enabled',
      'portal_loyalty_rate',
      'portal_referral_reward',
      'portal_review_threshold',
      'portal_google_review_url',
      'portal_after_photo_delete_hours',
      'store_name',
      'store_phone',
      'store_address',
      'store_city',
      'store_state',
      'store_zip',
      'store_hours',
      'store_website',
    ]);
    res.json({ success: true, data: config });
  }),
);

// ---------------------------------------------------------------------------
// HTML templates — printed/saved by browser in lieu of PDF.
// ---------------------------------------------------------------------------

function renderReceiptHtml(
  ticket: AnyRow,
  config: Record<string, string>,
): string {
  const store = escapeHtml(config.store_name || 'Repair Shop');
  const addr = escapeHtml(
    [config.store_address, config.store_city, config.store_state, config.store_zip]
      .filter(Boolean)
      .join(', '),
  );
  const phone = escapeHtml(config.store_phone || '');
  const customerName = escapeHtml(
    `${ticket.first_name || ''} ${ticket.last_name || ''}`.trim() || 'Customer',
  );
  const money = (n: any) => `$${Number(n || 0).toFixed(2)}`;
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Receipt ${escapeHtml(ticket.order_id || '')}</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 600px; margin: 2rem auto; padding: 2rem; color: #111; }
  h1 { font-size: 1.5rem; margin: 0 0 .25rem; }
  .muted { color: #666; font-size: .9rem; }
  table { width: 100%; border-collapse: collapse; margin: 1.5rem 0; }
  td { padding: .5rem 0; }
  tr.total td { font-weight: bold; border-top: 2px solid #111; padding-top: .75rem; }
  .footer { margin-top: 2rem; text-align: center; color: #888; font-size: .8rem; }
  @media print { body { margin: 0; } }
</style></head>
<body>
  <h1>${store}</h1>
  <div class="muted">${addr}<br>${phone}</div>
  <hr style="margin: 1.5rem 0; border: none; border-top: 1px solid #ddd;">
  <div><strong>Receipt</strong> — Ticket ${escapeHtml(ticket.order_id || `#${ticket.id}`)}</div>
  <div class="muted">Customer: ${customerName}</div>
  <div class="muted">Date: ${escapeHtml(ticket.created_at || '')}</div>
  <table>
    <tr><td>Subtotal</td><td style="text-align: right;">${money(ticket.subtotal)}</td></tr>
    <tr><td>Discount</td><td style="text-align: right;">-${money(ticket.discount)}</td></tr>
    <tr><td>Tax</td><td style="text-align: right;">${money(ticket.total_tax)}</td></tr>
    <tr class="total"><td>Total</td><td style="text-align: right;">${money(ticket.total)}</td></tr>
  </table>
  <div class="footer">Thank you for your business. Use your browser's print dialog to save as PDF.</div>
</body></html>`;
}

function renderWarrantyHtml(
  ticket: AnyRow,
  cert: AnyRow,
  config: Record<string, string>,
): string {
  const store = escapeHtml(config.store_name || 'Repair Shop');
  const customerName = escapeHtml(
    `${ticket.first_name || ''} ${ticket.last_name || ''}`.trim() || 'Customer',
  );
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Warranty ${escapeHtml(cert.certificate_number)}</title>
<style>
  body { font-family: Georgia, serif; max-width: 700px; margin: 2rem auto; padding: 3rem; color: #111; border: 4px double #3b82f6; }
  h1 { text-align: center; font-size: 2rem; letter-spacing: .1em; margin: 0; }
  h2 { text-align: center; color: #3b82f6; font-size: 1.1rem; font-weight: normal; margin: .5rem 0 2rem; }
  .body { text-align: center; font-size: 1.05rem; line-height: 1.7; }
  .number { font-family: monospace; font-size: 1.2rem; margin-top: 2rem; text-align: center; color: #666; }
  ul { text-align: left; margin: 2rem auto; max-width: 450px; }
  @media print { body { border: 4px double #000; } }
</style></head>
<body>
  <h1>WARRANTY</h1>
  <h2>Certificate of Repair</h2>
  <div class="body">
    <p>This certifies that <strong>${customerName}</strong>'s device was repaired at <strong>${store}</strong> on ${escapeHtml(ticket.created_at || '')}, and is covered under the following warranty terms.</p>
    <ul>
      <li>Coverage period: <strong>${cert.warranty_days} days</strong> from repair date</li>
      <li>Expires: <strong>${escapeHtml(cert.warranty_end_date)}</strong></li>
      <li>Covers defects in parts and workmanship from the original repair</li>
      <li>Does not cover new physical damage, liquid damage, or unrelated failures</li>
    </ul>
    <p>Present this certificate or your ticket number for warranty service.</p>
  </div>
  <div class="number">Certificate: ${escapeHtml(cert.certificate_number)}</div>
</body></html>`;
}

export default router;
