import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage } from './types.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('sms:console');

/**
 * Dev-only SMS provider. Logs outbound messages to the server console and
 * returns `{ success: false, simulated: true }` so callers can distinguish
 * a simulated send from a real one. Nothing is actually transmitted.
 *
 * Callers MUST check `result.success` / `result.simulated` before marking
 * messages as delivered or incrementing usage counters.
 */
export class ConsoleProvider implements SmsProvider {
  name = 'console';

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const type = media && media.length > 0 ? 'MMS' : 'SMS';
    // Keep console output for dev visibility — this is the whole point of the
    // console provider. Structured logger also records the event.
    console.log(`[${type}:console] From: ${from || 'store'} -> To: ${to}`);
    console.log(`[${type}:console] Body: ${body}`);
    if (media && media.length > 0) {
      console.log(`[${type}:console] Media: ${media.map(m => `${m.contentType}: ${m.url}`).join(', ')}`);
    }
    console.log(`[${type}:console] (Message NOT actually sent — using console provider)`);

    logger.warn('simulated send — console provider is dev-only, no real SMS/MMS was sent', {
      to,
      from: from || null,
      messageType: type,
      mediaCount: media?.length ?? 0,
    });

    return {
      success: false,
      simulated: true,
      error: 'Console provider is for dev only — no SMS sent',
      providerName: 'console',
      providerId: `console-${Date.now()}`,
    };
  }

  parseInboundWebhook(_req: any): InboundMessage | null {
    return null;
  }
}
