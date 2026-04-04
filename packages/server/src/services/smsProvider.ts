/**
 * SMS Provider abstraction layer.
 *
 * Implement the SmsProvider interface for your chosen provider (Twilio, Telnyx, etc.)
 * and register it via setSmsProvider(). The rest of the CRM calls sendSms() which
 * delegates to whatever provider is active.
 */

export interface SmsProviderResult {
  success: boolean;
  providerId?: string;      // Provider's message ID
  providerName: string;     // 'twilio', 'telnyx', 'console', etc.
  error?: string;
}

export interface SmsProvider {
  name: string;
  send(to: string, body: string, from?: string): Promise<SmsProviderResult>;
  // Optional: receive webhook handler (for inbound SMS)
  parseInboundWebhook?(req: any): { from: string; to: string; body: string; providerId?: string } | null;
}

// Console provider — logs to stdout, doesn't actually send
class ConsoleProvider implements SmsProvider {
  name = 'console';
  async send(to: string, body: string, from?: string): Promise<SmsProviderResult> {
    console.log(`[SMS:console] From: ${from || 'store'} -> To: ${to}`);
    console.log(`[SMS:console] Body: ${body}`);
    console.log(`[SMS:console] (Message NOT actually sent — using console provider)`);
    return { success: true, providerName: 'console', providerId: `console-${Date.now()}` };
  }
}

// Twilio provider stub (ready for real implementation)
class TwilioProvider implements SmsProvider {
  name = 'twilio';
  private accountSid: string;
  private authToken: string;
  private fromNumber: string;

  constructor(accountSid: string, authToken: string, fromNumber: string) {
    this.accountSid = accountSid;
    this.authToken = authToken;
    this.fromNumber = fromNumber;
  }

  async send(to: string, body: string, from?: string): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;
    try {
      // Using fetch directly to avoid adding twilio SDK dependency
      const url = `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`;
      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': 'Basic ' + Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64'),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({ To: to, From: sendFrom, Body: body }).toString(),
      });
      const data = await resp.json() as any;
      if (!resp.ok) {
        return { success: false, providerName: 'twilio', error: data.message || `HTTP ${resp.status}` };
      }
      return { success: true, providerName: 'twilio', providerId: data.sid };
    } catch (err: any) {
      return { success: false, providerName: 'twilio', error: err.message };
    }
  }

  parseInboundWebhook(req: any) {
    const { From, To, Body, MessageSid } = req.body || {};
    if (!From || !Body) return null;
    return { from: From, to: To, body: Body, providerId: MessageSid };
  }
}

// Telnyx provider stub
class TelnyxProvider implements SmsProvider {
  name = 'telnyx';
  private apiKey: string;
  private fromNumber: string;

  constructor(apiKey: string, fromNumber: string) {
    this.apiKey = apiKey;
    this.fromNumber = fromNumber;
  }

  async send(to: string, body: string, from?: string): Promise<SmsProviderResult> {
    const sendFrom = from || this.fromNumber;
    try {
      const resp = await fetch('https://api.telnyx.com/v2/messages', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ from: sendFrom, to, text: body, type: 'SMS' }),
      });
      const data = await resp.json() as any;
      if (!resp.ok) {
        return { success: false, providerName: 'telnyx', error: data.errors?.[0]?.detail || `HTTP ${resp.status}` };
      }
      return { success: true, providerName: 'telnyx', providerId: data.data?.id };
    } catch (err: any) {
      return { success: false, providerName: 'telnyx', error: err.message };
    }
  }

  parseInboundWebhook(req: any) {
    const payload = req.body?.data?.payload;
    if (!payload) return null;
    return { from: payload.from?.phone_number, to: payload.to?.[0]?.phone_number, body: payload.text, providerId: payload.id };
  }
}

// --- Module-level state ---
let activeProvider: SmsProvider = new ConsoleProvider();

export function setSmsProvider(provider: SmsProvider): void {
  console.log(`[SMS] Provider set to: ${provider.name}`);
  activeProvider = provider;
}

export function getSmsProvider(): SmsProvider {
  return activeProvider;
}

export function sendSms(to: string, body: string, from?: string): Promise<SmsProviderResult> {
  return activeProvider.send(to, body, from);
}

// Factory — call from server startup based on config
export function initSmsProvider(conf: {
  provider?: string;
  twilio?: { accountSid: string; authToken: string; fromNumber: string };
  telnyx?: { apiKey: string; fromNumber: string };
}): SmsProvider {
  const name = conf.provider || 'console';

  switch (name) {
    case 'twilio':
      if (!conf.twilio?.accountSid || !conf.twilio?.authToken || !conf.twilio?.fromNumber) {
        console.warn('[SMS] Twilio config incomplete — falling back to console provider');
        activeProvider = new ConsoleProvider();
      } else {
        activeProvider = new TwilioProvider(conf.twilio.accountSid, conf.twilio.authToken, conf.twilio.fromNumber);
      }
      break;
    case 'telnyx':
      if (!conf.telnyx?.apiKey || !conf.telnyx?.fromNumber) {
        console.warn('[SMS] Telnyx config incomplete — falling back to console provider');
        activeProvider = new ConsoleProvider();
      } else {
        activeProvider = new TelnyxProvider(conf.telnyx.apiKey, conf.telnyx.fromNumber);
      }
      break;
    default:
      activeProvider = new ConsoleProvider();
  }

  console.log(`[SMS] Provider initialized: ${activeProvider.name}`);
  return activeProvider;
}
