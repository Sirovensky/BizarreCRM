import { Router, Request, Response } from 'express';
import { config } from '../config.js';
import {
  isBlockChypEnabled,
  getBlockChypConfig,
  testConnection,
  capturePreTicketSignature,
  captureCheckInSignature,
  processPayment,
  refreshClient,
  adjustTip,
  deleteSignatureFile,
} from '../services/blockchyp.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('blockchyp.routes');
const router = Router();

// BL7: RFC-4122-ish UUID v4 check. We accept any reasonable non-empty token
// (hex, dashes, max 128 chars). Stricter than "any string" so random garbage
// doesn't bloat the idempotency table, looser than a full UUID regex so
// clients can pass other collision-safe identifiers (nanoid, ULID, etc.).
const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9._-]{8,128}$/;

interface IdempotencyRow {
  id: number;
  invoice_id: number;
  client_request_id: string;
  status: 'pending' | 'completed' | 'failed';
  transaction_id: string | null;
  payment_id: number | null;
  amount: number | null;
  error_message: string | null;
  created_at: string;
}

// ─── Test connection ────────────────────────────────────────────────

router.post('/test-connection', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403);
  }

  const { terminalName } = req.body;

  // Refresh client in case credentials just changed
  refreshClient();

  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp is not configured. Please set API Key, Bearer Token, and Signing Key in Settings.', 400);
  }

  const result = await testConnection(db, terminalName);
  res.json({ success: result.success, data: result });
}));

// ─── Capture pre-ticket signature (before ticket exists) ────────────

router.post('/capture-checkin-signature', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }

  const cfg = getBlockChypConfig(db);
  if (!cfg.tcEnabled) {
    throw new AppError('Check-in signature capture is not enabled in settings', 400);
  }

  const result = await capturePreTicketSignature(db);
  res.json({ success: result.success, data: result });
}));

// ─── Capture check-in signature (after ticket exists) ───────────────

router.post('/capture-signature', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { ticketId } = req.body;

  if (!ticketId) {
    throw new AppError('ticketId is required', 400);
  }

  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }

  const cfg = getBlockChypConfig(db);
  if (!cfg.tcEnabled) {
    throw new AppError('Check-in signature capture is not enabled in settings', 400);
  }

  // Load ticket
  const ticket = await adb.get<{ id: number; order_id: string }>('SELECT id, order_id FROM tickets WHERE id = ?', ticketId);
  if (!ticket) {
    throw new AppError('Ticket not found', 404);
  }

  const result = await captureCheckInSignature(db, ticket.order_id);

  if (result.success && result.signatureFile) {
    // Save signature path to ticket
    await adb.run('UPDATE tickets SET signature_file = ?, updated_at = datetime(\'now\') WHERE id = ?',
      result.signatureFile, ticket.id);
  }

  res.json({ success: result.success, data: result });
}));

// ─── Process payment via terminal ───────────────────────────────────
//
// BL7: per-invoice idempotency. Clients MUST supply `idempotency_key` in the
// body (UUID v4 is ideal — nanoid/ULID also fine). The same key reused for
// the same invoice collapses into one real charge:
//   - pending → we return 409 (request is still in flight)
//   - completed → we re-serialize the previous success result (safe replay)
//   - failed → client may retry, but MUST generate a fresh key
//
// BL6 coupled fix: the underlying processPayment() builds a globally-unique
// transactionRef via a counter, so even if two keys slip past this check,
// BlockChyp can't accidentally idempotency-collide them.

