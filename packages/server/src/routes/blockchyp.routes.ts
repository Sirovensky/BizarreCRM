import { Router, Request, Response } from 'express';
import net from 'net';
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
  voidCharge,
  captureCharge,
  deleteSignatureFile,
  getTerminalHeartbeat,
  BlockChypIndeterminateError,
} from '../services/blockchyp.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';
import { ERROR_CODES } from '../utils/errorCodes.js';

const logger = createLogger('blockchyp.routes');
const router = Router();

// BL7: RFC-4122-ish UUID v4 check. We accept any reasonable non-empty token
// (hex, dashes, max 128 chars). Stricter than "any string" so random garbage
// doesn't bloat the idempotency table, looser than a full UUID regex so
// clients can pass other collision-safe identifiers (nanoid, ULID, etc.).
const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9._-]{8,128}$/;

function nowSql(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function parseHostPort(value: string, defaultPort: number): { host: string; port: number } {
  const trimmed = value.trim();
  const [host, rawPort] = trimmed.includes(':') ? trimmed.split(':', 2) : [trimmed, undefined];
  const port = rawPort ? Number(rawPort) : defaultPort;
  if (!host || !Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new AppError('Invalid terminal IP or port', 400);
  }
  return { host, port };
}

function connectTcp(host: string, port: number, timeoutMs: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    let settled = false;
    const finish = (err?: Error) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      err ? reject(err) : resolve();
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => finish());
    socket.once('timeout', () => finish(new Error(`Timed out connecting to ${host}:${port}`)));
    socket.once('error', (err) => finish(err));
  });
}

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
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }

  const { terminalName, terminalIp } = req.body as { terminalName?: string; terminalIp?: string };

  // Refresh client in case credentials just changed
  refreshClient();

  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp is not configured. Please set API Key, Bearer Token, and Signing Key in Settings.', 400);
  }

  const result = await testConnection(db, terminalName);
  const cfg = getBlockChypConfig(db);
  const terminalIpToTest = String(terminalIp || cfg.terminalIp || '').trim();
  const lan: { attempted: boolean; success: boolean; host?: string; port?: number; error?: string } = {
    attempted: false,
    success: false,
  };

  if (terminalIpToTest) {
    const { host, port } = parseHostPort(terminalIpToTest, 8443);
    lan.attempted = true;
    lan.host = host;
    lan.port = port;
    try {
      await connectTcp(host, port, 3_000);
      lan.success = true;
    } catch (err) {
      lan.error = err instanceof Error ? err.message : 'LAN reachability failed';
    }
  }

  const success = result.success && (!lan.attempted || lan.success);
  const verificationStatus = result.success && lan.attempted && lan.success
    ? 'verified'
    : result.success && !lan.attempted
      ? 'gateway_only'
      : 'failed';
  const message = verificationStatus === 'verified'
    ? 'BlockChyp terminal verified.'
    : verificationStatus === 'gateway_only'
      ? 'BlockChyp gateway ping succeeded, but no terminal IP is saved so local hardware reachability was not verified.'
      : result.error || lan.error || 'BlockChyp terminal test failed.';

  res.status(success || verificationStatus === 'gateway_only' ? 200 : 502).json({
    success,
    data: {
      ...result,
      success,
      lan,
      verificationStatus,
      message,
    },
    ...(success ? {} : { message }),
  });
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
  // WEB-W3-004: `amount` is optional. When provided (split-payment card leg) the
  // caller supplies exactly the leg amount rather than the remaining invoice
  // balance. Must be > 0 and <= amountDue; validated after the invoice load.
  const { invoiceId, tip, amount: requestedAmount } = req.body;
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
  // WEB-W3-004: mirror the requestedAmount override so the dedup window
  // compares the actual leg amount, not the full remaining balance.
  const basePre = (requestedAmount !== undefined && requestedAmount !== null &&
    isFinite(Number(requestedAmount)) && Number(requestedAmount) > 0)
    ? Math.min(Number(requestedAmount), amountDuePre)
    : amountDuePre;
  const chargeAmountPre = basePre + (typeof tip === 'number' && tip > 0 ? tip : 0);
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

  // WEB-W3-004: honour split-payment leg amount when caller supplies it.
  // Bounds: must be a positive finite number that does not exceed amountDue.
  // Tip is applied on top of the leg amount (or amountDue) as before.
  let baseChargeAmount: number;
  if (requestedAmount !== undefined && requestedAmount !== null) {
    const parsed = typeof requestedAmount === 'number' ? requestedAmount : Number(requestedAmount);
    if (!isFinite(parsed) || parsed <= 0) {
      throw new AppError('amount must be a positive number', 400);
    }
    if (parsed > amountDue + 0.001) {
      // Allow up to 0.1 cent tolerance for float rounding in the frontend.
      throw new AppError(`Requested amount (${parsed.toFixed(2)}) exceeds remaining balance (${amountDue.toFixed(2)})`, 400);
    }
    baseChargeAmount = Math.min(parsed, amountDue);
  } else {
    baseChargeAmount = amountDue;
  }
  const chargeAmount = baseChargeAmount + tipAmount;
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

  // SEC-M34: processPayment throws BlockChypIndeterminateError when the charge
  // timed out AND the reconcile query also failed — outcome is truly unknown.
  // Do NOT write a 'failed' idempotency row (the charge may have been captured);
  // return HTTP 202 so the POS can surface a "pending reconciliation" state to
  // the operator rather than showing a confusing error and risking a retry
  // that would double-charge the card.
  //
  // The idempotency row stays 'pending'. The SEC-M42 janitor will flip it to
  // 'failed' after 5 minutes, at which point a human operator can decide
  // whether to retry or manually record the payment.
  let result: Awaited<ReturnType<typeof processPayment>>;
  try {
    result = await processPayment(db, chargeAmount, ticketRef, tipAmount > 0 ? tipAmount : undefined);
  } catch (payErr: unknown) {
    if (payErr instanceof BlockChypIndeterminateError) {
      logger.warn('BlockChyp charge indeterminate — returning 202 pending_reconciliation', {
        invoiceId: invoice.id,
        transactionRef: payErr.transactionRef,
        idempotencyKey,
      });
      audit(db, 'blockchyp_payment_indeterminate', req.user!.id, req.ip || 'unknown', {
        invoice_id: invoice.id,
        transaction_ref: payErr.transactionRef,
        idempotency_key: idempotencyKey,
        error: payErr.message,
      });
      res.status(202).json({
        success: false,
        data: {
          status: 'pending_reconciliation',
          transactionRef: payErr.transactionRef,
          message: 'Terminal charge outcome unknown. An operator must verify and reconcile this transaction.',
        },
      });
      return;
    }
    throw payErr; // unexpected — let asyncHandler handle it as 500
  }

  if (result.success) {
    // BL14: previously the payment INSERT, idempotency UPDATE, and invoice
    // UPDATE were three sequential `adb.run()` calls. A crash between any of
    // them would leave an orphaned state: BlockChyp charged + payment row
    // missing, or payment recorded + idempotency row still 'pending' (so a
    // retry would charge a SECOND time), or payment recorded + invoice still
    // showing a balance due. Bundle all three into a single atomic
    // transaction so post-capture recording is all-or-nothing.
    const userId = req.user!.id;
    // BUGHUNT-2026-05-16: round both sides so repeated partial payments
    // (e.g. 33.33 + 33.33 + 33.34) don't accumulate FP drift that leaves
    // amount_due stuck at 0.0000000001 and the invoice in 'partial' forever.
    // Mirrors the void-payment path at line 671-674.
    // BUGHUNT-2026-05-17: newStatus is still computed in JS as a
    // best-guess for the auto-close trigger below. The actual DB write
    // recomputes it from live amount_paid via differential SQL, so a
    // concurrent payment can't be lost. If our JS guess disagrees with
    // the live state (rare) the worst case is a missed auto-close
    // the operator can flip manually.
    const projectedPaid = roundMoney(invoice.amount_paid + chargeAmount);
    const newStatus = projectedPaid >= invoice.total ? 'paid' : 'partial';

    const txResults = await adb.transaction([
      {
        // SEC-M44: capture_state='captured' explicit — BlockChyp charge flow
        // captures immediately on approval, so the payment row is settled
        // funds by the time it lands. Refund gate reads this column.
        sql: `
          INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id,
            processor_transaction_id, processor_response, signature_file, signature_file_path,
            accepted_terms_name, accepted_terms_text, accepted_terms_hash, accepted_terms_accepted_at,
            notes, user_id, processor, reference, capture_state, created_at, updated_at)
          VALUES (?, ?, 'BlockChyp', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'blockchyp', ?, 'captured', datetime('now'), datetime('now'))
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
          result.acceptedTerms?.name ?? null,
          result.acceptedTerms?.content ?? null,
          result.acceptedTerms?.contentHash ?? null,
          result.acceptedTerms?.acceptedAt ?? null,
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
        // BUGHUNT-2026-05-17: guard the invoice UPDATE WHERE status NOT IN
        // ('void','refunded') so a /void landing between our pre-tx SELECT
        // and this write doesn't get silently flipped to 'paid'. Crucially
        // we do NOT use expectChanges here — the BlockChyp terminal has
        // already captured the card and the payment row + idempotency row
        // MUST persist so the merchant has a record of the charge. If the
        // invoice was voided concurrently, the payment row records as an
        // anomaly (audit-detectable) instead of silently overriding void.
        //
        // BUGHUNT-2026-05-17: differential SQL on amount_paid so a
        // concurrent payment / deposit-apply that landed between our
        // pre-tx invoice SELECT (line ~440) and this UPDATE can't be
        // lost-updated. Old shape wrote the JS-computed newPaid as an
        // absolute, clobbering the other writer's contribution. Now the
        // increment is atomic off the row's live amount_paid; amount_due
        // and status are re-derived from the same new total in SQL.
        sql: `UPDATE invoices
                SET amount_paid = ROUND((COALESCE(amount_paid, 0) + ?) * 100) / 100,
                    amount_due  = MAX(0, ROUND((COALESCE(total, 0) - COALESCE(amount_paid, 0) - ?) * 100) / 100),
                    status      = CASE
                      WHEN COALESCE(total, 0) <= COALESCE(amount_paid, 0) + ? THEN 'paid'
                      WHEN COALESCE(amount_paid, 0) + ? > 0                    THEN 'partial'
                      ELSE 'unpaid'
                    END,
                    updated_at = datetime('now')
              WHERE id = ? AND status NOT IN ('void', 'refunded')`,
        params: [chargeAmount, chargeAmount, chargeAmount, chargeAmount, invoice.id],
      },
    ]);
    // The first query in the batch is the payment INSERT. Its rowid is how
    // we correlate the audit log and (if configured) the auto-close.
    const paymentId = Number(txResults[0]?.lastInsertRowid ?? 0);
    // BUGHUNT-2026-05-17: detect void-clobber race. If the invoice UPDATE
    // matched 0 rows, the invoice was void/refunded by the time we wrote;
    // the BlockChyp charge already captured so the payment row stays, but
    // we log + audit the anomaly so the merchant can refund manually.
    const invoiceUpdateChanges = Number(txResults[2]?.changes ?? 0);
    if (invoiceUpdateChanges === 0) {
      logger.error('blockchyp_charge_on_terminal_invoice', {
        invoice_id: invoice.id,
        payment_id: paymentId,
        transaction_id: result.transactionId,
        amount: chargeAmount,
      });
      audit(db, 'blockchyp_payment_on_voided_invoice', req.user!.id, req.ip || 'unknown', {
        invoice_id: invoice.id,
        payment_id: paymentId,
        transaction_id: result.transactionId,
        amount: chargeAmount,
        action_required: 'manual_refund',
      });
    }

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
      accepted_terms_hash: result.acceptedTerms?.contentHash ?? null,
      accepted_terms_name: result.acceptedTerms?.name ?? null,
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
// Voids the processor transaction first, then marks the local payment row
// voided and backs the amount out of the invoice balance. The void_pending_at
// claim prevents concurrent duplicate void calls from both reaching BlockChyp.

router.post('/void-payment', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { paymentId } = req.body;

  if (!paymentId) {
    throw new AppError('paymentId is required', 400);
  }
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required to void a payment', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }

  const payment = await adb.get<{
    id: number;
    invoice_id: number;
    amount: number;
    processor_transaction_id: string | null;
    transaction_id: string | null;
    signature_file: string | null;
    signature_file_path: string | null;
    method: string;
    capture_state: string | null;
    void_pending_at: string | null;
  }>(`
    SELECT id, invoice_id, amount, processor_transaction_id, transaction_id,
           signature_file, signature_file_path, method, capture_state, void_pending_at
      FROM payments
     WHERE id = ?
  `, paymentId);

  if (!payment) {
    throw new AppError('Payment not found', 404);
  }
  if (payment.method !== 'BlockChyp') {
    throw new AppError('Payment is not a BlockChyp transaction', 400);
  }
  if (payment.capture_state === 'voided') {
    throw new AppError('Payment is already voided', 409);
  }
  if (payment.void_pending_at) {
    throw new AppError('Payment void is already in progress', 409);
  }

  const originalTransactionId = payment.processor_transaction_id ?? payment.transaction_id ?? null;
  if (!originalTransactionId) {
    throw new AppError('Payment is missing a BlockChyp transaction id', 400);
  }
  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }

  const claimResult = await adb.run(
    `UPDATE payments
        SET void_pending_at = ?,
            void_error = NULL,
            updated_at = datetime('now')
      WHERE id = ?
        AND COALESCE(capture_state, 'captured') != 'voided'
        AND void_pending_at IS NULL`,
    nowSql(),
    payment.id,
  );
  if (claimResult.changes === 0) {
    throw new AppError('Payment void is already in progress', 409);
  }

  const voidResult = await voidCharge(db, originalTransactionId, String(payment.id));
  if (!voidResult.success) {
    await adb.run(
      `UPDATE payments
          SET void_pending_at = NULL,
              void_error = ?,
              processor_response = COALESCE(?, processor_response),
              updated_at = datetime('now')
        WHERE id = ?`,
      voidResult.error ?? 'BlockChyp void failed',
      voidResult.response ? JSON.stringify(voidResult.response) : null,
      payment.id,
    );
    audit(db, 'blockchyp_payment_void_failed', req.user!.id, req.ip || 'unknown', {
      payment_id: payment.id,
      invoice_id: payment.invoice_id,
      transaction_id: originalTransactionId,
      amount: payment.amount,
      error: voidResult.error,
      transaction_ref: voidResult.transactionRef,
    });
    throw new AppError(voidResult.error || 'BlockChyp void failed', 400);
  }

  // BL8: delete the signature file from disk.
  const deleted = deleteSignatureFile(payment.signature_file_path);

  const voidAmount = roundMoney(Number(payment.amount || 0));

  // BL8: audit log with transaction id linkage.
  audit(db, 'blockchyp_payment_voided', req.user!.id, req.ip || 'unknown', {
    payment_id: payment.id,
    invoice_id: payment.invoice_id,
    transaction_id: originalTransactionId,
    void_transaction_id: voidResult.transactionId,
    transaction_ref: voidResult.transactionRef,
    amount: payment.amount,
    signature_file: payment.signature_file,
    signature_file_deleted: deleted,
  });

  // Flag the payment row so the signature fields don't resolve to stale data.
  await adb.transaction([
    {
      sql: `UPDATE payments
              SET signature_file = NULL,
                  signature_file_path = NULL,
                  capture_state = 'voided',
                  void_pending_at = NULL,
                  void_error = NULL,
                  voided_at = datetime('now'),
                  voided_by_user_id = ?,
                  processor_response = COALESCE(?, processor_response),
                  notes = COALESCE(notes || ' | ', '') || 'Voided by user ' || ? || ' at ' || datetime('now'),
                  updated_at = datetime('now')
            WHERE id = ?`,
      params: [
        req.user!.id,
        voidResult.response ? JSON.stringify(voidResult.response) : null,
        req.user!.id,
        payment.id,
      ],
      expectChanges: true,
      expectChangesError: 'Payment void local update failed',
    },
    {
      // BUGHUNT-2026-05-17: differential SQL so a concurrent payment
      // landing between our pre-tx invoice SELECT and this void's
      // UPDATE doesn't get lost-updated. Old shape wrote JS-computed
      // newPaid as absolute, clobbering the other writer's increment.
      // Decrement amount_paid by the voided amount, derive amount_due
      // and status from the live post-update total. MAX(0, ...) clamps
      // mirror the prior JS Math.max(0, priorPaid - amount) pattern.
      sql: `UPDATE invoices
              SET amount_paid = MAX(0, ROUND((COALESCE(amount_paid, 0) - ?) * 100) / 100),
                  amount_due  = MAX(0, ROUND((COALESCE(total, 0) - MAX(0, COALESCE(amount_paid, 0) - ?)) * 100) / 100),
                  status      = CASE
                    WHEN COALESCE(total, 0) <= MAX(0, COALESCE(amount_paid, 0) - ?) THEN 'paid'
                    WHEN MAX(0, COALESCE(amount_paid, 0) - ?) > 0                    THEN 'partial'
                    ELSE 'unpaid'
                  END,
                  updated_at = datetime('now')
            WHERE id = ?`,
      params: [voidAmount, voidAmount, voidAmount, voidAmount, payment.invoice_id],
    },
  ]);

  res.json({
    success: true,
    data: {
      paymentId: payment.id,
      transactionId: originalTransactionId,
      voidTransactionId: voidResult.transactionId,
      signatureFileDeleted: deleted,
    },
  });
}));

// ─── Capture a prior BlockChyp authorization ──────────────────────
//
// There is no auth-only sale flow in the current UI, but the SDK supports
// capture and legacy/imported rows can carry capture_state='authorized'. This
// endpoint keeps the settlement state transition explicit and guarded.

router.post('/capture-payment', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { paymentId, amount } = req.body;

  if (!paymentId) {
    throw new AppError('paymentId is required', 400);
  }
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required to capture a payment', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }

  const captureAmount = amount === undefined || amount === null
    ? null
    : Number(amount);
  if (captureAmount !== null && (!Number.isFinite(captureAmount) || captureAmount <= 0)) {
    throw new AppError('amount must be a positive number when provided', 400);
  }

  const payment = await adb.get<{
    id: number;
    invoice_id: number;
    amount: number;
    processor_transaction_id: string | null;
    transaction_id: string | null;
    method: string;
    capture_state: string | null;
    capture_pending_at: string | null;
  }>(`
    SELECT id, invoice_id, amount, processor_transaction_id, transaction_id,
           method, capture_state, capture_pending_at
      FROM payments
     WHERE id = ?
  `, paymentId);

  if (!payment) throw new AppError('Payment not found', 404);
  if (payment.method !== 'BlockChyp') {
    throw new AppError('Payment is not a BlockChyp transaction', 400);
  }
  if (payment.capture_state !== 'authorized') {
    throw new AppError(`Payment cannot be captured from state ${payment.capture_state ?? 'captured'}`, 409);
  }
  if (payment.capture_pending_at) {
    throw new AppError('Payment capture is already in progress', 409);
  }
  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }

  const originalTransactionId = payment.processor_transaction_id ?? payment.transaction_id ?? null;
  if (!originalTransactionId) {
    throw new AppError('Payment is missing a BlockChyp transaction id', 400);
  }

  const claimResult = await adb.run(
    `UPDATE payments
        SET capture_pending_at = ?,
            capture_error = NULL,
            updated_at = datetime('now')
      WHERE id = ?
        AND capture_state = 'authorized'
        AND capture_pending_at IS NULL`,
    nowSql(),
    payment.id,
  );
  if (claimResult.changes === 0) {
    throw new AppError('Payment capture is already in progress', 409);
  }

  const result = await captureCharge(db, originalTransactionId, captureAmount, String(payment.id));
  if (!result.success) {
    await adb.run(
      `UPDATE payments
          SET capture_pending_at = NULL,
              capture_error = ?,
              processor_response = COALESCE(?, processor_response),
              updated_at = datetime('now')
        WHERE id = ?`,
      result.error ?? 'BlockChyp capture failed',
      result.response ? JSON.stringify(result.response) : null,
      payment.id,
    );
    audit(db, 'blockchyp_payment_capture_failed', req.user!.id, req.ip || 'unknown', {
      payment_id: payment.id,
      invoice_id: payment.invoice_id,
      transaction_id: originalTransactionId,
      error: result.error,
      transaction_ref: result.transactionRef,
    });
    throw new AppError(result.error || 'BlockChyp capture failed', 400);
  }

  await adb.run(
    `UPDATE payments
        SET capture_state = 'captured',
            capture_pending_at = NULL,
            capture_error = NULL,
            captured_at = datetime('now'),
            captured_by_user_id = ?,
            processor_transaction_id = COALESCE(?, processor_transaction_id),
            processor_response = COALESCE(?, processor_response),
            updated_at = datetime('now')
      WHERE id = ?`,
    req.user!.id,
    result.transactionId ?? null,
    result.response ? JSON.stringify(result.response) : null,
    payment.id,
  );

  audit(db, 'blockchyp_payment_captured', req.user!.id, req.ip || 'unknown', {
    payment_id: payment.id,
    invoice_id: payment.invoice_id,
    transaction_id: result.transactionId ?? originalTransactionId,
    transaction_ref: result.transactionRef,
    amount: captureAmount ?? payment.amount,
  });

  res.json({
    success: true,
    data: {
      paymentId: payment.id,
      transactionId: result.transactionId ?? originalTransactionId,
      transactionRef: result.transactionRef,
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

  // WEB-UIUX-937: Reachability — previously /status only reported
  // configured-state (enabled flag + creds present), so a configured-but-
  // offline terminal silently passed the gate and then failed mid-charge.
  // We surface the last in-process ping outcome from the heartbeat cache.
  // `online` is true only when the last ping succeeded within the freshness
  // window. UI can use it to disable Charge buttons or to prompt operator
  // to power-cycle / reconnect the terminal before starting a sale.
  const HEARTBEAT_FRESH_MS = 5 * 60 * 1000; // 5 minutes
  const heartbeat = getTerminalHeartbeat(cfg.terminalName);
  let online = false;
  let stale = false;
  if (heartbeat?.lastSeenAt) {
    const ageMs = Date.now() - new Date(heartbeat.lastSeenAt).getTime();
    online = ageMs <= HEARTBEAT_FRESH_MS;
    stale = !online;
  }

  res.json({
    success: true,
    data: {
      enabled: isBlockChypEnabled(db),
      terminalName: cfg.terminalName,
      tcEnabled: cfg.tcEnabled,
      promptForTip: cfg.promptForTip,
      autoCloseTicket: cfg.autoCloseTicket,
      heartbeat: heartbeat
        ? {
            lastSeenAt: heartbeat.lastSeenAt,
            lastCheckedAt: heartbeat.lastCheckedAt,
            lastError: heartbeat.lastError,
            firmwareVersion: heartbeat.firmwareVersion,
            online,
            stale,
            freshnessWindowMs: HEARTBEAT_FRESH_MS,
          }
        : null,
    },
  });
});

export default router;
