/**
 * Ticket Signature + Waiver Capture Routes (SCAN-465, android §4.14)
 *
 * Mount point : /api/v1/tickets/:ticketId/signatures
 * Auth        : authMiddleware applied at parent mount — do NOT re-add here.
 * Role gate   : any authenticated user may capture (staff holds device while
 *               customer signs on-screen); DELETE is admin-only.
 *
 * Security notes:
 *   - signature_data_url: must start with data:image/png;base64, or
 *     data:image/jpeg;base64,  and must not exceed 500 000 chars (≈375 KB of
 *     raw image data). The limit matches the brief (500 KB base64 budget).
 *   - ip_address sourced from req.socket.remoteAddress (SCAN-194 compliant,
 *     not req.ip which can be spoofed via X-Forwarded-For).
 *   - user_agent capped at 500 chars to prevent log-stuffing.
 *   - Rate limit: 30 captures/min per user (consumeWindowRate).
 *   - All captures and deletes are audited.
 *   - Integer IDs validated before any SQL.
 *   - All SQL uses parameterised statements (no interpolation).
 */

import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router({ mergeParams: true });

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SIG_RATE_CATEGORY = 'ticket_signature_capture';
const SIG_RATE_MAX = 30;
const SIG_RATE_WINDOW_MS = 60_000; // 30 per minute per user

const ALLOWED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/jpeg;base64,',
] as const;

const MAX_DATA_URL_LENGTH = 500_000; // chars — enforces ~375 KB image budget
const MAX_SIGNER_NAME_LEN = 200;
const MAX_WAIVER_TEXT_LEN = 10_000;
const MAX_WAIVER_VERSION_LEN = 50;
const MAX_USER_AGENT_LEN = 500;

const ALLOWED_SIGNATURE_KINDS = ['check_in', 'check_out', 'waiver', 'payment'] as const;
type SignatureKind = (typeof ALLOWED_SIGNATURE_KINDS)[number];

