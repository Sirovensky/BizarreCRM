/**
 * tenantExport.routes.ts — SEC-H59 / P3-PII-16
 *
 * Full tenant data export for GDPR / CCPA data portability.
 *
 * Endpoints:
 *
 *   POST /api/v1/tenant/export
 *     Admin-only + step-up TOTP. Body: { passphrase: string (≥12 chars) }.
 *     Enqueues an async export job; returns { jobId }.
 *
 *   GET /api/v1/tenant/export/:jobId
 *     Admin-only. Returns the job record (status, error, byte_size) without
 *     the download token — the token is only returned via the download URL
 *     shape so it cannot leak in polling responses.
 *     When status === 'complete', also returns { downloadUrl } which is
 *     the signed single-use download path.
 *
 *   GET /api/v1/tenant/export/download/:signedToken
 *     Public (no auth — the token IS the credential). Streams the encrypted
 *     .enc file. Enforces single-use (stamps downloaded_at) and expiry.
 *     Sets Content-Type: application/octet-stream and a safe filename.
 *
 * Security:
 *   - POST requires admin role AND step-up TOTP (requireStepUpTotp).
 *   - GET /:jobId requires admin role; tenant_id scope enforced.
 *   - GET /download/:token requires only the token (opaque 64-char hex).
 *   - Passphrase validated ≥12 chars via Zod; never stored, never logged.
 *   - Rate limit: 1 export per tenant per hour (enforced in service layer).
 *   - Download token: 32 random bytes, 1-hour expiry, single-use.
 */

import { Router, type Request, type Response, type NextFunction } from 'express';
import { z } from 'zod';
import fs from 'node:fs';
import path from 'node:path';
import { AppError } from '../middleware/errorHandler.js';
import { requireStepUpTotp } from '../middleware/stepUpTotp.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { config } from '../config.js';
import {
  startExport,
  getExportJob,
  lookupDownloadToken,
  consumeDownloadToken,
  RateLimitError,
} from '../services/tenantExport.js';

const logger = createLogger('tenant-export-routes');
const router = Router();

// ─── Constants ────────────────────────────────────────────────────────────────

/** Base directory for all tenant export files. */
function getExportsDir(): string {
  return path.resolve(config.uploadsPath, '..', 'data', 'exports');
}

// ─── Validation ───────────────────────────────────────────────────────────────

const ExportRequestSchema = z.object({
  passphrase: z
    .string()
    .min(12, 'Passphrase must be at least 12 characters')
    .max(1024, 'Passphrase too long'),
});

// ─── Middleware ───────────────────────────────────────────────────────────────

function adminOnly(req: Request, _res: Response, next: NextFunction): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403);
  }
  next();
}

/**
 * Safely format a filename token from a tenant slug or job id.
 * Collapses anything outside [a-z0-9-_] to '-' so the result is safe inside
 * a Content-Disposition header without quoting edge cases.
 */
function safeFilenameToken(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9\-_]+/g, '-')
    .slice(0, 64) || 'export';
}

// ─── POST /api/v1/tenant/export ───────────────────────────────────────────────

router.post(
  '/',
  adminOnly,
  requireStepUpTotp('POST /tenant/export'),
  (req: Request, res: Response): void => {
    const parseResult = ExportRequestSchema.safeParse(req.body);
    if (!parseResult.success) {
      throw new AppError(
        parseResult.error.errors.map((e) => e.message).join('; '),
        400,
      );
    }

    const { passphrase } = parseResult.data;
    const db = req.db;
    const userId = req.user!.id;
    const tenantId = (req.tenantId as number | undefined) ?? 0;
    const tenantSlug = req.tenantSlug ?? 'single-tenant';
    const ip = req.ip || req.socket.remoteAddress || 'unknown';

    // Uploads directory for this tenant (may be slug-scoped in multi-tenant).
    const uploadsDir = tenantSlug && tenantSlug !== 'single-tenant'
      ? path.join(config.uploadsPath, tenantSlug)
      : config.uploadsPath;

    let result: { jobId: number };
    try {
      result = startExport(db, tenantId, userId, passphrase, getExportsDir(), uploadsDir);
    } catch (err) {
      if (err instanceof RateLimitError) {
        res.status(429).json({
          success: false,
          message: err.message,
        });
        return;
      }
      throw err;
    }

    // Audit: record that an export was requested. We do NOT log the passphrase.
    audit(db, 'tenant_export_requested', userId, ip, {
      jobId: result.jobId,
      tenantSlug,
    });

    logger.info('tenant export job started', {
      jobId: result.jobId,
      tenantId,
      userId,
    });

    res.status(202).json({
      success: true,
      data: {
        jobId: result.jobId,
        message: 'Export job started. Poll GET /api/v1/tenant/export/:jobId for status.',
      },
    });
  },
);

