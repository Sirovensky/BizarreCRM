/**
 * ENR-A6: Outbound webhook service.
 *
 * Reads `webhook_url` and `webhook_events` from store_config.
 * When an event fires, POSTs a JSON payload to the configured URL.
 *
 * SEC-M7: Payloads are signed with HMAC-SHA256 using a per-tenant webhook_secret.
 * The secret is auto-generated on first use and stored encrypted via configEncryption.
 *
 * L7 (criticalaudit.md §1): fireWebhook was previously fire-and-forget with a
 * 5s timeout and no retry. Now:
 *   - 10s HTTP timeout via AbortController per attempt
 *   - Exponential retry (3 attempts with 0s / 2s / 8s backoff)
 *   - On final failure, the event payload is persisted to
 *     `webhook_delivery_failures` (migration 082) so it becomes a
 *     visible dead-letter entry instead of a stdout log line
 *   - Each attempt and the final give-up are reported via logger.error
 *
 * Retries still run asynchronously from the caller's perspective — fireWebhook
 * never awaits the delivery and never throws into the request handler. The
 * caller fires and forgets; this module owns durability.
 *
 * SEC-H92: SSRF guards on every outbound call.
 *   - URL validated: http(s) scheme only, no embedded credentials
 *   - DNS resolved with { all: true } — every returned address checked
 *     against private/reserved ranges before fetch proceeds
 *   - redirect: 'error' on fetch so a redirect from a public host to an
 *     internal address cannot bypass the guard
 *   - SSRF blocks are logged as webhook_ssrf_blocked and never retried
 */

import crypto from 'crypto';
import dns from 'dns';
import net from 'net';
import { createLogger } from '../utils/logger.js';
// assertPublicUrl from ssrfGuard.ts is intentionally NOT imported here.
// SEC-H92 uses the local assertWebhookUrl (below) which tags errors with
// isSsrf: true so deliverWithRetry can skip retries on policy blocks.

const logger = createLogger('webhooks');

// ---------------------------------------------------------------------------
// SEC-H92: Local SSRF IP helpers
//
// isPrivateIp is intentionally duplicated here (instead of re-exported from
// ssrfGuard.ts) so that this file's security invariants are self-contained
// and auditable without following imports.
// ---------------------------------------------------------------------------

/** IPv4 CIDR ranges that must never be webhook targets. */
const PRIVATE_V4_RANGES: ReadonlyArray<readonly [number, number]> = [
  // RFC 1918 — private networks
  [0x0a000000, 0x0affffff], // 10.0.0.0/8
  [0xac100000, 0xac1fffff], // 172.16.0.0/12
  [0xc0a80000, 0xc0a8ffff], // 192.168.0.0/16
  // Loopback
  [0x7f000000, 0x7fffffff], // 127.0.0.0/8
  // Link-local + AWS IMDS (169.254.169.254)
  [0xa9fe0000, 0xa9feffff], // 169.254.0.0/16
  // "This host" / unspecified
  [0x00000000, 0x00ffffff], // 0.0.0.0/8
  // CGNAT
  [0x64400000, 0x647fffff], // 100.64.0.0/10
  // Multicast
  [0xe0000000, 0xefffffff], // 224.0.0.0/4
  // Reserved / broadcast
  [0xf0000000, 0xffffffff], // 240.0.0.0/4
] as const;

