import crypto from 'crypto';
import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage, DeliveryStatus,
         CallOptions, VoiceCallResult, CallEvent, PlivoConfig } from './types.js';
import { escapeXml } from '../../utils/xml.js';
import { createBreaker } from '../../utils/circuitBreaker.js';

// SEC-H77: per-provider breaker so Plivo outages don't affect other providers.
const plivoBreaker = createBreaker('plivo');

export class PlivoProvider implements SmsProvider {
  name = 'plivo';
  private authId: string;
  private authToken: string;
  private fromNumber: string;

  constructor(config: PlivoConfig) {
    this.authId = config.authId;
    this.authToken = config.authToken;
    this.fromNumber = config.fromNumber;
  }

  private get authHeader(): string {
    return 'Basic ' + Buffer.from(`${this.authId}:${this.authToken}`).toString('base64');
  }

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;
    try {
      const payload: Record<string, any> = {
        src: sendFrom,
        dst: to,
        text: body,
      };

      if (media && media.length > 0) {
        payload.type = 'mms';
        payload.media_urls = media.map(m => m.url);
      }

      const response = await plivoBreaker.run(() =>
        fetch(
          `https://api.plivo.com/v1/Account/${this.authId}/Message/`,
          {
            method: 'POST',
            headers: {
              'Authorization': this.authHeader,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
            signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
          },
        ),
      );

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'plivo', error: data.error || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'plivo', providerId: data.message_uuid?.[0] || data.message_uuid };
    } catch (err: any) {
      return { success: false, providerName: 'plivo', error: err.message };
    }
  }

  parseInboundWebhook(req: any): InboundMessage | null {
    const { From, To, Text, MessageUUID, TotalRate } = req.body || {};
    if (!From || !To) return null;

    const media: MmsMedia[] = [];
    // Plivo sends MediaUrl0, MediaUrl1, etc. for MMS
    for (let i = 0; i < 10; i++) {
      const url = req.body[`MediaUrl${i}`];
      const type = req.body[`MediaContentType${i}`];
      if (url) media.push({ url, contentType: type || 'image/jpeg' });
      else break;
    }

    return {
      from: From,
      to: To,
      body: Text || '',
      providerId: MessageUUID,
      media: media.length > 0 ? media : undefined,
      messageType: media.length > 0 ? 'mms' : 'sms',
    };
  }

  verifyWebhookSignature(req: any): boolean {
    const signature = req.headers['x-plivo-signature-v3'];
    const nonce = req.headers['x-plivo-signature-v3-nonce'];
    if (!signature || !nonce) return false;

    try {
      // Plivo V3: base_string = url + sorted_POST_params + '.' + nonce
      const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
      // Sort POST params alphabetically and append key=value pairs to URL
      const params = req.body && typeof req.body === 'object' ? req.body : {};
      const sortedKeys = Object.keys(params).sort();
      let paramString = '';
      for (const key of sortedKeys) {
        paramString += key + (params[key] ?? '');
      }
      const baseString = url + paramString + '.' + nonce;

      const expected = crypto.createHmac('sha256', this.authToken)
        .update(baseString)
        .digest('base64');

      const sigBuf = Buffer.from(signature, 'base64');
      const expectedBuf = Buffer.from(expected, 'base64');
      if (sigBuf.length !== expectedBuf.length) return false;
      return crypto.timingSafeEqual(sigBuf, expectedBuf);
    } catch {
      return false;
    }
  }

  parseStatusWebhook(req: any): DeliveryStatus | null {
    const { MessageUUID, Status, ErrorCode } = req.body || {};
    if (!MessageUUID) return null;
    return {
      providerId: MessageUUID,
      status: Status || 'unknown',
      errorCode: ErrorCode,
    };
  }

  async initiateCall(to: string, from: string, opts: CallOptions): Promise<VoiceCallResult> {
    const callFrom = from || this.fromNumber;
    const firstLeg = opts.mode === 'push' && opts.pushTo ? opts.pushTo : callFrom;

    try {
      const payload = {
        to: firstLeg,
        from: callFrom,
        answer_url: `${opts.callbackBaseUrl}/api/v1/voice/instructions/connect?to=${encodeURIComponent(to)}`,
        hangup_url: `${opts.callbackBaseUrl}/api/v1/voice/status-webhook`,
        record: opts.record || false,
        recording_callback_url: opts.record ? `${opts.callbackBaseUrl}/api/v1/voice/recording-webhook` : undefined,
      };

      const response = await plivoBreaker.run(() =>
        fetch(
          `https://api.plivo.com/v1/Account/${this.authId}/Call/`,
          {
            method: 'POST',
            headers: {
              'Authorization': this.authHeader,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
            signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
          },
        ),
      );

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'plivo', error: data.error || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'plivo', callId: data.request_uuid };
    } catch (err: any) {
      return { success: false, providerName: 'plivo', error: err.message };
    }
  }

  parseCallWebhook(req: any): CallEvent | null {
    const { CallUUID, CallStatus, Direction, From, To, Duration, RecordUrl } = req.body || {};
    if (!CallUUID) return null;
    return {
      providerCallId: CallUUID,
      status: CallStatus || 'unknown',
      direction: Direction === 'inbound' ? 'inbound' : 'outbound',
      from: From, to: To,
      duration: Duration ? parseInt(Duration, 10) : undefined,
      recordingUrl: RecordUrl,
    };
  }

  generateCallInstructions(action: string, params: Record<string, any>): string {
    // Plivo uses XML
    if (action === 'connect') {
      const announce = params.announceRecording
        ? `<Speak>This call may be recorded for quality purposes.</Speak>` : '';
      return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  ${announce}
  <Dial callerId="${escapeXml(params.from || this.fromNumber)}">
    <Number>${escapeXml(params.to)}</Number>
  </Dial>
</Response>`;
    }
    return `<?xml version="1.0" encoding="UTF-8"?><Response><Hangup/></Response>`;
  }

  async getRecordingUrl(recordingId: string): Promise<string | null> {
    return `https://api.plivo.com/v1/Account/${this.authId}/Recording/${recordingId}/`;
  }
}
