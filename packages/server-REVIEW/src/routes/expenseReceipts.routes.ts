/**
 * Expense Receipt Upload + OCR Routes (SCAN-490, ios §11.3)
 *
 * Mount point : /api/v1/expenses/:expenseId/receipt
 * Auth        : authMiddleware applied at parent mount — do NOT re-add here.
 * Role gate   : uploader must own the expense OR be manager/admin.
 *
 * Security notes:
 *   - MIME validated by magic bytes via fileUploadValidator (F1).
 *   - Virus scan stub wired via fileUploadValidator (F2).
 *   - Per-tenant file-count quota enforced by fileUploadValidator (F4).
 *   - Pre-write byte-quota check via enforceUploadQuota.
 *   - Rate limit: 20 uploads/min per user (consumeWindowRate).
 *   - All uploads and deletes are audited.
 *   - Integer IDs validated before any SQL.
 *   - ip_address sourced from req.socket.remoteAddress (SCAN-194).
 *   - OCR is out of scope for this wave — enqueueReceiptOcr() stubs the job.
 */

import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { fileUploadValidator, releaseFileCount } from '../middleware/fileUploadValidator.js';
import { enforceUploadQuota } from '../middleware/uploadQuota.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { reserveStorage } from '../services/usageTracker.js';
import { enqueueReceiptOcr } from '../services/receiptOcr.js';
import { config } from '../config.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router({ mergeParams: true });

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const RECEIPT_RATE_CATEGORY = 'expense_receipt_upload';
const RECEIPT_RATE_MAX = 20;
const RECEIPT_RATE_WINDOW_MS = 60_000; // 20 per minute per user

const RECEIPT_MAX_BYTES = 10 * 1024 * 1024; // 10 MB

const ALLOWED_RECEIPT_MIMES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
] as const;

const ALLOWED_RECEIPT_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.heic']);

// ---------------------------------------------------------------------------
// Multer configuration
// ---------------------------------------------------------------------------

function receiptUploadDir(req: any): string {
  const tenantSlug: string | undefined = req.tenantSlug;
  return tenantSlug
    ? path.join(config.uploadsPath, tenantSlug, 'receipts')
    : path.join(config.uploadsPath, 'receipts');
}

const receiptUpload = multer({
  storage: multer.diskStorage({
    destination: (req: any, _file, cb) => {
      const dest = receiptUploadDir(req);
      try {
        if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
        cb(null, dest);
      } catch (err) {
        cb(err as Error, dest);
      }
    },
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
      if (!ext || !ALLOWED_RECEIPT_EXTENSIONS.has(ext)) {
        cb(new Error('Unsupported receipt image extension'), '');
        return;
      }
      cb(null, `${crypto.randomBytes(16).toString('hex')}${ext}`);
    },
  }),
  limits: {
    fileSize: RECEIPT_MAX_BYTES,
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    if ((ALLOWED_RECEIPT_MIMES as readonly string[]).includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only JPEG, PNG, WebP, or HEIC allowed for receipt images'));
    }
  },
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseExpenseId(raw: unknown): number {
  const id = parseInt(String(raw ?? ''), 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);
  return id;
}

function isManagerOrAdmin(req: any): boolean {
  const role = req.user?.role;
  return role === 'admin' || role === 'manager';
}

function safeUnlink(filePath: string | undefined): void {
  if (!filePath) return;
  try { fs.unlinkSync(filePath); } catch { /* best effort */ }
}

// ---------------------------------------------------------------------------
// POST / — upload a receipt image; enqueue OCR
// ---------------------------------------------------------------------------

router.post(
  '/',
  enforceUploadQuota,
  receiptUpload.single('receipt'),
  fileUploadValidator({
    allowedMimes: ALLOWED_RECEIPT_MIMES,
    getTenantDir: (r) => receiptUploadDir(r),
  }),
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const expenseId = parseExpenseId(req.params.expenseId);
    const ipAddress = req.socket?.remoteAddress ?? 'unknown';

    // Rate-limit before touching the DB.
    const rl = consumeWindowRate(
      db,
      RECEIPT_RATE_CATEGORY,
      String(userId),
      RECEIPT_RATE_MAX,
      RECEIPT_RATE_WINDOW_MS,
    );
    if (!rl.allowed) {
      const photoFile = (req as any).file as Express.Multer.File | undefined;
      if (photoFile) {
        safeUnlink(photoFile.path);
        releaseFileCount(req, 1);
      }
      throw new AppError(
        `Too many receipt uploads. Retry after ${rl.retryAfterSeconds}s.`,
        429,
      );
    }

    const photoFile = (req as any).file as Express.Multer.File | undefined;
    if (!photoFile) throw new AppError('No receipt file uploaded (field name: receipt)', 400);

    // Verify expense exists and check ownership / role.
    const expense = await adb.get<{ id: number; user_id: number }>(
      'SELECT id, user_id FROM expenses WHERE id = ?',
      expenseId,
    );
    if (!expense) {
      safeUnlink(photoFile.path);
      releaseFileCount(req, 1);
      throw new AppError('Expense not found', 404);
    }

    if (expense.user_id !== userId && !isManagerOrAdmin(req)) {
      safeUnlink(photoFile.path);
      releaseFileCount(req, 1);
      throw new AppError('You are not authorised to upload a receipt for this expense', 403);
    }

    // SEC (PROD102): reserve byte quota AFTER the ownership check (avoids
    // charging quota for unauthorised attempts).
    const bytes = photoFile.size ?? 0;
    if (
      !reserveStorage(
        (req as any).tenantId,
        bytes,
        (req as any).tenantLimits?.storageLimitMb ?? null,
      )
    ) {
      safeUnlink(photoFile.path);
      releaseFileCount(req, 1);
      res.status(403).json({
        success: false,
        upgrade_required: true,
        feature: 'storage_limit',
        message: `Storage limit (${(req as any).tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for more storage.`,
      });
      return;
    }

    // Build the public URL path.
    const tenantSlug: string | undefined = (req as any).tenantSlug;
    const filePath = tenantSlug
      ? `/uploads/${tenantSlug}/receipts/${photoFile.filename}`
      : `/uploads/receipts/${photoFile.filename}`;

    // Persist the upload record + update the parent expense in a transaction.
    const uploadId: number = db.transaction(() => {
      const insertResult = db
        .prepare(
          `INSERT INTO expense_receipt_uploads
             (expense_id, uploaded_by_user_id, file_path, mime_type,
              file_size_bytes, ocr_status)
           VALUES (?, ?, ?, ?, ?, 'pending')`,
        )
        .run(expenseId, userId, filePath, photoFile.mimetype, bytes);

      // Stamp the parent expense with the latest receipt path + upload time.
      db.prepare(
        `UPDATE expenses
            SET receipt_image_path  = ?,
                receipt_uploaded_at = datetime('now'),
                updated_at          = datetime('now')
          WHERE id = ?`,
      ).run(filePath, expenseId);

      return Number(insertResult.lastInsertRowid);
    })();

    audit(db, 'expense_receipt_uploaded', userId, ipAddress, {
      upload_id: uploadId,
      expense_id: expenseId,
      mime_type: photoFile.mimetype,
      file_size_bytes: bytes,
    });

    // Fire-and-forget OCR enqueue — never throws.
    await enqueueReceiptOcr(db, uploadId);

    const uploadRow = await adb.get(
      'SELECT * FROM expense_receipt_uploads WHERE id = ?',
      uploadId,
    );

    res.status(201).json({ success: true, data: uploadRow });
  }),
);