function ipv4ToUint(ip: string): number {
  const parts = ip.split('.').map(Number);
  return (((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0);
}

function isPrivateIPv4(ip: string): boolean {
  const n = ipv4ToUint(ip);
  return PRIVATE_V4_RANGES.some(([lo, hi]) => n >= lo && n <= hi);
}

function isPrivateIPv6(ip: string): boolean {
  const norm = ip.toLowerCase();
  if (norm === '::1' || norm === '::') return true;

  // IPv4-mapped ::ffff:x.x.x.x
  const mapped = norm.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isPrivateIPv4(mapped[1]);

  // IPv4-mapped hex form ::ffff:hhhh:hhhh
  const hexMapped = norm.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
  if (hexMapped) {
    const hi = parseInt(hexMapped[1], 16);
    const lo = parseInt(hexMapped[2], 16);
    const octets = `${(hi >> 8) & 0xff}.${hi & 0xff}.${(lo >> 8) & 0xff}.${lo & 0xff}`;
    return isPrivateIPv4(octets);
  }

  // RFC 4193 unique-local fc00::/7 (0xfc or 0xfd prefix)
  if (/^f[cd][0-9a-f]{2}:/.test(norm)) return true;

  // Link-local fe80::/10
  if (/^fe[89ab][0-9a-f]:/.test(norm)) return true;

  return false;
}

/**
 * Returns true when the given IP address (v4 or v6) falls in a private,
 * reserved, or otherwise non-routable range.
 *
 * Covered ranges:
 *   IPv4: 10/8, 172.16/12, 192.168/16 (RFC1918), 127/8 (loopback),
 *         169.254/16 (link-local + AWS IMDS), 0/8, 100.64/10 (CGNAT),
 *         224/4 (multicast), 240/4 (reserved/broadcast)
 *   IPv6: ::1, :: (loopback/unspecified), ::ffff:0:0/96 (IPv4-mapped,
 *         re-checked against v4 rules), fc00::/7 (RFC4193 unique-local),
 *         fe80::/10 (link-local)
 */
export function isPrivateIp(ip: string): boolean {
  const family = net.isIP(ip);
  if (family === 4) return isPrivateIPv4(ip);
  if (family === 6) return isPrivateIPv6(ip);
  return true; // unparseable — treat as blocked
}

/**
 * SEC-H92: Validate a webhook target URL before connecting.
 *
 * Checks (in order):
 *   1. Parseable URL
 *   2. http or https scheme only — rejects file://, ftp://, gopher://, etc.
 *   3. No embedded credentials (user:pass@host) — prevents confused-deputy attacks
 *      where credentials in the URL cause the HTTP client to authenticate to the
 *      internal service using the tenant's stored secret.
 *   4. DNS resolved with { all: true } — every returned address checked against
 *      isPrivateIp; a split-horizon DNS returning one public + one private address
 *      is still rejected.
 *
 * Throws a WebhookSsrfError (tagged with isSsrf: true) so deliverWithRetry
 * can distinguish permanent SSRF blocks from transient network errors.
 */
async function assertWebhookUrl(url: string): Promise<void> {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw Object.assign(new Error(`webhook_ssrf_blocked: invalid URL "${url}"`), { isSsrf: true });
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw Object.assign(
      new Error(`webhook_ssrf_blocked: non-http(s) scheme "${parsed.protocol}"`),
      { isSsrf: true },
    );
  }

  if (parsed.username || parsed.password) {
    throw Object.assign(
      new Error('webhook_ssrf_blocked: embedded credentials in URL'),
      { isSsrf: true },
    );
  }

  const hostname = parsed.hostname;
  if (!hostname) {
    throw Object.assign(new Error('webhook_ssrf_blocked: missing hostname'), { isSsrf: true });
  }

  // If the host is already a numeric literal, skip DNS.
  if (net.isIP(hostname)) {
    if (isPrivateIp(hostname)) {
      throw Object.assign(
        new Error(`webhook_ssrf_blocked: private IP literal "${hostname}"`),
        { isSsrf: true },
      );
    }
    return;
  }

  let addresses: Array<{ address: string; family: number }>;
  try {
    addresses = await dns.promises.lookup(hostname, { all: true });
  } catch (err) {
    throw Object.assign(
      new Error(`webhook_ssrf_blocked: DNS lookup failed for "${hostname}": ${err instanceof Error ? err.message : String(err)}`),
      { isSsrf: true },
    );
  }

  if (addresses.length === 0) {
    throw Object.assign(
      new Error(`webhook_ssrf_blocked: DNS returned no addresses for "${hostname}"`),
      { isSsrf: true },
    );
  }

  for (const { address } of addresses) {
    if (isPrivateIp(address)) {
      throw Object.assign(
        new Error(`webhook_ssrf_blocked: "${hostname}" resolved to private IP "${address}"`),
        { isSsrf: true, resolvedIps: addresses.map((a) => a.address) },
      );
    }
  }
}

type WebhookEvent =
  | 'ticket_created'
  | 'ticket_status_changed'
  | 'invoice_created'
  | 'payment_received';

interface WebhookPayload {
  event: WebhookEvent;
  timestamp: string;
  data: Record<string, unknown>;
}

interface DeliveryAttemptResult {
  ok: boolean;
  status: number | null;
  error: string | null;
  /** True when the failure is an SSRF policy block — must not be retried. */
  isSsrfBlock?: boolean;
}

/** Per-attempt HTTP timeout. */
const ATTEMPT_TIMEOUT_MS = 10_000;

/** Backoff delays between retry attempts. Three total attempts: 0s, 2s, 8s. */
const RETRY_BACKOFF_MS = [0, 2_000, 8_000] as const;

/**
 * Get or create the per-tenant webhook signing secret.
 *
 * SEC-L16: previously read → branch → UPDATE-or-INSERT. Two concurrent
 * webhook deliveries on a first-time tenant could both read row=null,
 * both generate their own 32-byte secret, and race the INSERT — one
 * would succeed, the other would throw on the PRIMARY KEY constraint.
 * Worse, the losing delivery might have already signed its payload with
 * the now-orphaned secret, producing a signature the receiver can't
 * verify with what's in the DB.
 *
 * New path: one `INSERT OR IGNORE` seeds a fresh secret iff the row
 * doesn't yet exist, then re-SELECT returns the winning value. Either
 * every caller sees the same secret or the INSERT is a no-op; no race
 * window, no orphan-signature.
 */
function getOrCreateWebhookSecret(db: any): string {
  // SCAN-1134: previously generated 32 bytes of entropy on every call,
  // even though the INSERT OR IGNORE was a no-op 99% of the time (secret
  // is minted once then reused forever). Read first; only mint + insert
  // when the row is genuinely missing. Race-safety preserved via the
  // INSERT OR IGNORE + re-SELECT pattern on the slow path.
  const existing = db
    .prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'")
    .get() as { value?: string } | undefined;
  if (existing?.value) return existing.value;

  const candidate = crypto.randomBytes(32).toString('hex');
  db.prepare(
    "INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)"
  ).run(candidate);
  const row = db
    .prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'")
    .get() as { value?: string } | undefined;
  return row?.value || candidate;
}

/** Perform a single POST attempt with a bounded timeout. */
async function attemptDelivery(
  url: string,
  body: string,
  signature: string,
  timestamp: string,
): Promise<DeliveryAttemptResult> {
  // SEC-H92: SSRF guard runs before every attempt so DNS-rebinding attacks
  // (where a public name TTLs to a private IP between the first and a retry)
  // are caught on each round. Uses the local assertWebhookUrl which:
  //   • rejects non-http(s) schemes
  //   • rejects embedded credentials (user:pass@host)
  //   • resolves hostname with { all: true } and blocks any private/reserved IP
  // Throws a tagged WebhookSsrfError so deliverWithRetry can skip retries.
  try {
    await assertWebhookUrl(url);
  } catch (err: unknown) {
    const isSsrf = err instanceof Error && (err as NodeJS.ErrnoException & { isSsrf?: boolean }).isSsrf === true;
    const resolvedIps = err instanceof Error ? (err as unknown as Record<string, unknown>)['resolvedIps'] : undefined;
    logger.error('webhook_ssrf_blocked', {
      url,
      resolvedIps,
      reason: err instanceof Error ? err.message : String(err),
    });
    return {
      ok: false,
      status: null,
      error: err instanceof Error ? err.message : 'SSRF guard blocked URL',
      isSsrfBlock: isSsrf,
    };
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), ATTEMPT_TIMEOUT_MS);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Webhook-Signature': `sha256=${signature}`,
        'X-Webhook-Timestamp': timestamp,
      },
      body,
      signal: controller.signal,
      // SEC-H92: Never follow redirects — a 3xx from a public host pointing to
      // an internal address would otherwise bypass the SSRF guard above.
      redirect: 'error',
    });

    // Treat 2xx as success, anything else as a retryable error.
    if (res.ok) {
      return { ok: true, status: res.status, error: null };
    }

    return {
      ok: false,
      status: res.status,
      error: `HTTP ${res.status} ${res.statusText || ''}`.trim(),
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    return { ok: false, status: null, error: msg };
  } finally {
    clearTimeout(timeoutId);
  }
}

