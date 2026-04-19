import * as BlockChyp from '@blockchyp/blockchyp-ts';
import axiosLib from 'axios';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';
import { getConfigValue } from '../utils/configEncryption.js';
import { allocateCounter } from '../utils/counters.js';
import { createLogger } from '../utils/logger.js';
import { createBreaker } from '../utils/circuitBreaker.js';

const logger = createLogger('blockchyp');

// SEC-H77: Circuit breaker for BlockChyp terminal/gateway calls.
const blockchypBreaker = createBreaker('blockchyp');

// SEC-H110: Block redirect-smuggling. The BlockChyp SDK calls the global
// axios(config) directly (not axios.create), so we harden the global default.
// maxRedirects: 0 causes axios to throw on any 3xx rather than follow it,
// preventing an attacker-controlled redirect from leaking HMAC credentials
// to a third-party host in the Location header.
axiosLib.defaults.maxRedirects = 0;

// ─── Config helpers ────────────────────────────────────────────────

interface BlockChypConfig {
  enabled: boolean;
  apiKey: string;
  bearerToken: string;
  signingKey: string;
  terminalName: string;
  testMode: boolean;
  tcEnabled: boolean;
  tcContent: string;
  tcName: string;
  promptForTip: boolean;
  sigRequiredPayment: boolean;
  sigFormat: 'png' | 'jpg';
  sigWidth: number;
  autoCloseTicket: boolean;
}

export function getBlockChypConfig(db: any): BlockChypConfig {
  return {
    enabled: getConfigValue(db, 'blockchyp_enabled') === 'true',
    apiKey: getConfigValue(db, 'blockchyp_api_key') || '',
    bearerToken: getConfigValue(db, 'blockchyp_bearer_token') || '',
    signingKey: getConfigValue(db, 'blockchyp_signing_key') || '',
    terminalName: getConfigValue(db, 'blockchyp_terminal_name') || 'Front Counter',
    testMode: getConfigValue(db, 'blockchyp_test_mode') === 'true',
    tcEnabled: getConfigValue(db, 'blockchyp_tc_enabled') === 'true',
    tcContent: getConfigValue(db, 'blockchyp_tc_content') || 'I authorize this repair shop to perform diagnostic and repair services on my device.',
    tcName: getConfigValue(db, 'blockchyp_tc_name') || 'Repair Agreement',
    promptForTip: getConfigValue(db, 'blockchyp_prompt_for_tip') === 'true',
    sigRequiredPayment: getConfigValue(db, 'blockchyp_sig_required_payment') === 'true',
    sigFormat: (getConfigValue(db, 'blockchyp_sig_format') as 'png' | 'jpg') || 'png',
    sigWidth: parseInt(getConfigValue(db, 'blockchyp_sig_width') || '400', 10),
    autoCloseTicket: getConfigValue(db, 'blockchyp_auto_close_ticket') === 'true',
  };
}

export function isBlockChypEnabled(db: any): boolean {
  const cfg = getBlockChypConfig(db);
  return cfg.enabled && !!cfg.apiKey && !!cfg.bearerToken && !!cfg.signingKey;
}

// ─── Client management ─────────────────────────────────────────────

const CLIENT_TTL_MS = 5 * 60 * 1000; // 5 minutes

type BlockChypClientInstance = ReturnType<typeof BlockChyp.newClient>;
const clientCache = new Map<string, { client: BlockChypClientInstance; createdAt: number }>();

function credentialsHash(cfg: BlockChypConfig): string {
  return `${cfg.apiKey}|${cfg.bearerToken}|${cfg.signingKey}|${cfg.testMode}`;
}

/**
 * SEC-M39: Callers that have already snapshotted the BlockChyp config (e.g.
 * to lock down test-mode across a transaction) should pass the snapshot in
 * via `cfgSnapshot` so we don't re-read the DB — a second read opens a
 * window where a settings flip between snapshot and client-fetch could
 * route a live charge to sandbox (or vice versa). Callers without a
 * snapshot (one-off calls) can still pass nothing and we'll fetch fresh.
 */
