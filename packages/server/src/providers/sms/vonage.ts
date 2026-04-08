import crypto from 'crypto';
import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage, DeliveryStatus,
         CallOptions, VoiceCallResult, CallEvent, VonageConfig } from './types.js';

export class VonageProvider implements SmsProvider {
  name = 'vonage';
  private apiKey: string;
  private apiSecret: string;
  private fromNumber: string;
  private applicationId: string;
  private privateKey: string;
  private signatureSecret: string;
  private signatureMethod: string;

  constructor(config: VonageConfig) {
    this.apiKey = config.apiKey;
    this.apiSecret = config.apiSecret;
    this.fromNumber = config.fromNumber;
    this.applicationId = config.applicationId || '';
    this.privateKey = config.privateKey || '';
    this.signatureSecret = config.signatureSecret || config.apiSecret; // Falls back to apiSecret if not set
    this.signatureMethod = config.signatureMethod || 'md5hash';
  }

  private detectMediaType(media: MmsMedia): { messageType: string; payloadKey: string } {
    const ct = (media.contentType || '').toLowerCase();
    if (ct.startsWith('video/')) return { messageType: 'video', payloadKey: 'video' };
    if (ct.startsWith('audio/')) return { messageType: 'audio', payloadKey: 'audio' };
    if (ct.startsWith('image/')) return { messageType: 'image', payloadKey: 'image' };
    return { messageType: 'file', payloadKey: 'file' };
  }

  private generateJwt(): string {
    if (!this.applicationId || !this.privateKey) {
      throw new Error('Vonage voice requires applicationId and privateKey configuration');
    }
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    const payload = Buffer.from(JSON.stringify({
      application_id: this.applicationId,
      iat: now,
      jti: crypto.randomUUID(),
      exp: now + 300,
    })).toString('base64url');
    const signature = crypto.sign('RSA-SHA256', Buffer.from(`${header}.${payload}`), this.privateKey).toString('base64url');
    return `${header}.${payload}.${signature}`;
  }

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;

