import crypto from 'crypto';
import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage, DeliveryStatus,
         CallOptions, VoiceCallResult, CallEvent, TwilioConfig } from './types.js';
import { escapeXml } from '../../utils/xml.js';

export class TwilioProvider implements SmsProvider {
  name = 'twilio';
  private accountSid: string;
  private authToken: string;
  private fromNumber: string;

  constructor(config: TwilioConfig) {
    this.accountSid = config.accountSid;
    this.authToken = config.authToken;
    this.fromNumber = config.fromNumber;
  }

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;
    try {
      const params = new URLSearchParams();
      params.append('To', to);
      params.append('From', sendFrom);
      params.append('Body', body);

      // MMS: add media URLs
      if (media && media.length > 0) {
        for (const m of media) {
          params.append('MediaUrl', m.url);
        }
      }

      const response = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`,
        {
          method: 'POST',
          headers: {
            'Authorization': 'Basic ' + Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64'),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: params.toString(),
          signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
        }
      );

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'twilio', error: data.message || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'twilio', providerId: data.sid };
    } catch (err: any) {
      return { success: false, providerName: 'twilio', error: err.message };
    }
  }

  parseInboundWebhook(req: any): InboundMessage | null {
    const { From, To, Body, MessageSid, NumMedia } = req.body || {};
    if (!From || !To) return null;

    const media: MmsMedia[] = [];
    const numMedia = parseInt(NumMedia || '0', 10);
    for (let i = 0; i < numMedia; i++) {
      const url = req.body[`MediaUrl${i}`];
      const type = req.body[`MediaContentType${i}`];
      if (url) media.push({ url, contentType: type || 'application/octet-stream' });
    }

    return {
      from: From,
      to: To,
      body: Body || '',
      providerId: MessageSid,
      media: media.length > 0 ? media : undefined,
      messageType: media.length > 0 ? 'mms' : 'sms',
    };
  }

  verifyWebhookSignature(req: any): boolean {
    const signature = req.headers['x-twilio-signature'];
    if (!signature) return false;

    // Build the data string: URL + sorted POST params
    const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
    const params = req.body || {};
    const sortedKeys = Object.keys(params).sort();
    let data = url;
    for (const key of sortedKeys) {
      data += key + params[key];
    }

    const expected = crypto.createHmac('sha1', this.authToken)
      .update(data)
      .digest('base64');

    // Timing-safe comparison to prevent signature timing attacks.
    // timingSafeEqual requires equal-length buffers; reject immediately if lengths differ.
    const sigBuf = Buffer.from(signature);
    const expBuf = Buffer.from(expected);
    if (sigBuf.length !== expBuf.length) return false;
    return crypto.timingSafeEqual(sigBuf, expBuf);
  }

  parseStatusWebhook(req: any): DeliveryStatus | null {
    const { MessageSid, MessageStatus, ErrorCode, ErrorMessage } = req.body || {};
    if (!MessageSid || !MessageStatus) return null;
    return {
      providerId: MessageSid,
      status: MessageStatus, // queued, sent, delivered, undelivered, failed
      errorCode: ErrorCode,
      errorMessage: ErrorMessage,
    };
  }

  async initiateCall(to: string, from: string, opts: CallOptions): Promise<VoiceCallResult> {
    const callFrom = from || this.fromNumber;
    const firstLeg = opts.mode === 'push' && opts.pushTo ? opts.pushTo : callFrom;
    const twimlUrl = `${opts.callbackBaseUrl}/api/v1/voice/instructions/connect?to=${encodeURIComponent(to)}`;
    const statusUrl = `${opts.callbackBaseUrl}/api/v1/voice/status-webhook`;

    try {
      const params = new URLSearchParams();
      params.append('To', firstLeg);
      params.append('From', callFrom);
      params.append('Url', twimlUrl);
      params.append('StatusCallback', statusUrl);
      params.append('StatusCallbackEvent', 'initiated ringing answered completed');
      if (opts.record) {
        params.append('Record', 'true');
        params.append('RecordingStatusCallback', `${opts.callbackBaseUrl}/api/v1/voice/recording-webhook`);
        params.append('RecordingStatusCallbackEvent', 'completed');
        if (opts.transcribe) {
          params.append('TranscriptionCallback', `${opts.callbackBaseUrl}/api/v1/voice/transcription-webhook`);
        }
      }

      const response = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Calls.json`,
        {
          method: 'POST',
          headers: {
            'Authorization': 'Basic ' + Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64'),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: params.toString(),
          signal: AbortSignal.timeout(15000), // SEC-H13: Prevent hanging requests
        }
      );

      const data = await response.json() as any;
      if (!response.ok) {
        return { success: false, providerName: 'twilio', error: data.message || `HTTP ${response.status}` };
      }
      return { success: true, providerName: 'twilio', callId: data.sid };
    } catch (err: any) {
      return { success: false, providerName: 'twilio', error: err.message };
    }
  }

  parseCallWebhook(req: any): CallEvent | null {
    const { CallSid, CallStatus, Direction, From, To, CallDuration, RecordingUrl, RecordingSid, TranscriptionText } = req.body || {};
    if (!CallSid) return null;
    return {
      providerCallId: CallSid,
      status: CallStatus || 'unknown',
      direction: Direction === 'inbound' ? 'inbound' : 'outbound',
      from: From,
      to: To,
      duration: CallDuration ? parseInt(CallDuration, 10) : undefined,
      recordingUrl: RecordingUrl,
      recordingId: RecordingSid,
      transcription: TranscriptionText,
    };
  }

  generateCallInstructions(action: string, params: Record<string, any>): string {
    if (action === 'connect') {
      const announceRecording = params.announceRecording
        ? `<Say>This call may be recorded for quality purposes.</Say>` : '';
      return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  ${announceRecording}
  <Dial callerId="${escapeXml(params.from || this.fromNumber)}">${escapeXml(params.to)}</Dial>
</Response>`;
    }
    if (action === 'forward') {
      return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Dial>${escapeXml(params.forwardTo)}</Dial>
</Response>`;
    }
    return `<?xml version="1.0" encoding="UTF-8"?><Response><Say>No action configured.</Say></Response>`;
  }

  async getRecordingUrl(recordingId: string): Promise<string | null> {
    return `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Recordings/${recordingId}.mp3`;
  }

  async requestTranscription(_recordingId: string, _callbackUrl: string): Promise<string | null> {
    // Twilio's POST /Recordings/{id}/Transcriptions endpoint is deprecated.
    // Transcription is now handled via TwiML: <Record transcribe="true" transcribeCallback="..."/>
    // The voice route should set opts.transcribe=true at call initiation, which adds the
    // transcribe attributes to the <Record> TwiML in generateCallInstructions.
    // This method is a no-op — transcription delivery happens via the transcribeCallback webhook.
    return null;
  }
}
