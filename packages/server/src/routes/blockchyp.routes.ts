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
} from '../services/blockchyp.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

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
  const ticket = db.prepare('SELECT id, order_id FROM tickets WHERE id = ?').get(ticketId) as { id: number; order_id: string } | undefined;
  if (!ticket) {
    throw new AppError('Ticket not found', 404);
  }

  const result = await captureCheckInSignature(db, ticket.order_id);

  if (result.success && result.signatureFile) {
    // Save signature path to ticket
    db.prepare('UPDATE tickets SET signature_file = ?, updated_at = datetime(\'now\') WHERE id = ?')
      .run(result.signatureFile, ticket.id);
  }

  res.json({ success: result.success, data: result });
}));

// ─── Process payment via terminal ───────────────────────────────────

router.post('/process-payment', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const { invoiceId, tip } = req.body;

  if (!invoiceId) {
    throw new AppError('invoiceId is required', 400);
  }

  if (!isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }

  // Load invoice
  const invoice = db.prepare(`
    SELECT i.id, i.order_id, i.ticket_id, i.total, i.amount_paid, i.status,
           t.order_id as ticket_order_id
    FROM invoices i
    LEFT JOIN tickets t ON t.id = i.ticket_id
    WHERE i.id = ?
  `).get(invoiceId) as {
    id: number; order_id: string; ticket_id: number | null;
    total: number; amount_paid: number; status: string;
    ticket_order_id: string | null;
  } | undefined;

  if (!invoice) {
    throw new AppError('Invoice not found', 404);
  }
  if (invoice.status === 'void') {
    throw new AppError('Cannot process payment on a voided invoice', 400);
  }
  if (invoice.status === 'paid') {
    throw new AppError('Invoice is already fully paid', 400);
  }

  const amountDue = invoice.total - invoice.amount_paid;
  if (amountDue <= 0) {
    throw new AppError('No balance due on this invoice', 400);
  }

  const tipAmount = tip && typeof tip === 'number' && tip > 0 ? tip : 0;
  const chargeAmount = amountDue + tipAmount;
  const ticketRef = invoice.ticket_order_id || invoice.order_id;

  const result = await processPayment(db, chargeAmount, ticketRef, tipAmount > 0 ? tipAmount : undefined);

  if (result.success) {
    // Record payment, update invoice, and auto-close ticket atomically
    const userId = req.user!.id;

    const recordPayment = db.transaction(() => {
      db.prepare(`
        INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id,
          processor_transaction_id, processor_response, signature_file, notes, user_id, created_at, updated_at)
        VALUES (?, ?, 'BlockChyp', ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
      `).run(
        invoice.id,
        chargeAmount,
        result.cardType ? `${result.cardType} ending ${result.last4}` : 'Card',
        result.transactionId ?? null,
        result.transactionId ?? null,
        result.receiptSuggestions ? JSON.stringify(result.receiptSuggestions) : null,
        result.signatureFile ?? null,
        result.authCode ? `Auth: ${result.authCode}` : null,
        userId,
      );

      // Update invoice status
      const newPaid = invoice.amount_paid + chargeAmount;
      const newStatus = newPaid >= invoice.total ? 'paid' : 'partial';
      const newDue = Math.max(0, invoice.total - newPaid);

      db.prepare('UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime(\'now\') WHERE id = ?')
        .run(newPaid, newDue, newStatus, invoice.id);

      // Auto-close ticket if configured
      const cfg = getBlockChypConfig(db);
      if (cfg.autoCloseTicket && invoice.ticket_id && newStatus === 'paid') {
        const closedStatus = db.prepare("SELECT id FROM ticket_statuses WHERE name LIKE '%closed%' OR name LIKE '%picked up%' ORDER BY is_closed DESC LIMIT 1")
          .get() as { id: number } | undefined;
        if (closedStatus) {
          db.prepare('UPDATE tickets SET status_id = ?, updated_at = datetime(\'now\') WHERE id = ?')
            .run(closedStatus.id, invoice.ticket_id);
        }
      }
    });
    recordPayment();
  }

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