    // Use Messages API for MMS, SMS API for plain text
    if (media && media.length > 0) {
      return this.sendMms(to, body, sendFrom, media);
    }
    return this.sendSms(to, body, sendFrom);
  }

  private async sendSms(to: string, body: string, from: string): Promise<SmsProviderResult> {
    try {
      const response = await fetch('https://rest.nexmo.com/sms/json', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          api_key: this.apiKey,
          api_secret: this.apiSecret,
          from,
          to,
          text: body,
        }),
        signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
      });

      const data = await response.json() as any;
      const msg = data.messages?.[0];
      if (msg?.status !== '0') {
        return { success: false, providerName: 'vonage', error: msg?.['error-text'] || 'Send failed' };
      }
      return { success: true, providerName: 'vonage', providerId: msg?.['message-id'] };
    } catch (err: any) {
      return { success: false, providerName: 'vonage', error: err.message };
    }
  }

  private async sendMms(to: string, body: string, from: string, media: MmsMedia[]): Promise<SmsProviderResult> {
    try {
      if (media.length > 1) {
        console.warn(`[Vonage] MMS: ${media.length} media items provided but Vonage only supports 1 per message — sending first only`);
      }
      const { messageType, payloadKey } = this.detectMediaType(media[0]);
      const mediaPayload = payloadKey === 'image'
        ? { url: media[0].url, caption: body }
        : { url: media[0].url };

      const payload: Record<string, any> = {
        message_type: messageType,
        channel: 'mms',
        to: to,
        from: from,
        [payloadKey]: mediaPayload,
      };

      const response = await fetch('https://api.nexmo.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic ' + Buffer.from(`${this.apiKey}:${this.apiSecret}`).toString('base64'),
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
      });

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'vonage', error: data.title || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'vonage', providerId: data.message_uuid };
    } catch (err: any) {
      return { success: false, providerName: 'vonage', error: err.message };
    }
  }

  parseInboundWebhook(req: any): InboundMessage | null {
    // Vonage Messages API inbound
    if (req.body?.channel === 'mms' || req.body?.message_type) {
      const mediaItems: MmsMedia[] = [];
      if (req.body.image?.url) mediaItems.push({ url: req.body.image.url, contentType: 'image/jpeg' });
      if (req.body.video?.url) mediaItems.push({ url: req.body.video.url, contentType: 'video/mp4' });
      if (req.body.audio?.url) mediaItems.push({ url: req.body.audio.url, contentType: 'audio/mpeg' });
      if (req.body.file?.url) mediaItems.push({ url: req.body.file.url, contentType: 'application/octet-stream' });
      return {
        from: req.body.from,
        to: req.body.to,
        body: req.body.text || req.body.message?.content?.text || '',
        providerId: req.body.message_uuid,
        media: mediaItems.length > 0 ? mediaItems : undefined,
        messageType: mediaItems.length > 0 ? 'mms' : 'sms',
      };
    }

    // Vonage SMS API inbound (legacy)
    const { msisdn, to, text, messageId } = req.body || {};
    if (!msisdn) return null;
    return {
      from: msisdn,
      to: to || '',
      body: text || '',
      providerId: messageId,
      messageType: 'sms',
    };
  }

  verifyWebhookSignature(req: any): boolean {
    // Legacy SMS API: signature in query param 'sig'
    // Uses signatureSecret (from Vonage dashboard → Settings) and configurable algorithm
    const sig = req.query?.sig;
    if (sig) {
      try {
        const params = { ...req.query };
        delete params.sig;
        const sorted = Object.keys(params).sort();
        let sigString = '';
        for (const key of sorted) { sigString += key + params[key]; }

        let expected: string;
        const method = this.signatureMethod;
        if (method === 'md5hash') {
          // MD5 hash: concat params + secret, then MD5
          expected = crypto.createHash('md5').update(sigString + this.signatureSecret).digest('hex');
        } else {
          // HMAC variants: md5hmac, sha1hmac, sha256hmac, sha512hmac
          const algo = method.replace('hmac', '').replace('sha', 'sha'); // md5, sha1, sha256, sha512
          expected = crypto.createHmac(algo, this.signatureSecret).update(sigString).digest('hex');
        }

        const sigBuf = Buffer.from(String(sig));
        const expectedBuf = Buffer.from(expected);
        if (sigBuf.length !== expectedBuf.length) return false;
        return crypto.timingSafeEqual(sigBuf, expectedBuf);
      } catch { return false; }
    }
    // Messages API: JWT Bearer token — requires app public key for proper verification.
    // SECURITY: Do NOT accept unverified JWTs. Configure signature secret instead.
    const authHeader = req.headers?.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      console.warn('[Vonage] Messages API webhook has JWT Bearer token but verification is not implemented (needs app public key). Rejecting — configure signature-based verification instead.');
      return false;
    }
    return false;
  }

  parseStatusWebhook(req: any): DeliveryStatus | null {
    const { message_uuid, status, error } = req.body || {};
    if (!message_uuid) return null;
    return {
      providerId: message_uuid,
      status: status || 'unknown',
      errorCode: error?.code?.toString(),
      errorMessage: error?.reason,
    };
  }

  async initiateCall(to: string, from: string, opts: CallOptions): Promise<VoiceCallResult> {
    const callFrom = from || this.fromNumber;
    const firstLeg = opts.mode === 'push' && opts.pushTo ? opts.pushTo : callFrom;

    try {
      // Vonage uses NCCO (Nexmo Call Control Objects) as JSON
      const ncco = [
        ...(opts.record ? [{ action: 'record', eventUrl: [`${opts.callbackBaseUrl}/api/v1/voice/recording-webhook`] }] : []),
        { action: 'connect', from: callFrom, endpoint: [{ type: 'phone', number: to }] },
      ];

      const payload = {
        to: [{ type: 'phone', number: firstLeg }],
        from: { type: 'phone', number: callFrom },
        ncco,
        event_url: [`${opts.callbackBaseUrl}/api/v1/voice/status-webhook`],
      };

      const response = await fetch('https://api.nexmo.com/v1/calls', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.generateJwt()}`,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
      });

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'vonage', error: data.title || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'vonage', callId: data.uuid };
    } catch (err: any) {
      return { success: false, providerName: 'vonage', error: err.message };
    }
  }

  parseCallWebhook(req: any): CallEvent | null {
    const { uuid, status, direction, from, to, duration, recording_url } = req.body || {};
    if (!uuid) return null;
    return {
      providerCallId: uuid,
      status: status || 'unknown',
      direction: direction === 'inbound' ? 'inbound' : 'outbound',
      from: from?.number || from, to: to?.number || to,
      duration: duration ? parseInt(duration, 10) : undefined,
      recordingUrl: recording_url,
    };
  }

  generateCallInstructions(action: string, params: Record<string, any>): string {
    // Vonage uses NCCO (JSON)
    if (action === 'connect') {
      const ncco: any[] = [];
      if (params.announceRecording) {
        ncco.push({ action: 'talk', text: 'This call may be recorded for quality purposes.' });
      }
      ncco.push({ action: 'connect', from: params.from || this.fromNumber, endpoint: [{ type: 'phone', number: params.to }] });
      return JSON.stringify(ncco);
    }
    return JSON.stringify([{ action: 'talk', text: 'Goodbye.' }]);
  }

  async getRecordingUrl(recordingId: string): Promise<string | null> {
    // Note: Downloading from this URL requires JWT auth — the voice recording webhook handler
    // should use generateJwt() for the Authorization header when fetching the file
    return `https://api.nexmo.com/v1/files/${recordingId}`;
  }
}