// ─── GET /api/v1/tenant/export/download/:signedToken ─────────────────────────
// Declared BEFORE /:jobId so Express matches /download/:token first.

router.get(
  '/download/:signedToken',
  (req: Request, res: Response): void => {
    const signedToken = String(req.params['signedToken'] ?? '');

    // Validate token format: exactly 64 hex chars.
    if (!/^[0-9a-f]{64}$/.test(signedToken)) {
      throw new AppError('Invalid download token', 400);
    }

    const db = req.db;
    const job = lookupDownloadToken(db, signedToken);

    if (!job) {
      // Don't distinguish between expired, used, or nonexistent — all look the
      // same to the caller so there is no oracle to enumerate valid tokens.
      throw new AppError('Download token is invalid, expired, or already used', 410);
    }

    if (!job.file_path) {
      throw new AppError('Export file path not recorded — contact support', 500);
    }

    // Verify the file exists before marking the token consumed.
    if (!fs.existsSync(job.file_path)) {
      logger.error('tenant export: file missing for complete job', {
        jobId: job.id,
        filePath: job.file_path,
      });
      throw new AppError('Export file not found — it may have expired', 410);
    }

    // Mark token consumed BEFORE streaming so a concurrent request racing
    // on the same token gets a 410 rather than a second download.
    consumeDownloadToken(db, job.id);

    // Derive a safe filename from the job id and date.
    const dateToken = new Date(job.started_at).toISOString().slice(0, 10);
    const slugToken = safeFilenameToken(
      (req.tenantSlug ?? 'tenant') + '-' + String(job.id)
    );
    const filename = `bizarre-crm-export-${slugToken}-${dateToken}.enc`;

    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');

    const fileSize = fs.statSync(job.file_path).size;
    res.setHeader('Content-Length', String(fileSize));

    const stream = fs.createReadStream(job.file_path);

    stream.on('error', (err) => {
      logger.error('tenant export: stream error', {
        jobId: job.id,
        error: err.message,
      });
      // Headers already sent — nothing we can do except end the response.
      if (!res.writableEnded) res.end();
    });

    stream.pipe(res);

    logger.info('tenant export: download streamed', { jobId: job.id });
  },
);

// ─── GET /api/v1/tenant/export/:jobId ────────────────────────────────────────

router.get(
  '/:jobId',
  adminOnly,
  (req: Request, res: Response): void => {
    const jobIdRaw = Number(req.params['jobId'] ?? '');
    if (!Number.isInteger(jobIdRaw) || jobIdRaw < 1) {
      throw new AppError('Invalid job id', 400);
    }

    const db = req.db;
    const tenantId = (req.tenantId as number | undefined) ?? 0;

    const job = getExportJob(db, jobIdRaw, tenantId);
    if (!job) {
      throw new AppError('Export job not found', 404);
    }

    // Build the response — expose job metadata but NOT the raw download_token
    // (the download URL is the transport for that credential).
    const downloadUrl =
      job.status === 'complete' && job.download_token && !job.downloaded_at
        ? `/api/v1/tenant/export/download/${job.download_token}`
        : null;

    res.json({
      success: true,
      data: {
        id: job.id,
        status: job.status,
        started_at: job.started_at,
        completed_at: job.completed_at,
        byte_size: job.byte_size,
        error_message: job.error_message,
        download_url: downloadUrl,
        // Expose expiry so the UI can show a countdown / warn before it expires.
        download_token_expires_at: job.download_token_expires_at,
        // Whether the download has already been claimed.
        downloaded_at: job.downloaded_at,
      },
    });
  },
);

export default router;