export function getClient(db: any, cfgSnapshot?: BlockChypConfig): BlockChypClientInstance {
  const cfg = cfgSnapshot ?? getBlockChypConfig(db);
  if (!cfg.apiKey || !cfg.bearerToken || !cfg.signingKey) {
    throw new Error('BlockChyp credentials not configured. Set API Key, Bearer Token, and Signing Key in Settings.');
  }

  const hash = credentialsHash(cfg);
  const now = Date.now();
  const cached = clientCache.get(hash);
  if (cached && (now - cached.createdAt) < CLIENT_TTL_MS) {
    return cached.client;
  }

  const client = BlockChyp.newClient({
    apiKey: cfg.apiKey,
    bearerToken: cfg.bearerToken,
    signingKey: cfg.signingKey,
  });

  // SEC-H74: cap gateway (remote API) calls at 15s. gatewayTimeout is private
  // on the SDK class but settable at runtime — same pattern used above for
  // cloudRelay. terminalTimeout is intentionally left at the SDK default (120s)
  // because physical terminal interactions (card tap, signature) can take longer.
  // The SDK stores this value in seconds; it multiplies by 1000 before passing
  // to axios, so 15 here → 15_000 ms on the wire.
  (client as any).gatewayTimeout = 15;

  if (cfg.testMode) {
    // SDK bug: _resolveTerminalRoute doesn't pass the request to _assembleGatewayUrl,
    // so it always uses gatewayHost (production) even when request.test = true.
    client.setGatewayHost('https://test.blockchyp.com');

    // Sandbox has no physical terminal, so route resolution returns empty ipAddress
    // causing "Invalid URL" (https://:8443/...). Force cloud relay to skip terminal routing.
    // WARNING: This uses an undocumented SDK internal. If a BlockChyp SDK update breaks
    // test-mode payments, check whether this property was renamed or removed.
    if ('cloudRelay' in client || typeof (client as any).cloudRelay !== 'undefined') {
      (client as any).cloudRelay = true;
    } else {
      console.warn('[BlockChyp] SDK may have changed — cloudRelay property not found. Test mode terminal routing may fail.');
      (client as any).cloudRelay = true; // Try anyway
    }
  }

  clientCache.set(hash, { client, createdAt: now });
  return client;
}

export function refreshClient(): void {
  clientCache.clear();
}

// ─── Signature file saving ─────────────────────────────────────────

export interface SavedSignature {
  filename: string;
  absolutePath: string;
}

