import crypto from 'crypto';
import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage, DeliveryStatus,
         CallOptions, VoiceCallResult, CallEvent, TelnyxConfig } from './types.js';

export class TelnyxProvider implements SmsProvider {
  name = 'telnyx';
  private apiKey: string;
  private fromNumber: string;
  private publicKey: string;
  private connectionId: string;

  constructor(config: TelnyxConfig) {
    this.apiKey = config.apiKey;
    this.fromNumber = config.fromNumber;
    this.publicKey = config.publicKey || '';
    this.connectionId = config.connectionId || '';
  }

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;
    try {
      const payload: Record<string, any> = {
        from: sendFrom,
        to,
        text: body,
        type: 'SMS',
      };

      // MMS: add media URLs
      if (media && media.length > 0) {
        payload.type = 'MMS';
        payload.media_urls = media.map(m => m.url);
      }

      const response = await fetch('https://api.telnyx.com/v2/messages', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
      });

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'telnyx', error: data.errors?.[0]?.detail || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'telnyx', providerId: data.data?.id };
    } catch (err: any) {
      return { success: false, providerName: 'telnyx', error: err.message };
    }
  }

  parseInboundWebhook(req: any): InboundMessage | null {
    const payload = req.body?.data?.payload;
    if (!payload) return null;

    const from = payload.from?.phone_number;
    const to = payload.to?.[0]?.phone_number;
    const body = payload.text || '';
    const providerId = payload.id;

    const media: MmsMedia[] = [];
    if (payload.media && Array.isArray(payload.media)) {
      for (const m of payload.media) {
        if (m.url) media.push({ url: m.url, contentType: m.content_type || 'application/octet-stream' });
      }
    }

    if (!from || !to) return null;
    return {
      from, to, body, providerId,
      media: media.length > 0 ? media : undefined,
      messageType: media.length > 0 ? 'mms' : 'sms',
    };
  }

  verifyWebhookSignature(req: any): boolean {
    if (!this.publicKey) return false; // Reject if no public key configured
    const signature = req.headers['telnyx-signature-ed25519'];
    const timestamp = req.headers['telnyx-timestamp'];
    if (!signature || !timestamp) return false;

    // @audit-fixed: previously fell back to `JSON.stringify(req.body)` when rawBody
    // was missing — but JSON re-serialization is NOT canonical (Node may reorder
    // keys, normalize whitespace, etc.) and the result will NEVER match Telnyx's
    // signature against the original wire bytes. The fallback was a 100% silent
    // verification failure pretending to be working. Refuse to verify if rawBody
    // isn't available; the route layer must mount express.raw() / capture-rawBody
    // middleware on the Telnyx webhook path.
    const rawBody = (req as any).rawBody;
    if (!rawBody) {
      console.warn('[Telnyx] verifyWebhookSignature: rawBody missing — wire raw-body capture middleware on the Telnyx webhook path. Refusing to verify against re-serialized JSON.');
      return false;
    }

    // @audit-fixed: Replay attack protection — reject signatures whose timestamp is
    // more than 5 minutes old. Without this check, a captured webhook can be
    // re-played indefinitely.
    const tsNum = parseInt(String(timestamp), 10);
    if (!Number.isFinite(tsNum) || Math.abs(Date.now() / 1000 - tsNum) > 300) {
      console.warn('[Telnyx] verifyWebhookSignature: timestamp out of window (>5 min)');
      return false;
    }

    try {
      const rawBodyStr = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody);
      const payload = `${timestamp}|${rawBodyStr}`;
      return crypto.verify(
        null,
        Buffer.from(payload),
        { key: Buffer.from(this.publicKey, 'base64'), format: 'der', type: 'spki' },
        Buffer.from(signature, 'base64')
      );
    } catch {
      return false; // Crypto exception must reject — fail closed, not open
    }
  }

  parseStatusWebhook(req: any): DeliveryStatus | null {
    const payload = req.body?.data?.payload;
    if (!payload) return null;
    const eventType = req.body?.data?.event_type;

    // Telnyx API v2 only sends: message.sent, message.finalized
    // Delivery outcomes (delivered, delivery_failed, etc.) are in message.finalized → to[0].status
    let status: string;
    switch (eventType) {
      case 'message.sent':
        status = 'sent';
        break;
      case 'message.finalized':
        status = payload.to?.[0]?.status || 'unknown';
        break;
      default:
        return null;
    }

    return {
      providerId: payload.id,
      status,
    };
  }

  async initiateCall(to: string, from: string, opts: CallOptions): Promise<VoiceCallResult> {
    const callFrom = from || this.fromNumber;
    const firstLeg = opts.mode === 'push' && opts.pushTo ? opts.pushTo : callFrom;

    try {
      // Telnyx Call Control sends all events (including call.answered) to webhook_url.
      // There is no separate answer_url — the voice webhook handler must issue a
      // bridge command (POST /v2/calls/{id}/actions/bridge) when it receives call.answered.
      const payload: Record<string, any> = {
        to: firstLeg,
        from: callFrom,
        connection_id: this.connectionId,
        webhook_url: `${opts.callbackBaseUrl}/api/v1/voice/status-webhook`,
        webhook_url_method: 'POST',
        record: opts.record ? 'record-from-answer' : undefined,
      };

      const response = await fetch('https://api.telnyx.com/v2/calls', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
      });

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'telnyx', error: data.errors?.[0]?.detail || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'telnyx', callId: data.data?.call_control_id };
    } catch (err: any) {
      return { success: false, providerName: 'telnyx', error: err.message };
    }
  }

  parseCallWebhook(req: any): CallEvent | null {
    const payload = req.body?.data?.payload;
    if (!payload) return null;
    return {
      providerCallId: payload.call_control_id || payload.call_session_id,
      status: payload.state || req.body?.data?.event_type || 'unknown',
      direction: payload.direction === 'incoming' ? 'inbound' : 'outbound',
      from: payload.from,
      to: payload.to,
      duration: payload.duration_secs,
      recordingUrl: payload.recording_urls?.mp3,
      recordingId: payload.recording_id,
    };
  }

  generateCallInstructions(action: string, params: Record<string, any>): string {
    // Telnyx uses Call Control commands via REST API, not XML/TwiML.
    // In practice, call instructions are executed by POSTing to
    // /v2/calls/{call_control_id}/actions/bridge (or /hangup, /speak, etc.).
    // The voice webhook handler should call the Telnyx API to bridge when it
    // receives a call.answered event. This method returns a JSON descriptor
    // that the handler can use to build the API call.
    if (action === 'connect') {
      return JSON.stringify({
        command: 'bridge',
        to: params.to,
        from: params.from || this.fromNumber,
      });
    }
    return JSON.stringify({ command: 'hangup' });
  }

  async getRecordingUrl(recordingId: string): Promise<string | null> {
    try {
      const response = await fetch(`https://api.telnyx.com/v2/recordings/${recordingId}`, {
        headers: { 'Authorization': `Bearer ${this.apiKey}` },
        signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
      });
      const data = await response.json() as any;
      return data.data?.download_urls?.mp3 || null;
    } catch {
      return null;
    }
  }

  async requestTranscription(recordingId: string, _callbackUrl: string): Promise<string | null> {
    // Telnyx transcription is enabled at recording start, delivered via webhook
    // If not already enabled, we can't retroactively request it
    return null;
  }
}
