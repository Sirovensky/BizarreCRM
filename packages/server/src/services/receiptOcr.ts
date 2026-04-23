/**
 * Receipt OCR service stub (SCAN-490, wave 1).
 *
 * This module is intentionally minimal. The real OCR worker (Tesseract or
 * Cloud Vision API) will be wired in a future wave. For now every call marks
 * the upload as pending and emits a structured log entry so the queue is
 * observable from day one.
 *
 * Contract:
 *   - enqueueReceiptOcr() NEVER throws — callers do not need try/catch.
 *   - ocr_status starts at 'pending' and remains there until the real worker
 *     picks it up and transitions it to 'processing' → 'completed' | 'failed'.
 *
 * Future integration points:
 *   - Replace the log line with a real job-queue push (Bull, pg-boss, etc.).
 *   - The worker should call back into the DB to set ocr_status='completed',
 *     ocr_text, and parsed_json, then UPDATE expenses SET receipt_ocr_text,
 *     receipt_ocr_parsed_json, receipt_uploaded_at for the parent expense row.
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('receipt-ocr');

/**
 * Enqueue an OCR job for a freshly-uploaded expense receipt.
 *
 * @param db       - better-sqlite3 Database instance (synchronous, from req.db).
 *                   Accepts `any` so callers using the typed AsyncDb wrapper can
 *                   pass req.db directly without a cast.
 * @param uploadId - Primary key from expense_receipt_uploads.
 */
export async function enqueueReceiptOcr(db: Database.Database, uploadId: number): Promise<void> {
  try {
    // Ensure the record is in 'pending' state before logging the enqueue.
    // The record is already created with DEFAULT 'pending' in the route handler,
    // but an explicit set makes the intent clear and guards against future
    // call-site changes that might reuse this function for re-queue workflows.
    db.prepare(
      `UPDATE expense_receipt_uploads
         SET ocr_status = 'pending'
       WHERE id = ? AND ocr_status NOT IN ('processing','completed')`,
    ).run(uploadId);

    logger.info('OCR enqueued for upload', { upload_id: uploadId });

    // TODO (wave 2): push { uploadId } onto the job queue here.
    // Example with Bull:
    //   await ocrQueue.add({ uploadId }, { attempts: 3, backoff: 5000 });
  } catch (err) {
    // Intentionally swallow — the upload already succeeded. The OCR job
    // can be retried by an operator or a future background sweeper.
    logger.error('enqueueReceiptOcr: failed to record pending status', {
      upload_id: uploadId,
      error: err instanceof Error ? err.message : 'unknown',
    });
  }
}