router.post('/process-payment', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { invoiceId, tip } = req.body;
  const idempotencyKey = (req.body?.idempotency_key || req.headers['idempotency-key']) as string | undefined;

  // SEC-H43: processing a card payment commits the shop to settlement fees
  // and a refund path even if the charge fails downstream. Gate to
  // admin/manager so a cashier can't drive up fees against a compromised
  // session. Technicians still record payments via the non-card POS path.
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required for card payments', 403);
  }

  if (!invoiceId) {
    throw new AppError('invoiceId is required', 400);
  }

  // BL7: mandatory idempotency key
  if (!idempotencyKey || typeof idempotencyKey !== 'string' || !IDEMPOTENCY_KEY_RE.test(idempotencyKey)) {
    throw new AppError('idempotency_key is required and must be a stable client-generated token', 400);
  }

  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }

  // Load invoice
  const invoice = await adb.get<{
    id: number; order_id: string; ticket_id: number | null;
    total: number; amount_paid: number; status: string;
    ticket_order_id: string | null;
  }>(`
    SELECT i.id, i.order_id, i.ticket_id, i.total, i.amount_paid, i.status,
           t.order_id as ticket_order_id
    FROM invoices i
    LEFT JOIN tickets t ON t.id = i.ticket_id
    WHERE i.id = ?
  `, invoiceId);

  if (!invoice) {
    throw new AppError('Invoice not found', 404);
  }
  if (invoice.status === 'void') {
    throw new AppError('Cannot process payment on a voided invoice', 400);
  }
  if (invoice.status === 'paid') {
    // BL7: This is the "double-click check" — invoice ALREADY at paid status.
    throw new AppError('Invoice is already fully paid', 400);
  }

  // SEC-H42: 30-second dedup window on (invoice_id, client_ip, amount).
  // Covers the case where a different (fresh) idempotency_key is sent
  // from the same client for the same invoice + amount within seconds —
  // usually a retried card-dip caused by an impatient user + terminal
  // timeout. Without this, a card that just cleared can be re-charged
  // because the second request has its own unique key and passes the
  // BL7 check. 30s is long enough to cover normal terminal + network
  // stalls and short enough that two separate legitimate same-amount
  // charges in quick succession (e.g. parts + labor on one ticket)
  // can be disambiguated by the cashier waiting 30s.
  const amountDuePre = Number(invoice.total) - Number(invoice.amount_paid || 0);
  const chargeAmountPre = amountDuePre + (typeof tip === 'number' && tip > 0 ? tip : 0);
  const clientIp = req.ip || req.socket?.remoteAddress || 'unknown';
  const recentDupe = await adb.get<{ id: number; transaction_id: string | null }>(
    `SELECT pi.id, pi.transaction_id
       FROM payment_idempotency pi
      WHERE pi.invoice_id = ?
        AND pi.amount = ?
        AND pi.status = 'completed'
        AND pi.created_at > datetime('now', '-30 seconds')
      LIMIT 1`,
    invoice.id,
    chargeAmountPre,
  );
  void clientIp; // DB-side dedup is scoped to invoice_id+amount; IP is
  // recorded below for audit + future refinement rather than a WHERE
  // clause — a retry behind CGNAT rotates src IP in seconds so binding
  // the window to IP would miss the replay we're trying to block.
  if (recentDupe) {
    logger.warn('BlockChyp process-payment dedup fired — recent completed charge matches', {
      invoiceId: invoice.id,
      amount: chargeAmountPre,
      transactionId: recentDupe.transaction_id,
    });
    throw new AppError(
      'A charge of this amount completed in the last 30 seconds. Wait 30s and retry if intentional.',
      409,
    );
  }

  // BL7: check / acquire the idempotency lock BEFORE calling BlockChyp.
  // Using INSERT OR IGNORE + post-read means at most one caller gets the
  // 'pending' row; every other caller sees an existing row and is handled
  // by the branching logic below. better-sqlite3 is synchronous so there
  // is no window between the INSERT and the SELECT.
  const existing = await adb.get<IdempotencyRow>(
    // SEC-M41: scope the idempotency lookup by user_id so a stolen
    // (invoice_id, client_request_id) pair cannot be replayed from a
    // different user's session to read the original charge's
    // transaction_id / amount via the 'replayed charge' happy path.
    'SELECT * FROM payment_idempotency WHERE invoice_id = ? AND client_request_id = ? AND user_id = ?',
    invoice.id, idempotencyKey, req.user!.id,
  );

  if (existing) {
    if (existing.status === 'completed') {
      // Safe replay: return the already-recorded payment.
      logger.info('Idempotency replay: returning prior completed charge', {
        invoiceId: invoice.id,
        idempotencyKey,
        transactionId: existing.transaction_id,
      });
      res.json({
        success: true,
        data: {
          success: true,
          replayed: true,
          transactionId: existing.transaction_id,
          amount: existing.amount,
        },
      });
      return;
    }
    if (existing.status === 'pending') {
      // A parallel request is still in flight. Return 409 so the client
      // retries the SAME key after a short backoff (or surfaces a spinner).
      res.status(409).json({
        success: false,
        message: 'A payment with this idempotency key is already being processed',
      });
      return;
    }
    // existing.status === 'failed' → client must use a new key for a retry.
    res.status(409).json({
      success: false,
      message: 'This idempotency key has already been used for a failed attempt. Generate a new key to retry.',
    });
    return;
  }

  const amountDue = invoice.total - invoice.amount_paid;
  if (amountDue <= 0) {
    throw new AppError('No balance due on this invoice', 400);
  }

  const tipAmount = tip && typeof tip === 'number' && tip > 0 ? tip : 0;
  const chargeAmount = amountDue + tipAmount;
  const ticketRef = invoice.ticket_order_id || invoice.order_id;

  // Reserve the idempotency row as 'pending' before we dispatch.
  // SEC-M41: user_id is now part of the UNIQUE constraint.
  const reserveResult = await adb.run(
    `INSERT INTO payment_idempotency
       (invoice_id, client_request_id, user_id, status, amount, created_at, updated_at)
     VALUES (?, ?, ?, 'pending', ?, datetime('now'), datetime('now'))`,
    invoice.id, idempotencyKey, req.user!.id, chargeAmount,
  );
  const idempotencyRowId = Number(reserveResult.lastInsertRowid);

  const result = await processPayment(db, chargeAmount, ticketRef, tipAmount > 0 ? tipAmount : undefined);

  if (result.success) {
    // BL14: previously the payment INSERT, idempotency UPDATE, and invoice
    // UPDATE were three sequential `adb.run()` calls. A crash between any of
    // them would leave an orphaned state: BlockChyp charged + payment row
    // missing, or payment recorded + idempotency row still 'pending' (so a
    // retry would charge a SECOND time), or payment recorded + invoice still
    // showing a balance due. Bundle all three into a single atomic
    // transaction so post-capture recording is all-or-nothing.
    const userId = req.user!.id;
    const newPaid = invoice.amount_paid + chargeAmount;
    const newStatus = newPaid >= invoice.total ? 'paid' : 'partial';
    const newDue = Math.max(0, invoice.total - newPaid);

    const txResults = await adb.transaction([
      {
        // SEC-M44: capture_state='captured' explicit — BlockChyp charge flow
        // captures immediately on approval, so the payment row is settled
        // funds by the time it lands. Refund gate reads this column.
        sql: `
          INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id,
            processor_transaction_id, processor_response, signature_file, signature_file_path,
            notes, user_id, processor, reference, capture_state, created_at, updated_at)
          VALUES (?, ?, 'BlockChyp', ?, ?, ?, ?, ?, ?, ?, ?, 'blockchyp', ?, 'captured', datetime('now'), datetime('now'))
        `,
        params: [
          invoice.id,
          chargeAmount,
          result.cardType ? `${result.cardType} ending ${result.last4}` : 'Card',
          result.transactionId ?? null,
          result.transactionId ?? null,
          result.receiptSuggestions ? JSON.stringify(result.receiptSuggestions) : null,
          result.signatureFile ?? null,
          result.signatureFilePath ?? null,
          result.authCode ? `Auth: ${result.authCode}` : null,
          userId,
          result.transactionRef ?? result.transactionId ?? null,
        ],
      },
      // BL7: mark idempotency row completed so subsequent duplicates replay.
      // Uses a correlated subquery to read back the payment id we just
      // inserted — keeps the whole batch self-contained without a JS-side
      // round-trip between the two statements.
      {
        sql: `
          UPDATE payment_idempotency
             SET status = 'completed',
                 transaction_id = ?,
                 payment_id = (SELECT id FROM payments WHERE invoice_id = ? AND reference = ? ORDER BY id DESC LIMIT 1),
                 updated_at = datetime('now')
           WHERE id = ?
        `,
        params: [
          result.transactionId ?? null,
          invoice.id,
          result.transactionRef ?? result.transactionId ?? null,
          idempotencyRowId,
        ],
      },
      {
        sql: `UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?`,
        params: [newPaid, newDue, newStatus, invoice.id],
      },
    ]);
    // The first query in the batch is the payment INSERT. Its rowid is how
    // we correlate the audit log and (if configured) the auto-close.
    const paymentId = Number(txResults[0]?.lastInsertRowid ?? 0);

    // BL8: payment event audit log (links transaction id → payment row → signature).
    audit(db, 'blockchyp_payment_success', req.user!.id, req.ip || 'unknown', {
      invoice_id: invoice.id,
      payment_id: paymentId,
      transaction_id: result.transactionId,
      transaction_ref: result.transactionRef,
      amount: chargeAmount,
      tip: tipAmount,
      test_mode: result.testMode,
      signature_file: result.signatureFile ?? null,
      card_type: result.cardType ?? null,
      last4: result.last4 ?? null,
    });

    // Auto-close ticket if configured. Kept outside the txn — a failed
    // auto-close must never roll back a captured charge.
    const cfg = getBlockChypConfig(db);
    if (cfg.autoCloseTicket && invoice.ticket_id && newStatus === 'paid') {
      const closedStatus = await adb.get<{ id: number }>("SELECT id FROM ticket_statuses WHERE name LIKE '%closed%' OR name LIKE '%picked up%' ORDER BY is_closed DESC LIMIT 1");
      if (closedStatus) {
        await adb.run('UPDATE tickets SET status_id = ?, updated_at = datetime(\'now\') WHERE id = ?',
          closedStatus.id, invoice.ticket_id);
      }
    }
  } else {
    // BL7: mark failed so client can retry (with a fresh key).
    // BL8: cleanup the signature file that may have been captured before decline.
    if (result.signatureFilePath) {
      deleteSignatureFile(result.signatureFilePath);
    }
    await adb.run(
      `UPDATE payment_idempotency
          SET status = 'failed',
              error_message = ?,
              updated_at = datetime('now')
        WHERE id = ?`,
      result.error ?? 'unknown error', idempotencyRowId,
    );
    audit(db, 'blockchyp_payment_failed', req.user!.id, req.ip || 'unknown', {
      invoice_id: invoice.id,
      transaction_ref: result.transactionRef,
      error: result.error,
      test_mode: result.testMode,
    });
  }

  res.json({ success: result.success, data: result });
}));

