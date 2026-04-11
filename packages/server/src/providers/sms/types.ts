/**
 * SMS/MMS + Voice provider abstraction layer.
 * All providers implement this interface for unified messaging and calling.
 */

// --- Messaging Types ---

export interface MmsMedia {
  url: string;
  contentType: string; // e.g. 'image/jpeg', 'image/png'
}

export interface SmsProviderResult {
  success: boolean;
  providerId?: string;      // Provider's message ID
  providerName: string;
  error?: string;
  /**
   * True when the provider is the dev-only ConsoleProvider or an incomplete
   * credential fallback. Callers MUST check this before marking messages as
   * delivered, incrementing usage counters, or charging tenants.
   */
  simulated?: boolean;
}

export interface InboundMessage {
  from: string;
  to: string;
  body: string;
  providerId?: string;
  media?: MmsMedia[];
  messageType: 'sms' | 'mms';
}

export interface DeliveryStatus {
  providerId: string;
  status: string;         // 'delivered', 'failed', 'undelivered', etc.
  errorCode?: string;
  errorMessage?: string;
}

// --- Voice Types ---

export interface CallOptions {
  mode: 'bridge' | 'push';   // bridge = call store first, push = call tech's mobile first
  pushTo?: string;            // Tech's mobile number (for push mode)
  record?: boolean;           // Start recording immediately
  transcribe?: boolean;       // Request transcription after recording
  callbackBaseUrl: string;    // Base URL for status/recording/transcription webhooks
}

export interface VoiceCallResult {
  success: boolean;
  callId?: string;            // Provider's call ID
  providerName: string;
  error?: string;
}

export interface CallEvent {
  providerCallId: string;
  status: string;             // 'initiated', 'ringing', 'in-progress', 'completed', 'failed', 'busy', 'no-answer'
  direction: 'inbound' | 'outbound';
  from?: string;
  to?: string;
  duration?: number;          // seconds
  recordingUrl?: string;
  recordingId?: string;
  transcription?: string;
}

// --- Provider Interface ---

export interface SmsProvider {
  name: string;

  // ---- Messaging ----

  /** Send SMS or MMS. If media is provided, sends as MMS. */
  send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult>;

  /** Parse an inbound SMS/MMS webhook request into a normalized message. */
  parseInboundWebhook?(req: any): InboundMessage | null;

  /** Verify the authenticity of an inbound webhook request (signature check). */
  verifyWebhookSignature?(req: any): boolean;

  /** Parse a delivery status webhook into normalized status. */
  parseStatusWebhook?(req: any): DeliveryStatus | null;

  // ---- Voice ----

  /** Initiate an outbound call (two-leg bridge: store/tech phone → customer phone). */
  initiateCall?(to: string, from: string, opts: CallOptions): Promise<VoiceCallResult>;

  /** Parse a voice webhook event (call status, recording ready, etc). */
  parseCallWebhook?(req: any): CallEvent | null;

  /** Generate provider-specific call instructions (TwiML, TeXML, BXML, etc). */
  generateCallInstructions?(action: string, params: Record<string, any>): string;

  /** Get the download URL for a call recording. */
  getRecordingUrl?(recordingId: string): Promise<string | null>;

  /** Request transcription of a recording. Returns transcription text or null if async. */
  requestTranscription?(recordingId: string, callbackUrl: string): Promise<string | null>;
}

// --- Provider Config Types ---

export interface TwilioConfig {
  accountSid: string;
  authToken: string;
  fromNumber: string;
}

export interface TelnyxConfig {
  apiKey: string;
  fromNumber: string;
  publicKey?: string;       // For webhook signature verification (ed25519)
  connectionId?: string;    // For voice Call Control
}

export interface BandwidthConfig {
  accountId: string;
  username: string;
  password: string;
  applicationId: string;    // Messaging application ID
  fromNumber: string;
  voiceApplicationId?: string;
}

export interface PlivoConfig {
  authId: string;
  authToken: string;
  fromNumber: string;
}

export interface VonageConfig {
  apiKey: string;
  apiSecret: string;
  fromNumber: string;
  applicationId?: string;   // For voice
  privateKey?: string;      // JWT signing for voice
  signatureSecret?: string; // Separate secret for webhook sig verification (Vonage dashboard → Settings → Signature secret)
  signatureMethod?: string; // 'md5hash' | 'md5hmac' | 'sha1hmac' | 'sha256hmac' | 'sha512hmac' (default: md5hash)
}

export type ProviderType = 'console' | 'twilio' | 'telnyx' | 'bandwidth' | 'plivo' | 'vonage';

