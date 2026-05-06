import crypto from 'crypto';
import {
  BizarreSmsConfig,
  DeliveryStatus,
  InboundMessage,
  MmsMedia,
  SmsProvider,
  SmsProviderResult,
} from './types.js';
import { createBreaker } from '../../utils/circuitBreaker.js';

const bizarreSmsBreaker = createBreaker('bizarresms');

function cleanBaseUrl(url: string): string {
  return url.replace(/\/+$/, '');
}

function safeError(data: any, fallback: string): string {
  if (data && typeof data === 'object') {
    const message = data.message || data.error || data.error_description;
    if (typeof message === 'string' && message.trim()) return message.slice(0, 300);
  }
  return fallback;
}

export class BizarreSmsProvider implements SmsProvider {
  name = 'bizarresms';
  private relayUrl: string;
  private relayToken: string;
  private webhookSecret: string;
  private tenantSlug: string | null;
  private fromNumber: string;

  constructor(cfg: BizarreSmsConfig) {
    this.relayUrl = cfg.relayUrl.trim();
    this.relayToken = cfg.relayToken.trim();
    this.webhookSecret = (cfg.webhookSecret || '').trim();
    this.tenantSlug = cfg.tenantSlug || null;
    this.fromNumber = cfg.fromNumber || '';
  }

  isConfigured(): boolean {
    return Boolean(this.relayUrl && this.relayToken);
  }

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    if (!this.isConfigured()) {
      return {
        success: false,
        providerName: this.name,
        error: 'BizarreSMS relay is not configured. Set BIZARRESMS_RELAY_URL and BIZARRESMS_RELAY_TOKEN.',
      };
    }
    if (media && media.length > 0) {
      return {
        success: false,
        providerName: this.name,
        error: 'BizarreSMS relay does not support MMS yet. Use a BYO provider for MMS.',
      };
    }

    try {
      const response = await bizarreSmsBreaker.run(() =>
        fetch(`${cleanBaseUrl(this.relayUrl)}/v1/messages`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${this.relayToken}`,
            'Content-Type': 'application/json',
            'X-Bizarre-Tenant': this.tenantSlug || '',
          },
          body: JSON.stringify({
            tenant_slug: this.tenantSlug,
            to,
            from: from || this.fromNumber || undefined,
            body,
          }),
          signal: AbortSignal.timeout(15000),
        }),
      );

      const data = (await response.json().catch(() => null)) as any;
      if (!response.ok) {
        return {
          success: false,
          providerName: this.name,
          error: safeError(data, `BizarreSMS relay failed (HTTP ${response.status})`),
        };
      }

      return {
        success: data?.success !== false,
        providerName: this.name,
        providerId: data?.id || data?.message_id || data?.provider_id,
        error: data?.success === false ? safeError(data, 'BizarreSMS relay rejected the message') : undefined,
      };
    } catch (err: any) {
      return { success: false, providerName: this.name, error: err?.message || 'BizarreSMS relay error' };
    }
  }

  parseInboundWebhook(req: any): InboundMessage | null {
    const body = req.body || {};
    const from = body.from || body.From;
    const to = body.to || body.To;
    const message = body.body || body.message || body.Body || '';
    const providerId = body.id || body.message_id || body.provider_id || body.MessageSid;
    if (!from || !to) return null;
    return {
      from,
      to,
      body: message,
      providerId,
      messageType: 'sms',
    };
  }

  verifyWebhookSignature(req: any): boolean {
    if (!this.webhookSecret) return false;
    const signature = String(req.headers['x-bizarresms-signature'] || '');
    if (!signature) return false;
    const raw = (req as any).rawBody
      ? Buffer.isBuffer((req as any).rawBody)
        ? (req as any).rawBody
        : Buffer.from(String((req as any).rawBody))
      : Buffer.from(JSON.stringify(req.body || {}));
    const expected = crypto
      .createHmac('sha256', this.webhookSecret)
      .update(raw)
      .digest('hex');
    const normalized = signature.startsWith('sha256=')
      ? signature.slice('sha256='.length)
      : signature;
    const sigBuf = Buffer.from(normalized, 'hex');
    const expBuf = Buffer.from(expected, 'hex');
    return sigBuf.length === expBuf.length && crypto.timingSafeEqual(sigBuf, expBuf);
  }

  parseStatusWebhook(req: any): DeliveryStatus | null {
    const body = req.body || {};
    const providerId = body.id || body.message_id || body.provider_id || body.MessageSid;
    const status = body.status || body.message_status || body.MessageStatus;
    if (!providerId || !status) return null;
    return {
      providerId,
      status,
      errorCode: body.error_code || body.ErrorCode,
      errorMessage: body.error_message || body.ErrorMessage,
    };
  }
}