// ─── BL8: Void a BlockChyp payment ────────────────────────────────
//
// When a payment is voided, any captured signature file becomes orphaned
// on disk. This endpoint deletes the signature file, audit-logs the void,
// and flips the payment record notes. It does NOT call BlockChyp's void
// API (that's a separate refunds flow owned by refunds.routes.ts); it is
// the cleanup half of a void workflow.

router.post('/void-payment', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { paymentId } = req.body;

  if (!paymentId) {
    throw new AppError('paymentId is required', 400);
  }
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required to void a payment', 403);
  }

  const payment = await adb.get<{
    id: number;
    invoice_id: number;
    amount: number;
    processor_transaction_id: string | null;
    signature_file: string | null;
    signature_file_path: string | null;
    method: string;
  }>('SELECT id, invoice_id, amount, processor_transaction_id, signature_file, signature_file_path, method FROM payments WHERE id = ?', paymentId);

  if (!payment) {
    throw new AppError('Payment not found', 404);
  }
  if (payment.method !== 'BlockChyp') {
    throw new AppError('Payment is not a BlockChyp transaction', 400);
  }

  // BL8: delete the signature file from disk.
  const deleted = deleteSignatureFile(payment.signature_file_path);

  // BL8: audit log with transaction id linkage.
  audit(db, 'blockchyp_payment_voided', req.user!.id, req.ip || 'unknown', {
    payment_id: payment.id,
    invoice_id: payment.invoice_id,
    transaction_id: payment.processor_transaction_id,
    amount: payment.amount,
    signature_file: payment.signature_file,
    signature_file_deleted: deleted,
  });

  // Flag the payment row so the signature fields don't resolve to stale data.
  await adb.run(
    `UPDATE payments
        SET signature_file = NULL,
            signature_file_path = NULL,
            notes = COALESCE(notes || ' | ', '') || 'Voided by user ' || ? || ' at ' || datetime('now'),
            updated_at = datetime('now')
      WHERE id = ?`,
    req.user!.id, payment.id,
  );

  res.json({
    success: true,
    data: {
      paymentId: payment.id,
      transactionId: payment.processor_transaction_id,
      signatureFileDeleted: deleted,
    },
  });
}));