export interface ProviderInfo {
  type: ProviderType;
  label: string;
  description: string;
  fields: { key: string; label: string; placeholder: string; sensitive: boolean; required: boolean }[];
  supportsSms: boolean;
  supportsMms: boolean;
  supportsVoice: boolean;
  supportsRecording: boolean;
  supportsTranscription: boolean;
}

/** Registry of all provider metadata (used by Settings UI). */
export const PROVIDER_REGISTRY: ProviderInfo[] = [
  {
    type: 'console',
    label: 'Console (Testing)',
    description: 'Logs messages to server console. No real SMS sent. For development only.',
    fields: [],
    supportsSms: true, supportsMms: false, supportsVoice: false, supportsRecording: false, supportsTranscription: false,
  },
  {
    type: 'twilio',
    label: 'Twilio',
    description: 'Most popular. Best documentation. ~$0.008/SMS, ~$0.02/MMS, $0.014/min voice.',
    fields: [
      { key: 'account_sid', label: 'Account SID', placeholder: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', sensitive: false, required: true },
      { key: 'auth_token', label: 'Auth Token', placeholder: 'your-auth-token', sensitive: true, required: true },
      { key: 'from_number', label: 'From Number', placeholder: '+13035551234', sensitive: false, required: true },
    ],
    supportsSms: true, supportsMms: true, supportsVoice: true, supportsRecording: true, supportsTranscription: true,
  },
  {
    type: 'telnyx',
    label: 'Telnyx',
    description: 'Cheapest option. Owns network. ~$0.004/SMS, ~$0.015/MMS, $0.0002/min voice.',
    fields: [
      { key: 'api_key', label: 'API Key', placeholder: 'KEY0xxxxxxxxxxxxxxxx', sensitive: true, required: true },
      { key: 'from_number', label: 'From Number', placeholder: '+13035551234', sensitive: false, required: true },
      { key: 'public_key', label: 'Public Key (webhook verify)', placeholder: 'Optional — from Telnyx portal', sensitive: false, required: false },
      { key: 'connection_id', label: 'Voice Connection ID', placeholder: 'Optional — for voice calls', sensitive: false, required: false },
    ],
    supportsSms: true, supportsMms: true, supportsVoice: true, supportsRecording: true, supportsTranscription: true,
  },
  {
    type: 'bandwidth',
    label: 'Bandwidth',
    description: 'Carrier-grade. Free inbound SMS. US/Canada focused. ~$0.004/SMS.',
    fields: [
      { key: 'account_id', label: 'Account ID', placeholder: '1234567', sensitive: false, required: true },
      { key: 'username', label: 'API Username', placeholder: 'your-username', sensitive: false, required: true },
      { key: 'password', label: 'API Password', placeholder: 'your-password', sensitive: true, required: true },
      { key: 'application_id', label: 'Messaging Application ID', placeholder: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', sensitive: false, required: true },
      { key: 'from_number', label: 'From Number', placeholder: '+13035551234', sensitive: false, required: true },
    ],
    supportsSms: true, supportsMms: true, supportsVoice: true, supportsRecording: true, supportsTranscription: false,
  },
  {
    type: 'plivo',
    label: 'Plivo',
    description: 'Good international reach (190+ countries). ~$0.005/SMS, $0.05/min voice.',
    fields: [
      { key: 'auth_id', label: 'Auth ID', placeholder: 'MAxxxxxxxxxxxxxxxxxxxxxxxx', sensitive: false, required: true },
      { key: 'auth_token', label: 'Auth Token', placeholder: 'your-auth-token', sensitive: true, required: true },
      { key: 'from_number', label: 'From Number', placeholder: '+13035551234', sensitive: false, required: true },
    ],
    supportsSms: true, supportsMms: true, supportsVoice: true, supportsRecording: true, supportsTranscription: false,
  },
  {
    type: 'vonage',
    label: 'Vonage (Nexmo)',
    description: 'Per-second voice billing. Messages API. ~$0.008/SMS, $0.016/MMS.',
    fields: [
      { key: 'api_key', label: 'API Key', placeholder: 'abcdef12', sensitive: false, required: true },
      { key: 'api_secret', label: 'API Secret', placeholder: 'your-api-secret', sensitive: true, required: true },
      { key: 'from_number', label: 'From Number', placeholder: '+13035551234', sensitive: false, required: true },
      { key: 'signature_secret', label: 'Signature Secret (webhooks)', placeholder: 'From Settings → Signature secret', sensitive: true, required: false },
      { key: 'application_id', label: 'Application ID (voice)', placeholder: 'Optional — for voice', sensitive: false, required: false },
      { key: 'private_key', label: 'Private Key (voice)', placeholder: 'Optional — RSA key for voice JWT', sensitive: true, required: false },
    ],
    supportsSms: true, supportsMms: true, supportsVoice: true, supportsRecording: true, supportsTranscription: false,
  },
];
