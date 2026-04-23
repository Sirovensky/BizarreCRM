/**
 * Receipt OCR service (SCAN-490).
 *
 * Decision: tesseract.js is NOT in packages/server/package.json.
 * FINDING (dep-addition required): To enable real OCR, add "tesseract.js": "^5.x"
 * to packages/server/package.json dependencies. Until then, processReceiptOcr
 * immediately marks uploads as failed with a clear message.
 *
 * Without tesseract.js the pipeline still functions end-to-end:
 *   upload → enqueueReceiptOcr (sets pending) → receiptOcrCron picks up →
 *   processReceiptOcr (marks failed with informative error_message)
 *
 * When tesseract.js IS installed the lazy import in processReceiptOcr will
 * succeed automatically — no other code change needed.
 *
 * Security:
 *   - File path from DB row is validated against uploadsPath before any read.
 *   - Absolute paths are redacted from error_message (only basename logged).
 *   - OCR text capped at 64 KB when writing to ocr_text column.
 *
 * Public API:
 *   enqueueReceiptOcr(db, uploadId)   — call from route handler post-upload.
 *   processReceiptOcr(db, uploadId, uploadsPath) — called by receiptOcrCron.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('receipt-ocr');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Hard cap on ocr_text column to prevent runaway writes (64 KB). */
const OCR_TEXT_MAX_BYTES = 64 * 1024;

// ---------------------------------------------------------------------------
// Security helpers
// ---------------------------------------------------------------------------

/**
 * Returns true when `filePath` is a descendant of `baseDir`.
 * Both paths are resolved to absolute before comparison so symlink-style
 * traversal attempts (/uploads/../../../etc/passwd) are neutralised.
 */
function isPathUnder(filePath: string, baseDir: string): boolean {
  const resolved = path.resolve(filePath);
  const base = path.resolve(baseDir);
  // Ensure the resolved path starts with base + separator so "base2" doesn't
  // accidentally match "base".
  return resolved === base || resolved.startsWith(base + path.sep);
}

// ---------------------------------------------------------------------------
// OCR text parser — best-effort regex extraction
// ---------------------------------------------------------------------------

interface ParsedReceipt {
  total?: string;
  date?: string;
  vendor?: string;
}

/**
 * Extracts common receipt fields from raw OCR text.
 * All fields are optional — partial results are still useful.
 */