const ALLOWED_SIGNER_ROLES = ['customer', 'technician', 'manager'] as const;
type SignerRole = (typeof ALLOWED_SIGNER_ROLES)[number];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseTicketId(raw: unknown): number {
  const id = parseInt(String(raw ?? ''), 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid ticket ID', 400);
  return id;
}

function parseSignatureId(raw: unknown): number {
  const id = parseInt(String(raw ?? ''), 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid signature ID', 400);
  return id;
}

function validateDataUrl(value: unknown): string {
  if (typeof value !== 'string') throw new AppError('signature_data_url is required', 400);
  const hasValidPrefix = ALLOWED_DATA_URL_PREFIXES.some((p) => value.startsWith(p));
  if (!hasValidPrefix) {
    throw new AppError(
      'signature_data_url must start with data:image/png;base64, or data:image/jpeg;base64,',
      400,
    );
  }
  if (value.length > MAX_DATA_URL_LENGTH) {
    throw new AppError(
      `signature_data_url exceeds maximum length of ${MAX_DATA_URL_LENGTH} characters (≈375 KB)`,
      400,
    );
  }
  return value;
}

function validateSignatureKind(value: unknown): SignatureKind {
  if (!ALLOWED_SIGNATURE_KINDS.includes(value as SignatureKind)) {
    throw new AppError(
      `signature_kind must be one of: ${ALLOWED_SIGNATURE_KINDS.join(', ')}`,
      400,
    );
  }
  return value as SignatureKind;
}

function validateSignerRole(value: unknown): SignerRole | null {
  if (value === undefined || value === null || value === '') return null;
  if (!ALLOWED_SIGNER_ROLES.includes(value as SignerRole)) {
    throw new AppError(
      `signer_role must be one of: ${ALLOWED_SIGNER_ROLES.join(', ')}`,
      400,
    );
  }
  return value as SignerRole;
}

function validateStringField(
  value: unknown,
  fieldName: string,
  maxLen: number,
  required: true,
): string;
function validateStringField(
  value: unknown,
  fieldName: string,
  maxLen: number,
  required: false,
): string | null;
function validateStringField(
  value: unknown,
  fieldName: string,
  maxLen: number,
  required: boolean,
): string | null {
  if (value === undefined || value === null || value === '') {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const trimmed = value.trim();
  if (required && trimmed.length === 0) throw new AppError(`${fieldName} is required`, 400);
  if (trimmed.length > maxLen) {
    throw new AppError(`${fieldName} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed || null;
}

function requireAdminOrManager(req: any): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

// ---------------------------------------------------------------------------
// GET / — list all signatures for a ticket
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const ticketId = parseTicketId(req.params.ticketId);

    // Verify the ticket exists (gives a clean 404 rather than an empty list
    // that could mislead clients querying a non-existent ticket).
    const ticket = await adb.get<{ id: number }>(
      'SELECT id FROM tickets WHERE id = ?',
      ticketId,
    );
    if (!ticket) throw new AppError('Ticket not found', 404);

    const rows = await adb.all(
      `SELECT id, ticket_id, signature_kind, signer_name, signer_role,
              waiver_version, captured_by_user_id, captured_at, ip_address
         FROM ticket_signatures
        WHERE ticket_id = ?
        ORDER BY captured_at ASC`,
      ticketId,
    );

    // NOTE: signature_data_url is intentionally excluded from the list view
    // to keep payloads small. Clients should fetch the detail endpoint when
    // they need the actual image data.
    res.json({ success: true, data: rows });
  }),
);

// ---------------------------------------------------------------------------
// POST / — capture a new signature
// ---------------------------------------------------------------------------

router.post(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ticketId = parseTicketId(req.params.ticketId);

    // Rate-limit: 30 captures per user per minute.
    const rl = consumeWindowRate(db, SIG_RATE_CATEGORY, String(userId), SIG_RATE_MAX, SIG_RATE_WINDOW_MS);
    if (!rl.allowed) {
      throw new AppError(
        `Too many signature captures. Retry after ${rl.retryAfterSeconds}s.`,
        429,
      );
    }

    // Validate body.
    const signatureKind = validateSignatureKind(req.body?.signature_kind);
    const signerName = validateStringField(req.body?.signer_name, 'signer_name', MAX_SIGNER_NAME_LEN, true)!;
    const signerRole = validateSignerRole(req.body?.signer_role);
    const signatureDataUrl = validateDataUrl(req.body?.signature_data_url);
    const waiverText = validateStringField(req.body?.waiver_text, 'waiver_text', MAX_WAIVER_TEXT_LEN, false);
    const waiverVersion = validateStringField(req.body?.waiver_version, 'waiver_version', MAX_WAIVER_VERSION_LEN, false);

    // IP: SCAN-194 requires socket address, not req.ip (proxy-injectable).
    const ipAddress = (req.socket?.remoteAddress ?? null);
    // user_agent: cap to prevent log-stuffing.
    const rawUa = req.headers['user-agent'];
    const userAgent = typeof rawUa === 'string' ? rawUa.slice(0, MAX_USER_AGENT_LEN) : null;

    // Verify the ticket exists.
    const ticket = await adb.get<{ id: number }>(
      'SELECT id FROM tickets WHERE id = ?',
      ticketId,
    );
    if (!ticket) throw new AppError('Ticket not found', 404);

    const result = await adb.run(
      `INSERT INTO ticket_signatures
         (ticket_id, signature_kind, signer_name, signer_role,
          signature_data_url, waiver_text, waiver_version,
          captured_by_user_id, ip_address, user_agent)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ticketId,
      signatureKind,
      signerName,
      signerRole,
      signatureDataUrl,
      waiverText,
      waiverVersion,
      userId,
      ipAddress,
      userAgent,
    );

    const newId = Number(result.lastInsertRowid);

    audit(db, 'ticket_signature_captured', userId, ipAddress ?? 'unknown', {
      signature_id: newId,
      ticket_id: ticketId,
      signature_kind: signatureKind,
      signer_name: signerName,
      signer_role: signerRole,
    });

    const row = await adb.get(
      `SELECT id, ticket_id, signature_kind, signer_name, signer_role,
              waiver_version, captured_by_user_id, captured_at, ip_address
         FROM ticket_signatures WHERE id = ?`,
      newId,
    );

    res.status(201).json({ success: true, data: row });
  }),
);

// ---------------------------------------------------------------------------
// GET /:signatureId — retrieve a single signature (includes data URL)
// ---------------------------------------------------------------------------

router.get(
  '/:signatureId',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const ticketId = parseTicketId(req.params.ticketId);
    const signatureId = parseSignatureId(req.params.signatureId);

    const row = await adb.get(
      `SELECT * FROM ticket_signatures WHERE id = ? AND ticket_id = ?`,
      signatureId,
      ticketId,
    );
    if (!row) throw new AppError('Signature not found', 404);

    res.json({ success: true, data: row });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:signatureId — hard-delete (admin/manager only); audited
// ---------------------------------------------------------------------------

router.delete(
  '/:signatureId',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);

    const db = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ticketId = parseTicketId(req.params.ticketId);
    const signatureId = parseSignatureId(req.params.signatureId);
    const ipAddress = req.socket?.remoteAddress ?? 'unknown';

    const existing = await adb.get<{ id: number; signature_kind: string }>(
      `SELECT id, signature_kind FROM ticket_signatures WHERE id = ? AND ticket_id = ?`,
      signatureId,
      ticketId,
    );
    if (!existing) throw new AppError('Signature not found', 404);

    await adb.run(
      `DELETE FROM ticket_signatures WHERE id = ?`,
      signatureId,
    );

    audit(db, 'ticket_signature_deleted', userId, ipAddress, {
      signature_id: signatureId,
      ticket_id: ticketId,
      signature_kind: existing.signature_kind,
    });

    res.json({ success: true, data: { id: signatureId } });
  }),
);

export default router;