function saveSignatureFile(sigFileHex: string, format: string): SavedSignature {
  const buffer = Buffer.from(sigFileHex, 'hex');
  const ext = format === 'jpg' ? '.jpg' : '.png';
  const filename = `sig-${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
  const absolutePath = path.join(config.uploadsPath, filename);
  fs.writeFileSync(absolutePath, buffer);
  return { filename, absolutePath };
}

/**
 * BL8: delete a previously saved signature file by its absolute path.
 * Used when a payment is voided / refunded so orphan signatures don't pile up.
 * Never throws — cleanup failures are logged and swallowed (no audit impact).
 */
export function deleteSignatureFile(absolutePath: string | null | undefined): boolean {
  if (!absolutePath) return false;
  try {
    // Guardrail: only delete files inside the configured uploadsPath.
    const normalized = path.resolve(absolutePath);
    const uploadsRoot = path.resolve(config.uploadsPath);
    if (!normalized.startsWith(uploadsRoot + path.sep) && normalized !== uploadsRoot) {
      logger.warn('Refusing to delete signature file outside uploads root', { absolutePath });
      return false;
    }
    if (fs.existsSync(normalized)) {
      fs.unlinkSync(normalized);
      return true;
    }
  } catch (err: unknown) {
    logger.error('Failed to delete signature file', {
      absolutePath,
      error: err instanceof Error ? err.message : String(err),
    });
  }
  return false;
}

// ─── Public API methods ────────────────────────────────────────────

export interface TestConnectionResult {
  success: boolean;
  terminalName: string;
  firmwareVersion?: string;
  error?: string;
}

export async function testConnection(db: any, terminalNameOverride?: string): Promise<TestConnectionResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);
  const terminalName = terminalNameOverride || cfg.terminalName;

  try {
    const request = new BlockChyp.PingRequest();
    request.terminalName = terminalName;
    request.test = cfg.testMode;

    const response = await blockchypBreaker.run(() => client.ping(request));
    const data = response.data;

    return {
      success: !!data.success,
      terminalName,
      firmwareVersion: (data as any).firmwareVersion ?? undefined,
      error: data.success ? undefined : (data.error ?? 'Unknown error'),
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Connection failed';
    return { success: false, terminalName, error: message };
  }
}

export interface CaptureSignatureResult {
  success: boolean;
  signatureFile?: string;
  signatureFilePath?: string;
  transactionId?: string;
  error?: string;
}

export async function capturePreTicketSignature(db: any): Promise<CaptureSignatureResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.TermsAndConditionsRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.tcAlias = null;
    request.tcName = cfg.tcName;
    request.tcContent = cfg.tcContent;
    request.sigFormat = cfg.sigFormat as "" | "png" | "jpg" | "gif";
    request.sigWidth = cfg.sigWidth;
    request.sigRequired = true;
    request.transactionRef = buildUniqueTransactionRef(db, 'checkin-pre');

    const response = await blockchypBreaker.run(() =>
      client.termsAndConditions(request),
    );
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Customer declined or terminal error' };
    }

    let signatureFile: string | undefined;
    let signatureFilePath: string | undefined;
    if (data.sigFile) {
      const saved = saveSignatureFile(data.sigFile, cfg.sigFormat);
      signatureFile = saved.filename;
      signatureFilePath = saved.absolutePath;
    }

    return {
      success: true,
      signatureFile,
      signatureFilePath,
      transactionId: data.transactionId ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

export async function captureCheckInSignature(db: any, ticketOrderId: string): Promise<CaptureSignatureResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.TermsAndConditionsRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.tcAlias = null;
    request.tcName = cfg.tcName;
    request.tcContent = cfg.tcContent;
    request.sigFormat = cfg.sigFormat as "" | "png" | "jpg" | "gif";
    request.sigWidth = cfg.sigWidth;
    request.sigRequired = true;
    request.transactionRef = buildUniqueTransactionRef(db, `checkin-${ticketOrderId}`);

    const response = await blockchypBreaker.run(() =>
      client.termsAndConditions(request),
    );
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Customer declined or terminal error' };
    }

    let signatureFile: string | undefined;
    let signatureFilePath: string | undefined;
    if (data.sigFile) {
      const saved = saveSignatureFile(data.sigFile, cfg.sigFormat);
      signatureFile = saved.filename;
      signatureFilePath = saved.absolutePath;
    }

    return {
      success: true,
      signatureFile,
      signatureFilePath,
      transactionId: data.transactionId ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

export interface ProcessPaymentResult {
  success: boolean;
  transactionId?: string;
  authCode?: string;
  amount?: string;
  cardType?: string;
  last4?: string;
  signatureFile?: string;
  signatureFilePath?: string;
  transactionRef?: string;
  testMode?: boolean;
  receiptSuggestions?: Record<string, unknown>;
  error?: string;
  responseDescription?: string;
}

/**
 * BL6: Generate a transaction ref that is GUARANTEED unique per call.
 *
 * The original code used `payment-${ticketOrderId}-${Date.now()}`, which
 * collapses to an identical string if two charges land in the same millisecond
 * (common on double-click, retry-on-network-blip, or two users behind the same
 * terminal). BlockChyp treats identical transactionRefs as idempotency keys
 * and can approve the second charge against the first's record — a double
 * charge from the customer's perspective.
 *
 * Fix: combine (prefix, allocateCounter, 8 random bytes). The counter makes
 * the ref monotonic across concurrent requests; the random bytes harden it
 * against counter-table corruption or clock skew between nodes.
 */
function buildUniqueTransactionRef(db: any, prefix: string): string {
  const seq = allocateCounter(db, 'blockchyp_transaction_ref');
  const rand = crypto.randomBytes(8).toString('hex');
  return `${prefix}-${seq}-${rand}`;
}

export async function processPayment(
  db: any,
  amount: number,
  ticketOrderId: string,
  tip?: number,
): Promise<ProcessPaymentResult> {
  // BL10: Snapshot config ONCE at the start of the transaction. The old code
  // called getBlockChypConfig twice (once here, once implicitly through
  // getClient). A settings flip between those two reads could route a live
  // charge to sandbox (or vice-versa). We read all fields once, derive a
  // typed snapshot, and pass that snapshot to the rest of the call.
  const cfgSnapshot = getBlockChypConfig(db);
  const lockedTestMode = cfgSnapshot.testMode;

  // The client cache key already incorporates testMode (see credentialsHash),
  // so getClient returns a client keyed against THIS snapshot. We also pass
  // the pre-snapshotted config into getClient so it doesn't re-read the DB
  // (SEC-M39) — a second read would open a small window for a settings flip
  // to change the client's underlying testMode between snapshot and dispatch.
  const client = getClient(db, cfgSnapshot);
  const transactionRef = buildUniqueTransactionRef(db, `payment-${ticketOrderId}`);

  // BL10: Re-read just before firing the request. If the flag flipped, log
  // a critical error and refuse to proceed. Better to fail loud than to
  // silently route a live charge to sandbox.
  const cfgCheck = getBlockChypConfig(db);
  if (cfgCheck.testMode !== lockedTestMode) {
    logger.error('CRITICAL: BlockChyp test-mode flipped mid-transaction; aborting charge', {
      transactionRef,
      ticketOrderId,
      lockedTestMode,
      liveTestMode: cfgCheck.testMode,
    });
    return {
      success: false,
      transactionRef,
      testMode: lockedTestMode,
      error: 'Terminal configuration changed during transaction. Please retry.',
    };
  }

  try {
    const request = new BlockChyp.AuthorizationRequest();
    request.terminalName = cfgSnapshot.terminalName;
    request.test = lockedTestMode;
    request.amount = amount.toFixed(2);
    request.transactionRef = transactionRef;
    request.description = `Ticket ${ticketOrderId}`;

    if (tip && tip > 0) {
      request.tipAmount = tip.toFixed(2);
    }
    if (cfgSnapshot.promptForTip) {
      request.promptForTip = true;
    }
    if (!cfgSnapshot.sigRequiredPayment) {
      request.disableSignature = true;
    }
    request.sigFormat = cfgSnapshot.sigFormat as "" | "png" | "jpg" | "gif";
    request.sigWidth = cfgSnapshot.sigWidth;

    const response = await blockchypBreaker.run(() => client.charge(request));
    const data = response.data;

    if (!data.approved) {
      return {
        success: false,
        transactionRef,
        testMode: lockedTestMode,
        error: data.responseDescription ?? 'Payment declined',
        responseDescription: data.responseDescription ?? undefined,
      };
    }

    let signatureFile: string | undefined;
    let signatureFilePath: string | undefined;
    if (data.sigFile) {
      const saved = saveSignatureFile(data.sigFile, cfgSnapshot.sigFormat);
      signatureFile = saved.filename;
      signatureFilePath = saved.absolutePath;
    }

    return {
      success: true,
      transactionId: data.transactionId ?? undefined,
      authCode: data.authCode ?? undefined,
      amount: data.authorizedAmount ?? undefined,
      cardType: data.paymentType ?? undefined,
      last4: data.maskedPan?.slice(-4) ?? undefined,
      signatureFile,
      signatureFilePath,
      transactionRef,
      testMode: lockedTestMode,
      receiptSuggestions: data.receiptSuggestions as unknown as Record<string, unknown> | undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    logger.error('BlockChyp charge failed', { transactionRef, ticketOrderId, error: message });
    return {
      success: false,
      transactionRef,
      testMode: lockedTestMode,
      error: message,
    };
  }
}

// ─── BL9: Tip adjustment (post-signature) ─────────────────────────
//
// The BlockChyp TS SDK as shipped at this time does not expose an adjustTip
// or updateTransaction endpoint. Restaurant-style "tip after signature" flows
// therefore are not natively supported. This helper is called by the route
// and returns NOT_SUPPORTED until SDK support lands. When BlockChyp ships a
// tipAdjust API, replace the body with the real call. The route contract
// is stable so frontends can rely on the shape.
export interface AdjustTipResult {
  success: boolean;
  code?: 'NOT_SUPPORTED' | 'INVALID_INPUT' | 'TERMINAL_ERROR';
  error?: string;
  transactionId?: string;
  newTip?: number;
}

export async function adjustTip(
  _db: any,
  transactionId: string,
  newTip: number,
): Promise<AdjustTipResult> {
  if (!transactionId) {
    return { success: false, code: 'INVALID_INPUT', error: 'transaction_id is required' };
  }
  if (typeof newTip !== 'number' || !isFinite(newTip) || newTip < 0) {
    return { success: false, code: 'INVALID_INPUT', error: 'new_tip must be a non-negative number' };
  }

  // SDK capability probe. If a future BlockChyp SDK adds tip adjustment,
  // call it here and return { success: true, transactionId, newTip }.
  logger.warn('Tip adjustment requested but SDK has no adjustTip endpoint', {
    transactionId,
    newTip,
  });
  return {
    success: false,
    code: 'NOT_SUPPORTED',
    error: 'Tip adjustment is not supported by the current BlockChyp SDK. Void and re-charge.',
    transactionId,
    newTip,
  };
}

// ─── Membership: Card Enrollment (tokenization) ───────────────────

export interface EnrollResult {
  success: boolean;
  token?: string;
  maskedPan?: string;
  cardType?: string;
  error?: string;
}

/**
 * Enroll a card on the terminal for recurring billing.
 * Presents the card capture screen, tokenizes the card, returns a token for future charges.
 */
export async function enrollCard(db: any): Promise<EnrollResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.EnrollRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    // BL13: same uniqueness fix as BL6. Two rapid enrollments in the same
    // millisecond (retry-on-network-blip, double-click) previously shared a
    // transactionRef and BlockChyp's idempotency rules would collapse the
    // second into the first, hiding a duplicate card attempt.
    request.transactionRef = buildUniqueTransactionRef(db, 'enroll');

    const response = await blockchypBreaker.run(() => client.enroll(request));
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Card enrollment failed' };
    }

    return {
      success: true,
      token: data.token ?? undefined,
      maskedPan: data.maskedPan ?? undefined,
      cardType: data.paymentType ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

// ─── Membership: Token-based charge (recurring billing) ───────────

export interface TokenChargeResult {
  success: boolean;
  transactionId?: string;
  authCode?: string;
  amount?: string;
  error?: string;
}

/**
 * Charge a previously tokenized card (for monthly membership renewal).
 * No terminal interaction — runs server-side via BlockChyp gateway.
 */
export async function chargeToken(db: any, token: string, amount: string, description: string): Promise<TokenChargeResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.AuthorizationRequest();
    request.token = token;
    request.amount = amount;
    request.test = cfg.testMode;
    request.description = description;
    // BL13: uniqueness fix — `membership-${Date.now()}` collapses under
    // concurrent renewals. The dispatcher parallelises up to N renewals per
    // tick, so two memberships hitting the same epoch ms is not hypothetical.
    request.transactionRef = buildUniqueTransactionRef(db, 'membership');

    const response = await blockchypBreaker.run(() => client.charge(request));
    const data = response.data;

    if (!data.approved) {
      return { success: false, error: data.responseDescription ?? 'Payment declined' };
    }

    return {
      success: true,
      transactionId: data.transactionId ?? undefined,
      authCode: data.authCode ?? undefined,
      amount: data.authorizedAmount ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Payment processing failed';
    return { success: false, error: message };
  }
}

// ─── Membership: Payment Link (for remote signup) ─────────────────

export interface PaymentLinkResult {
  success: boolean;
  linkUrl?: string;
  linkCode?: string;
  error?: string;
}

/**
 * Create a BlockChyp payment link for remote membership signup.
 * Customer receives a link (via SMS/email/QR code) to enter card details.
 */
export async function createPaymentLink(db: any, amount: string, description: string, callbackUrl?: string): Promise<PaymentLinkResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.PaymentLinkRequest();
    request.amount = amount;
    request.description = description;
    request.test = cfg.testMode;
    request.autoSend = false; // We send the link ourselves via SMS
    // BL13: uniqueness fix — Date.now() collides under concurrent admin SMS
    // sends. BlockChyp's link table treats transactionRef as an idempotency
    // key; collapsing two sends into one silently drops the second link.
    request.transactionRef = buildUniqueTransactionRef(db, 'membership-link');
    if (callbackUrl) {
      request.callbackUrl = callbackUrl;
    }
    request.enroll = true; // Tokenize the card for recurring

    const response = await blockchypBreaker.run(() =>
      client.sendPaymentLink(request),
    );
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Failed to create payment link' };
    }

    return {
      success: true,
      linkUrl: data.url ?? undefined,
      linkCode: data.linkCode ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to create payment link';
    return { success: false, error: message };
  }
}

// ─── SEC-M42: payment_idempotency janitor ─────────────────────────
//
// The `payment_idempotency` table (migration 080) gates duplicate charge
// attempts via a `pending` row that is supposed to flip to `completed`
// or `failed` once the BlockChyp call returns. If the server crashes (or
// a network blip kills the process) between INSERT and the final UPDATE,
// the row is stuck `pending` forever. The UNIQUE (invoice_id, client_request_id)
// index then rejects legitimate retries with 409 — the customer can't pay.
//
// The janitor flips rows older than the threshold from `pending` → `failed`
// so the client can retry with a new idempotency key. 5 minutes is a
// generous ceiling for a BlockChyp round-trip; anything still `pending`
// past that is almost certainly orphaned.
const STUCK_PENDING_THRESHOLD_MINUTES = 5;

/**
 * Sweep stuck-pending payment_idempotency rows in the given DB. Returns the
 * number of rows fixed. Designed to be called from a cron — safe to invoke
 * on a schema that does not yet have the table (pre-migration tenants),
 * and errors are swallowed with a log line because the janitor must never
 * crash the cron loop.
 */
export function sweepStuckPaymentIdempotency(db: any): number {
  try {
    const result = db
      .prepare(
        `UPDATE payment_idempotency
            SET status = 'failed',
                error_message = COALESCE(error_message, 'Janitor: stuck pending > ${STUCK_PENDING_THRESHOLD_MINUTES} min'),
                updated_at = datetime('now')
          WHERE status = 'pending'
            AND created_at < datetime('now', '-${STUCK_PENDING_THRESHOLD_MINUTES} minutes')`,
      )
      .run();
    const changes = Number(result?.changes ?? 0);
    if (changes > 0) {
      logger.warn('Flipped stuck payment_idempotency rows to failed', { changes });
    }
    return changes;
  } catch (err: unknown) {
    // Older tenants may not have run migration 080 yet; "no such table" is
    // expected and fine to swallow. Log other errors so they surface.
    const message = err instanceof Error ? err.message : String(err);
    if (!/no such table/i.test(message)) {
      logger.error('payment_idempotency janitor failed', { error: message });
    }
    return 0;
  }
}
