import path from 'path';
import { Router, Request, Response } from 'express';
import { config } from '../config.js';
import { db as defaultDb } from '../db/connection.js';
import { getMasterDb } from '../db/master-connection.js';
import { createAsyncDb } from '../db/async-db.js';
import { getTenantDb, releaseTenantDb } from '../db/tenant-pool.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validatePositiveAmount, validateIntegerQuantity } from '../utils/validate.js';
import {
  createTenantStripePaymentIntent,
  handleTenantStripeEvent,
  isTenantStripeEnabled,
  verifyTenantStripeWebhook,
} from '../services/tenantStripe.js';

const router = Router();

const SLUG_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;
const IDEMPOTENCY_RE = /^[A-Za-z0-9._:-]{8,180}$/;

function dollarsToCents(value: unknown): number {
  const dollars = validatePositiveAmount(value, 'amount');
  return Math.round(Number(dollars.toFixed(2)) * 100);
}

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required for Stripe payments', 403);
  }
}

router.get('/status', asyncHandler(async (req: Request, res: Response) => {
  res.json({ success: true, data: { enabled: isTenantStripeEnabled(req.db) } });
}));

router.post('/payment-intents', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);

  const adb = req.asyncDb;
  const amountCents = dollarsToCents(req.body?.amount);
  const invoiceId = req.body?.invoice_id != null && req.body.invoice_id !== ''
    ? validateIntegerQuantity(req.body.invoice_id, 'invoice_id')
    : null;
  let customerId = req.body?.customer_id != null && req.body.customer_id !== ''
    ? validateIntegerQuantity(req.body.customer_id, 'customer_id')
    : null;
  const idempotencyKey = typeof req.body?.idempotency_key === 'string'
    ? req.body.idempotency_key.trim()
    : '';
  if (idempotencyKey && !IDEMPOTENCY_RE.test(idempotencyKey)) {
    throw new AppError('idempotency_key must be 8-180 URL-safe characters', 400);
  }

  if (invoiceId) {
    const invoice = await adb.get<{ id: number; customer_id: number | null; amount_due: number; status: string }>(
      'SELECT id, customer_id, amount_due, status FROM invoices WHERE id = ?',
      invoiceId,
    );
    if (!invoice) throw new AppError('Invoice not found', 404);
    if (invoice.status === 'void' || invoice.status === 'paid') {
      throw new AppError(`Cannot create Stripe payment for a ${invoice.status} invoice`, 400);
    }
    if (customerId && invoice.customer_id != null && invoice.customer_id !== customerId) {
      throw new AppError('customer_id does not match invoice.customer_id', 400);
    }
    if (!customerId && invoice.customer_id != null) {
      customerId = invoice.customer_id;
    }
    const dueCents = Math.round(Number(invoice.amount_due ?? 0) * 100);
    if (amountCents > dueCents) {
      throw new AppError('Stripe payment amount exceeds invoice balance due', 400);
    }
  }

  const result = await createTenantStripePaymentIntent(req.db, {
    amountCents,
    invoiceId,
    customerId,
    source: invoiceId ? 'invoice' : 'pos',
    createdByUserId: req.user?.id ?? null,
    idempotencyKey: idempotencyKey || null,
  });

  res.status(201).json({ success: true, data: result });
}));

export async function tenantStripeWebhookHandler(req: Request, res: Response): Promise<void> {
  const slug = String(req.params.slug ?? '').trim().toLowerCase();
  const sig = req.headers['stripe-signature'];
  if (!SLUG_RE.test(slug)) {
    res.status(400).send('Invalid tenant slug');
    return;
  }
  if (typeof sig !== 'string' || !sig) {
    res.status(400).send('Missing stripe-signature header');
    return;
  }

  let tenantDb = defaultDb;
  let releaseSlug: string | null = null;

  try {
    if (config.multiTenant) {
      const masterDb = getMasterDb();
      if (!masterDb) {
        res.status(500).send('Tenant lookup unavailable');
        return;
      }
      const tenant = masterDb
        .prepare("SELECT id, slug FROM tenants WHERE slug = ? AND status = 'active'")
        .get(slug) as { id: number; slug: string } | undefined;
      if (!tenant) {
        res.status(404).send('Tenant not found');
        return;
      }
      tenantDb = await getTenantDb(tenant.slug);
      releaseSlug = tenant.slug;
      const tenantDbPath = path.join(
        config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'),
        `${tenant.slug}.db`,
      );
      req.db = tenantDb;
      req.asyncDb = createAsyncDb(tenantDbPath);
      req.tenantSlug = tenant.slug;
      req.tenantId = tenant.id;
    } else {
      req.db = defaultDb;
      req.tenantSlug = slug;
      req.tenantId = undefined;
    }

    const event = verifyTenantStripeWebhook(tenantDb, req.body, sig);
    const result = handleTenantStripeEvent(tenantDb, req.tenantSlug ?? slug, event);
    res.json({ received: true, result });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(err instanceof AppError ? err.statusCode : 400).send(message || 'Stripe webhook failed');
  } finally {
    if (releaseSlug) releaseTenantDb(releaseSlug);
  }
}

export default router;