// ---------------------------------------------------------------------------
// GET / — return current receipt status for the expense
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const expenseId = parseExpenseId(req.params.expenseId);

    const expense = await adb.get<{ id: number; user_id: number; receipt_image_path: string | null; receipt_ocr_text: string | null; receipt_uploaded_at: string | null }>(
      `SELECT id, user_id, receipt_image_path, receipt_ocr_text, receipt_uploaded_at
         FROM expenses WHERE id = ?`,
      expenseId,
    );
    if (!expense) throw new AppError('Expense not found', 404);

    if (expense.user_id !== userId && !isManagerOrAdmin(req)) {
      throw new AppError('Not authorised to view this expense receipt', 403);
    }

    // Return the most-recent upload record alongside the denormalised expense columns.
    const upload = await adb.get(
      `SELECT id, ocr_status, ocr_text, parsed_json, error_message, mime_type,
              file_size_bytes, created_at
         FROM expense_receipt_uploads
        WHERE expense_id = ?
        ORDER BY id DESC
        LIMIT 1`,
      expenseId,
    );

    res.json({
      success: true,
      data: {
        expense_id: expenseId,
        receipt_image_path: expense.receipt_image_path,
        receipt_ocr_text: expense.receipt_ocr_text,
        receipt_uploaded_at: expense.receipt_uploaded_at,
        latest_upload: upload ?? null,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// DELETE / — delete the receipt file + upload record (owns or manager+)
// ---------------------------------------------------------------------------

router.delete(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const expenseId = parseExpenseId(req.params.expenseId);
    const ipAddress = req.socket?.remoteAddress ?? 'unknown';

    const expense = await adb.get<{ id: number; user_id: number; receipt_image_path: string | null }>(
      'SELECT id, user_id, receipt_image_path FROM expenses WHERE id = ?',
      expenseId,
    );
    if (!expense) throw new AppError('Expense not found', 404);

    if (expense.user_id !== userId && !isManagerOrAdmin(req)) {
      throw new AppError('Not authorised to delete this expense receipt', 403);
    }

    // Fetch the most-recent upload row so we can delete the file.
    const upload = await adb.get<{ id: number; file_path: string }>(
      `SELECT id, file_path
         FROM expense_receipt_uploads
        WHERE expense_id = ?
        ORDER BY id DESC
        LIMIT 1`,
      expenseId,
    );

    if (!upload && !expense.receipt_image_path) {
      throw new AppError('No receipt on record for this expense', 404);
    }

    // Resolve the on-disk path from the stored URL path.
    // Stored format: /uploads/<tenant>/receipts/<filename>
    // config.uploadsPath is the absolute path to the uploads/ directory, so
    // strip the leading "/uploads/" prefix and join from there.
    const storedPath = upload?.file_path ?? expense.receipt_image_path ?? '';
    const relPath = storedPath.replace(/^\/uploads\//, '');
    const diskPath = relPath ? path.join(config.uploadsPath, relPath) : null;

    // Delete: upload record, then clear expense columns, then unlink the file.
    db.transaction(() => {
      if (upload) {
        db.prepare('DELETE FROM expense_receipt_uploads WHERE id = ?').run(upload.id);
      }
      db.prepare(
        `UPDATE expenses
            SET receipt_image_path    = NULL,
                receipt_ocr_text      = NULL,
                receipt_ocr_parsed_json = NULL,
                receipt_uploaded_at   = NULL,
                updated_at            = datetime('now')
          WHERE id = ?`,
      ).run(expenseId);
    })();

    if (diskPath) safeUnlink(diskPath);
    if (upload) releaseFileCount(req, 1);

    audit(db, 'expense_receipt_deleted', userId, ipAddress, {
      expense_id: expenseId,
      upload_id: upload?.id ?? null,
      file_path: upload?.file_path ?? null,
    });

    res.json({ success: true, data: { expense_id: expenseId } });
  }),
);

export default router;