function parseReceiptText(text: string): ParsedReceipt {
  const result: ParsedReceipt = {};

  // Total: look for currency amounts near keywords
  const totalMatch = text.match(
    /(?:total|amount\s+due|grand\s+total|balance\s+due)[^\d$]*[\$£€]?\s*([\d,]+\.\d{2})/i,
  );
  if (totalMatch) {
    result.total = totalMatch[1].replace(/,/g, '');
  } else {
    // Fallback: last standalone currency amount on the receipt
    const amounts = [...text.matchAll(/[\$£€]([\d,]+\.\d{2})/g)];
    if (amounts.length > 0) {
      result.total = amounts[amounts.length - 1][1].replace(/,/g, '');
    }
  }

  // Date: ISO, US, or common locale formats
  const dateMatch = text.match(
    /\b(\d{4}[-\/]\d{2}[-\/]\d{2}|\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})\b/,
  );
  if (dateMatch) {
    result.date = dateMatch[1];
  }

  // Vendor: first non-empty line that is mostly alphabetic characters
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  for (const line of lines.slice(0, 6)) {
    // Skip lines that look like addresses, phone numbers, or pure numbers
    if (/^\d/.test(line)) continue;
    if (/\d{3}[-.\s]\d{3,4}/.test(line)) continue; // phone-like
    if (line.length >= 3 && line.length <= 80 && /[A-Za-z]{3}/.test(line)) {
      result.vendor = line;
      break;
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Core processor
// ---------------------------------------------------------------------------

/**
 * Process a single receipt upload through OCR.
 *
 * Transitions:
 *   pending → processing → completed   (success)
 *   pending → processing → failed      (any error)
 *   (also handles uploads already in processing state from a crashed tick)
 *
 * Never throws. All errors are caught and written back to the DB row.
 *
 * @param db          - better-sqlite3 Database for the owning tenant.
 * @param uploadId    - Primary key from expense_receipt_uploads.
 * @param uploadsPath - Absolute base path for all tenant uploads (from config).
 */
export async function processReceiptOcr(
  db: Database.Database,
  uploadId: number,
  uploadsPath: string,
): Promise<void> {
  // ---- Step 1: claim the row (pending → processing) ----------------------
  try {
    const claimed = db
      .prepare(
        `UPDATE expense_receipt_uploads
            SET ocr_status = 'processing'
          WHERE id = ?
            AND ocr_status IN ('pending','processing')`,
      )
      .run(uploadId);

    if (claimed.changes === 0) {
      // Already completed/failed or non-existent — nothing to do.
      logger.info('OCR: upload already resolved or not found, skipping', {
        upload_id: uploadId,
      });
      return;
    }
  } catch (err) {
    logger.error('OCR: failed to claim upload row', {
      upload_id: uploadId,
      error: err instanceof Error ? err.message : String(err),
    });
    return; // Cannot proceed without knowing we own the row
  }

  // ---- Step 2: fetch file path from DB -----------------------------------
  let filePath: string;
  try {
    const row = db
      .prepare<[number], { file_path: string }>(
        `SELECT file_path FROM expense_receipt_uploads WHERE id = ?`,
      )
      .get(uploadId);

    if (!row) {
      await markFailed(db, uploadId, 'Upload row not found after claim');
      return;
    }
    filePath = row.file_path;
  } catch (err) {
    await markFailed(
      db,
      uploadId,
      `DB read error: ${err instanceof Error ? err.message : String(err)}`,
    );
    return;
  }

  // ---- Step 3: security — verify path is under uploadsPath ---------------
  if (!isPathUnder(filePath, uploadsPath)) {
    logger.error('OCR: file_path is outside uploadsPath — rejecting', {
      upload_id: uploadId,
      file_basename: path.basename(filePath), // never log absolute path
    });
    await markFailed(db, uploadId, 'File path failed security check');
    return;
  }

  // ---- Step 4: verify file exists and is readable ------------------------
  try {
    fs.accessSync(filePath, fs.constants.R_OK);
  } catch {
    await markFailed(
      db,
      uploadId,
      `File not readable: ${path.basename(filePath)}`,
    );
    return;
  }

  // ---- Step 5: attempt OCR -----------------------------------------------

  // Lazy import so the server starts cleanly even without tesseract.js.
  // We type the module as `unknown` and narrow it at runtime so TypeScript
  // does not attempt to resolve the missing package declaration at compile time.
  // When tesseract.js IS installed the import resolves and the duck-type check
  // on `.recognize` passes — no other change needed.
  let tesseractModule: unknown = null;
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    tesseractModule = await (Function('m', 'return import(m)') as (m: string) => Promise<unknown>)('tesseract.js');
  } catch {
    // Package not installed — expected until dep is added.
    logger.warn('OCR: tesseract.js not available', { upload_id: uploadId });
    await markFailed(
      db,
      uploadId,
      'OCR processor not installed; configure tesseract.js in package.json',
    );
    return;
  }

  // Narrow to a usable shape: { recognize(path, lang, opts): Promise<{ data: { text: string } }> }
  if (
    tesseractModule === null ||
    typeof tesseractModule !== 'object' ||
    typeof (tesseractModule as Record<string, unknown>)['recognize'] !== 'function'
  ) {
    await markFailed(db, uploadId, 'OCR processor loaded but has unexpected shape');
    return;
  }

  const recognize = (tesseractModule as Record<string, unknown>)['recognize'] as (
    image: string,
    lang: string,
    opts: Record<string, unknown>,
  ) => Promise<{ data: { text: string } }>;

  // tesseract.js is available — run OCR.
  try {
    logger.info('OCR: starting tesseract recognition', {
      upload_id: uploadId,
      file: path.basename(filePath),
    });

    const {
      data: { text },
    } = await recognize(filePath, 'eng', {
      // Suppress tesseract's own console output; our logger handles it.
      logger: () => undefined,
    });

    // Cap text length to guard against pathological inputs.
    const cappedText =
      text.length > OCR_TEXT_MAX_BYTES
        ? text.slice(0, OCR_TEXT_MAX_BYTES)
        : text;

    const parsed = parseReceiptText(cappedText);

    db.prepare(
      `UPDATE expense_receipt_uploads
          SET ocr_status  = 'completed',
              ocr_text    = ?,
              parsed_json = ?,
              error_message = NULL
        WHERE id = ?`,
    ).run(cappedText, JSON.stringify(parsed), uploadId);

    logger.info('OCR: completed successfully', {
      upload_id: uploadId,
      text_bytes: cappedText.length,
      parsed_fields: Object.keys(parsed).join(',') || 'none',
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.error('OCR: tesseract recognition failed', {
      upload_id: uploadId,
      error: msg,
    });
    await markFailed(db, uploadId, `OCR recognition error: ${msg.slice(0, 200)}`);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function markFailed(
  db: Database.Database,
  uploadId: number,
  errorMessage: string,
): Promise<void> {
  try {
    db.prepare(
      `UPDATE expense_receipt_uploads
          SET ocr_status    = 'failed',
              error_message = ?
        WHERE id = ?`,
    ).run(errorMessage.slice(0, 500), uploadId);
  } catch (err) {
    // Log but do not rethrow — caller must not be disrupted.
    logger.error('OCR: could not write failed status to DB', {
      upload_id: uploadId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

// ---------------------------------------------------------------------------
// Enqueue (public API — called from route handler)
// ---------------------------------------------------------------------------

/**
 * Enqueue an OCR job for a freshly-uploaded expense receipt.
 *
 * The real work happens on the next receiptOcrCron tick (every 2 min).
 * This function only ensures the row is in 'pending' state and emits a log.
 *
 * Never throws — callers do not need try/catch.
 */
export async function enqueueReceiptOcr(
  db: Database.Database,
  uploadId: number,
): Promise<void> {
  try {
    db.prepare(
      `UPDATE expense_receipt_uploads
          SET ocr_status = 'pending'
        WHERE id = ? AND ocr_status NOT IN ('processing','completed')`,
    ).run(uploadId);

    logger.info(
      'OCR enqueued; processor will pick up on next cron tick',
      { upload_id: uploadId },
    );
  } catch (err) {
    // Intentionally swallow — the upload already succeeded. The cron will
    // pick up any 'pending' rows including this one on the next tick.
    logger.error('enqueueReceiptOcr: failed to record pending status', {
      upload_id: uploadId,
      error: err instanceof Error ? err.message : 'unknown',
    });
  }
}
