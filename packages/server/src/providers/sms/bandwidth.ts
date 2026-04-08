import crypto from 'crypto';
import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage, DeliveryStatus,
         CallOptions, VoiceCallResult, CallEvent, BandwidthConfig } from './types.js';
import { escapeXml } from '../../utils/xml.js';

export class BandwidthProvider implements SmsProvider {
  name = 'bandwidth';
  private accountId: string;
  private username: string;
  private password: string;
  private applicationId: string;
  private fromNumber: string;
  private voiceApplicationId: string;

  constructor(config: BandwidthConfig) {
    this.accountId = config.accountId;
    this.username = config.username;
    this.password = config.password;
    this.applicationId = config.applicationId;
    this.fromNumber = config.fromNumber;
    this.voiceApplicationId = config.voiceApplicationId || '';
  }

  private get authHeader(): string {
    return 'Basic ' + Buffer.from(`${this.username}:${this.password}`).toString('base64');
  }

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;
    try {
      const payload: Record<string, any> = {
        to: [to],
        from: sendFrom,
        text: body,
        applicationId: this.applicationId,
      };

      if (media && media.length > 0) {
        payload.media = media.map(m => m.url);
      }

      const response = await fetch(
        `https://messaging.bandwidth.com/api/v2/users/${this.accountId}/messages`,
        {
          method: 'POST',
          headers: {
            'Authorization': this.authHeader,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
        }
      );

      const data = await response.json() as any;
      if (!response.ok && response.status !== 202) {
        return { success: false, providerName: 'bandwidth', error: data.description || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'bandwidth', providerId: data.id };
    } catch (err: any) {
      return { success: false, providerName: 'bandwidth', error: err.message };
    }
  }

  parseInboundWebhook(req: any): InboundMessage | null {
    // Bandwidth sends array of callbacks
    const callbacks = Array.isArray(req.body) ? req.body : [req.body];
    const cb = callbacks[0];
    if (!cb || cb.type !== 'message-received') return null;

    const msg = cb.message;
    if (!msg) return null;

    const media: MmsMedia[] = [];
    if (msg.media && Array.isArray(msg.media)) {
      for (const url of msg.media) {
        if (typeof url === 'string' && !url.endsWith('.smil')) {
          media.push({ url, contentType: 'image/jpeg' }); // Bandwidth doesn't always provide MIME
        }
      }
    }

    return {
      from: msg.from,
      to: msg.to,
      body: msg.text || '',
      providerId: msg.id,
      media: media.length > 0 ? media : undefined,
      messageType: media.length > 0 ? 'mms' : 'sms',
    };
  }

  verifyWebhookSignature(req: any): boolean {
    // Bandwidth uses a 401 challenge-response flow for webhook auth, not proactive header signing.
    // Their flow: (1) send webhook without auth, (2) expect 401 + WWW-Authenticate, (3) resend with Basic auth.
    // This challenge flow is incompatible with our single-pass webhook handler.
    // If Basic auth header IS present (retry after challenge), verify it:
    const authHeader = req.headers?.authorization;
    if (authHeader?.startsWith('Basic ')) {
      try {
        const decoded = Buffer.from(authHeader.slice(6), 'base64').toString();
        const expected = `${this.username}:${this.password}`;
        const decodedBuf = Buffer.from(decoded);
        const expectedBuf = Buffer.from(expected);
        if (decodedBuf.length !== expectedBuf.length) return false;
        return crypto.timingSafeEqual(decodedBuf, expectedBuf);
      } catch {
        return false;
      }
    }
    // No auth header — reject the request.
    // SECURITY: Bandwidth webhook URLs must include Basic auth credentials in the URL
    // (e.g., https://user:pass@yourserver.com/webhook) so Bandwidth sends them on every request.
    // Without auth, any party who discovers the webhook URL can inject fake messages.
    console.warn('[Bandwidth] Webhook request has no Authorization header. Rejecting — configure Basic auth credentials in your Bandwidth webhook URL.');
    return false;
  }

  parseStatusWebhook(req: any): DeliveryStatus | null {
    const callbacks = Array.isArray(req.body) ? req.body : [req.body];
    const cb = callbacks[0];
    if (!cb || !cb.type?.startsWith('message-')) return null;
    return {
      providerId: cb.message?.id || '',
      status: cb.type === 'message-delivered' ? 'delivered' :
              cb.type === 'message-failed' ? 'failed' : cb.type,
      errorCode: (cb.description || cb.errorCode)?.toString(),
    };
  }

  async initiateCall(to: string, from: string, opts: CallOptions): Promise<VoiceCallResult> {
    const callFrom = from || this.fromNumber;
    const firstLeg = opts.mode === 'push' && opts.pushTo ? opts.pushTo : callFrom;

    try {
      const payload = {
        to: firstLeg,
        from: callFrom,
        applicationId: this.voiceApplicationId || this.applicationId,
        answerUrl: `${opts.callbackBaseUrl}/api/v1/voice/instructions/connect?to=${encodeURIComponent(to)}`,
        disconnectUrl: `${opts.callbackBaseUrl}/api/v1/voice/status-webhook`,
      };

      const response = await fetch(
        `https://voice.bandwidth.com/api/v2/accounts/${this.accountId}/calls`,
        {
          method: 'POST',
          headers: {
            'Authorization': this.authHeader,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
        }
      );

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'bandwidth', error: data.description || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'bandwidth', callId: data.callId };
    } catch (err: any) {
      return { success: false, providerName: 'bandwidth', error: err.message };
    }
  }

  parseCallWebhook(req: any): CallEvent | null {
    const { callId, eventType, from, to, cause, duration } = req.body || {};
    if (!callId) return null;
    const statusMap: Record<string, string> = {
      answer: 'in-progress', hangup: 'completed', disconnect: 'completed',
      error: 'failed', timeout: 'no-answer',
    };
    return {
      providerCallId: callId,
      status: statusMap[eventType] || eventType || 'unknown',
      direction: req.body?.direction === 'inbound' ? 'inbound' : 'outbound',
      from, to,
      duration: duration ? Math.round(parseFloat(duration)) : undefined,
    };
  }

  generateCallInstructions(action: string, params: Record<string, any>): string {
    // Bandwidth uses BXML
    if (action === 'connect') {
      const announce = params.announceRecording
        ? `<SpeakSentence>This call may be recorded for quality purposes.</SpeakSentence>` : '';
      return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  ${announce}
  <Transfer transferCallerId="${escapeXml(params.from)}">
    <PhoneNumber>${escapeXml(params.to)}</PhoneNumber>
  </Transfer>
</Response>`;
    }
    return `<?xml version="1.0" encoding="UTF-8"?><Response><Hangup/></Response>`;
  }

  async getRecordingUrl(recordingId: string): Promise<string | null> {
    return `https://voice.bandwidth.com/api/v2/accounts/${this.accountId}/recordings/${recordingId}/media`;
  }
}
