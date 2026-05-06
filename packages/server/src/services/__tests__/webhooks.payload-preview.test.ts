import { describe, expect, it } from 'vitest';
import {
  WEBHOOK_FAILURE_PAYLOAD_PREVIEW_BYTES,
  formatWebhookFailurePayloadPreview,
} from '../webhooks.js';

describe('webhook failure payload previews', () => {
  it('returns the full sent payload when it is under the 4 KB response cap', () => {
    const payload = JSON.stringify({ event: 'ticket_created', data: { ticket_id: 123 } });

    expect(formatWebhookFailurePayloadPreview(payload)).toEqual({
      sent_payload: payload,
      payload_bytes: Buffer.byteLength(payload, 'utf8'),
      payload_truncated: false,
    });
  });

  it('caps sent payload previews at 4 KB', () => {
    const payload = JSON.stringify({ event: 'ticket_created', data: { notes: 'x'.repeat(8_000) } });
    const preview = formatWebhookFailurePayloadPreview(payload);

    expect(preview.payload_bytes).toBe(Buffer.byteLength(payload, 'utf8'));
    expect(preview.payload_truncated).toBe(true);
    expect(Buffer.byteLength(preview.sent_payload ?? '', 'utf8')).toBeLessThanOrEqual(WEBHOOK_FAILURE_PAYLOAD_PREVIEW_BYTES);
  });

  it('does not split multibyte characters at the cap boundary', () => {
    const payload = 'a'.repeat(WEBHOOK_FAILURE_PAYLOAD_PREVIEW_BYTES - 1) + '€';
    const preview = formatWebhookFailurePayloadPreview(payload);

    expect(preview.payload_truncated).toBe(true);
    expect(Buffer.byteLength(preview.sent_payload ?? '', 'utf8')).toBe(WEBHOOK_FAILURE_PAYLOAD_PREVIEW_BYTES - 1);
    expect(preview.sent_payload?.endsWith('€')).toBe(false);
  });
});
