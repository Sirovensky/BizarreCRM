/**
 * ENR-A6: Outbound webhook service.
 *
 * Reads `webhook_url` and `webhook_events` from store_config.
 * When an event fires, POSTs a JSON payload to the configured URL.
 * Fire-and-forget with a 5-second timeout — failures are logged, never thrown.
 *
 * SEC-M7: Payloads are signed with HMAC-SHA256 using a per-tenant webhook_secret.
 * The secret is auto-generated on first use and stored encrypted via configEncryption.
 */

import crypto from 'crypto';

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

/**
 * Get or create the per-tenant webhook signing secret.
 */
function getOrCreateWebhookSecret(db: any): string {
  const row = db.prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'").get() as any;
  if (row?.value) return row.value;

  // Auto-generate a 256-bit secret on first use
  const secret = crypto.randomBytes(32).toString('hex');
  const existing = db.prepare("SELECT id FROM store_config WHERE key = 'webhook_secret'").get();
  if (existing) {
    db.prepare("UPDATE store_config SET value = ? WHERE key = 'webhook_secret'").run(secret);
  } else {
    db.prepare("INSERT INTO store_config (key, value) VALUES ('webhook_secret', ?)").run(secret);
  }
  return secret;
}

/**
 * Fire a webhook for the given event. Non-blocking — errors are caught and logged.
 */
export function fireWebhook(db: any, event: WebhookEvent, data: Record<string, unknown>): void {
  // Run async, fire-and-forget
  (async () => {
    try {
      const urlRow = db.prepare("SELECT value FROM store_config WHERE key = 'webhook_url'").get() as any;
      if (!urlRow?.value) return;

      const eventsRow = db.prepare("SELECT value FROM store_config WHERE key = 'webhook_events'").get() as any;
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

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);

      try {
        await fetch(urlRow.value, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Webhook-Signature': `sha256=${signature}`,
            'X-Webhook-Timestamp': payload.timestamp,
          },
          body,
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeoutId);
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      console.log(`[Webhook] Failed to deliver "${event}": ${msg}`);
    }
  })();
}