/** Persist a failed delivery to the dead-letter table. */
function recordDeliveryFailure(
  db: any,
  endpoint: string,
  event: WebhookEvent,
  payloadBody: string,
  attempts: number,
  lastError: string | null,
  lastStatus: number | null,
): void {
  try {
    db.prepare(
      `INSERT INTO webhook_delivery_failures
         (endpoint, event, payload, attempts, last_error, last_status)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(endpoint, event, payloadBody, attempts, lastError, lastStatus);
  } catch (err: unknown) {
    // The dead-letter INSERT itself failing is a genuine logger.error case —
    // the caller has no way to recover and we don't want to swallow it silently.
    logger.error('Failed to record webhook delivery failure', {
      event,
      endpoint,
      attempts,
      lastError,
      lastStatus,
      insertError: err instanceof Error ? err.message : String(err),
    });
  }
}

/** Sleep helper that resolves after `ms` milliseconds. */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Deliver a webhook with retry + dead-letter semantics.
 *
 * Runs the three attempts back-to-back with exponential backoff. On final
 * failure, inserts a row into `webhook_delivery_failures` and logs an error.
 */
async function deliverWithRetry(
  db: any,
  endpoint: string,
  event: WebhookEvent,
  body: string,
  signature: string,
  timestamp: string,
): Promise<void> {
  let lastError: string | null = null;
  let lastStatus: number | null = null;
  let attempts = 0;

  for (let i = 0; i < RETRY_BACKOFF_MS.length; i += 1) {
    if (RETRY_BACKOFF_MS[i] > 0) {
      await sleep(RETRY_BACKOFF_MS[i]);
    }

    attempts += 1;
    const result = await attemptDelivery(endpoint, body, signature, timestamp);

    if (result.ok) {
      if (attempts > 1) {
        logger.info('Webhook delivered after retry', {
          event,
          endpoint,
          attempts,
          status: result.status,
        });
      }
      return;
    }

    // SEC-H92: SSRF blocks are permanent — the configured URL is policy-invalid.
    // Do not retry (retrying will never help) and do not write to dead-letter
    // (the URL is rejected by policy, not by a transient network condition).
    if (result.isSsrfBlock) {
      // webhook_ssrf_blocked was already logged inside attemptDelivery.
      return;
    }

    lastError = result.error;
    lastStatus = result.status;

    logger.error('Webhook delivery attempt failed', {
      event,
      endpoint,
      attempt: attempts,
      maxAttempts: RETRY_BACKOFF_MS.length,
      status: result.status,
      error: result.error,
    });
  }

  // All retries exhausted — persist to dead-letter queue.
  logger.error('Webhook delivery exhausted retries — writing to dead-letter queue', {
    event,
    endpoint,
    attempts,
    lastStatus,
    lastError,
  });

  recordDeliveryFailure(db, endpoint, event, body, attempts, lastError, lastStatus);
}

/**
 * Fire a webhook for the given event. Non-blocking — the caller is not aware
 * of any failures; they land in the dead-letter table instead.
 */
export function fireWebhook(
  db: any,
  event: WebhookEvent,
  data: Record<string, unknown>,
): void {
  // Run async, fire-and-forget from the caller's perspective.
  (async () => {
    try {
      const urlRow = db
        .prepare("SELECT value FROM store_config WHERE key = 'webhook_url'")
        .get() as { value?: string } | undefined;
      if (!urlRow?.value) return;

      const eventsRow = db
        .prepare("SELECT value FROM store_config WHERE key = 'webhook_events'")
        .get() as { value?: string } | undefined;
      let enabledEvents: string[] = [];
      try {
        enabledEvents = JSON.parse(eventsRow?.value || '[]');
      } catch {
        return; // Invalid JSON — skip
      }

      if (!Array.isArray(enabledEvents) || !enabledEvents.includes(event)) return;

      const payload: WebhookPayload = {
        event,
        timestamp: new Date().toISOString(),
        data,
      };

      const body = JSON.stringify(payload);

      // SEC-M7: Sign payload with HMAC-SHA256.
      // SEC-L31: Bind the X-Webhook-Timestamp header into the signed input —
      // `${timestamp}.${body}` — so a replay attacker can't capture a
      // valid (timestamp, body, signature) triple and resend it with an
      // updated timestamp to trick receivers that honour freshness windows.
      // Legacy signature scheme (body only) is NOT kept — bump is safe
      // because receivers re-derive the signature on each delivery and we
      // issue a new sig every event.
      const secret = getOrCreateWebhookSecret(db);
      const signedInput = `${payload.timestamp}.${body}`;
      const signature = crypto.createHmac('sha256', secret).update(signedInput).digest('hex');

      await deliverWithRetry(db, urlRow.value, event, body, signature, payload.timestamp);
    } catch (err: unknown) {
      // Catches programmer errors (bad DB state, crypto failure, etc.)
      // that happen OUTSIDE the delivery attempt loop. Log with full context
      // so they're never silently swallowed.
      logger.error('Webhook pipeline crashed before delivery', {
        event,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  })();
}

/**
 * Operator-triggered retry of a single dead-lettered webhook delivery. Reads
 * the failure row, reconstructs the signature against the ORIGINAL payload
 * timestamp (so replay-window-enforcing receivers still accept it), makes a
 * single POST attempt, and either deletes the row on success or bumps the
 * attempt counter + last_error/last_status on failure.
 *
 * Only does one attempt — the operator knows they want to retry now, so the
 * multi-attempt exponential backoff of the original pipeline would just
 * make the dashboard feel unresponsive. For a repeated transient failure
 * the row stays in place and can be retried again.
 */
export async function retryDeliveryFailure(
  db: any,
  failureId: number,
): Promise<{ ok: true; status: number | null } | { ok: false; status: number | null; error: string; attempts: number }> {
  const row = db
    .prepare(
      'SELECT id, endpoint, event, payload, attempts FROM webhook_delivery_failures WHERE id = ?',
    )
    .get(failureId) as
    | { id: number; endpoint: string; event: string; payload: string; attempts: number }
    | undefined;

  if (!row) {
    return { ok: false, status: null, error: 'Failure row not found', attempts: 0 };
  }

  // Payload stored in DB is the JSON-serialised WebhookPayload (including the
  // original `timestamp` field). Reuse that timestamp so signature matches
  // anything a receiver cached at original delivery time.
  let timestamp: string;
  try {
    const parsed = JSON.parse(row.payload) as { timestamp?: string };
    if (typeof parsed.timestamp !== 'string') {
      return { ok: false, status: null, error: 'Stored payload missing timestamp', attempts: row.attempts };
    }
    timestamp = parsed.timestamp;
  } catch (err) {
    return {
      ok: false,
      status: null,
      error: 'Stored payload is not valid JSON',
      attempts: row.attempts,
    };
  }

  const secret = getOrCreateWebhookSecret(db);
  const signedInput = `${timestamp}.${row.payload}`;
  const signature = crypto.createHmac('sha256', secret).update(signedInput).digest('hex');

  const result = await attemptDelivery(row.endpoint, row.payload, signature, timestamp);
  const newAttempts = row.attempts + 1;

  if (result.ok) {
    db.prepare('DELETE FROM webhook_delivery_failures WHERE id = ?').run(failureId);
    logger.info('Webhook retry succeeded — row removed from dead-letter queue', {
      failureId,
      event: row.event,
      endpoint: row.endpoint,
      attempts: newAttempts,
      status: result.status,
    });
    return { ok: true, status: result.status };
  }

  // Bump attempts + persist last error so the dashboard shows fresh context.
  db.prepare(
    'UPDATE webhook_delivery_failures SET attempts = ?, last_error = ?, last_status = ? WHERE id = ?',
  ).run(newAttempts, result.error ?? null, result.status ?? null, failureId);

  logger.warn('Webhook retry failed — row still in dead-letter queue', {
    failureId,
    event: row.event,
    endpoint: row.endpoint,
    attempts: newAttempts,
    status: result.status,
    error: result.error,
  });

  return {
    ok: false,
    status: result.status,
    error: result.error ?? 'Delivery failed',
    attempts: newAttempts,
  };
}
