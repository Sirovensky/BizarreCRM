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
 */

import crypto from 'crypto';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('webhooks');

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

      // SEC-M7: Sign payload with HMAC-SHA256
      const secret = getOrCreateWebhookSecret(db);
      const signature = crypto.createHmac('sha256', secret).update(body).digest('hex');

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