// ─── BL9: Adjust tip on a BlockChyp payment ───────────────────────
//
// Post-signature tip adjust for restaurant / salon flows. BlockChyp TS SDK
// does not currently expose a tip-adjust endpoint, so this returns
// { code: 'NOT_SUPPORTED' } — the route contract is stable so frontends
// can build against it and the server can ship real support transparently
// once the SDK adds it.

router.post('/adjust-tip', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const { transaction_id, new_tip } = req.body || {};

  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }
  if (!transaction_id) {
    throw new AppError('transaction_id is required', 400);
  }
  if (typeof new_tip !== 'number' || !isFinite(new_tip) || new_tip < 0) {
    throw new AppError('new_tip must be a non-negative number', 400);
  }

  const result = await adjustTip(db, transaction_id, new_tip);

  audit(db, 'blockchyp_tip_adjust_attempt', req.user?.id ?? null, req.ip || 'unknown', {
    transaction_id,
    new_tip,
    success: result.success,
    code: result.code,
  });

  // Not supported → return success:false with code so the frontend can
  // render a useful message. 200 is correct because the request itself is
  // valid; the capability is missing.
  res.json({ success: result.success, data: result });
}));

// ─── Get BlockChyp status (for frontend to know if enabled) ────────

router.get('/status', (req: Request, res: Response) => {
  const db = req.db;
  const cfg = getBlockChypConfig(db);
  res.json({
    success: true,
    data: {
      enabled: isBlockChypEnabled(db),
      terminalName: cfg.terminalName,
      tcEnabled: cfg.tcEnabled,
      promptForTip: cfg.promptForTip,
      autoCloseTicket: cfg.autoCloseTicket,
    },
  });
});

export default router;
