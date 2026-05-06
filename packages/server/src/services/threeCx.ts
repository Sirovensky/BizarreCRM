import { getConfigValue } from '../utils/configEncryption.js';
import { createBreaker } from '../utils/circuitBreaker.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('3cx');
const threeCxBreaker = createBreaker('3cx');

export interface ThreeCxConfig {
  host: string;
  clientId: string;
  clientSecret: string;
  dnNumber: string;
}

export interface ThreeCxCallResult {
  success: boolean;
  providerName: '3cx';
  callId?: string;
  status?: string;
  error?: string;
}

function trimSlash(value: string): string {
  return value.replace(/\/+$/, '');
}

function normalizeHost(raw: string): string {
  const value = raw.trim();
  if (!value) return '';
  const withProtocol = /^https?:\/\//i.test(value) ? value : `https://${value}`;
  const parsed = new URL(withProtocol);
  if (!['https:', 'http:'].includes(parsed.protocol)) {
    throw new Error('3CX host must be an http(s) URL');
  }
  parsed.pathname = parsed.pathname.replace(/\/+$/, '');
  parsed.search = '';
  parsed.hash = '';
  return trimSlash(parsed.toString());
}

export function getThreeCxConfig(db: any): ThreeCxConfig | null {
  try {
    const host = normalizeHost(getConfigValue(db, 'tcx_host') || '');
    const extension = (getConfigValue(db, 'tcx_extension') || '').trim();
    const legacyClientId = (getConfigValue(db, 'tcx_username') || '').trim();
    const clientSecret = (getConfigValue(db, 'tcx_password') || '').trim();
    const clientId = legacyClientId || extension;

    if (!host || !clientId || !clientSecret || !extension) return null;
    return { host, clientId, clientSecret, dnNumber: extension };
  } catch (err) {
    logger.warn('3CX config invalid', { error: err instanceof Error ? err.message : String(err) });
    return null;
  }
}

export function isThreeCxConfigured(db: any): boolean {
  return getThreeCxConfig(db) !== null;
}

async function requestAccessToken(cfg: ThreeCxConfig): Promise<string> {
  const body = new URLSearchParams();
  body.set('client_id', cfg.clientId);
  body.set('client_secret', cfg.clientSecret);
  body.set('grant_type', 'client_credentials');

  const response = await threeCxBreaker.run(() =>
    fetch(`${cfg.host}/connect/token`, {
      method: 'POST',
      headers: {
        'Authorization': 'Basic ' + Buffer.from(`${cfg.clientId}:${cfg.clientSecret}`).toString('base64'),
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: body.toString(),
      signal: AbortSignal.timeout(15_000),
    }),
  );

  const data = await response.json().catch(() => ({})) as any;
  if (!response.ok) {
    throw new Error(data.error_description || data.error || `3CX token HTTP ${response.status}`);
  }
  if (!data.access_token || typeof data.access_token !== 'string') {
    throw new Error('3CX token response did not include access_token');
  }
  return data.access_token;
}

export async function initiateThreeCxCall(
  db: any,
  to: string,
  attachedData: Record<string, string | number | null | undefined> = {},
): Promise<ThreeCxCallResult> {
  const cfg = getThreeCxConfig(db);
  if (!cfg) {
    return { success: false, providerName: '3cx', error: '3CX is not configured' };
  }

  try {
    const token = await requestAccessToken(cfg);
    const payload = {
      destination: to,
      timeout: 30,
      attacheddata: Object.fromEntries(
        Object.entries(attachedData)
          .filter(([, value]) => value !== undefined && value !== null)
          .map(([key, value]) => [key, String(value)]),
      ),
    };

    const response = await threeCxBreaker.run(() =>
      fetch(`${cfg.host}/callcontrol/${encodeURIComponent(cfg.dnNumber)}/makecall`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15_000),
      }),
    );

    const data = await response.json().catch(() => ({})) as any;
    if (!response.ok) {
      const reason = data.reasontext || data.reason || data.message || `3CX makecall HTTP ${response.status}`;
      return { success: false, providerName: '3cx', error: reason };
    }

    const result = data.result || data;
    const callId = result.callid ?? result.callId ?? result.id ?? data.callid ?? data.id;
    return {
      success: true,
      providerName: '3cx',
      callId: callId != null ? String(callId) : undefined,
      status: data.finalstatus || result.status || 'accepted',
    };
  } catch (err) {
    return {
      success: false,
      providerName: '3cx',
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
