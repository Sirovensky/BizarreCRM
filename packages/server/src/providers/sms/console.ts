import { SmsProvider, SmsProviderResult, MmsMedia, InboundMessage } from './types.js';

export class ConsoleProvider implements SmsProvider {
  name = 'console';

  async send(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
    const type = media && media.length > 0 ? 'MMS' : 'SMS';
    console.log(`[${type}:console] From: ${from || 'store'} -> To: ${to}`);
    console.log(`[${type}:console] Body: ${body}`);
    if (media && media.length > 0) {
      console.log(`[${type}:console] Media: ${media.map(m => `${m.contentType}: ${m.url}`).join(', ')}`);
    }
    console.log(`[${type}:console] (Message NOT actually sent — using console provider)`);
    return { success: true, providerName: 'console', providerId: `console-${Date.now()}` };
  }

  parseInboundWebhook(_req: any): InboundMessage | null {
    return null;
  }
}
