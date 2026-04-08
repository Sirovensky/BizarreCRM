/**
 * ENR-A6: Outbound webhook service.
 *
 * Reads `webhook_url` and `webhook_events` from store_config.
 * When an event fires, POSTs a JSON payload to the configured URL.
 * Fire-and-forget with a 5-second timeout — failures are logged, never thrown.
 */

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

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);

      try {
        await fetch(urlRow.value, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
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
