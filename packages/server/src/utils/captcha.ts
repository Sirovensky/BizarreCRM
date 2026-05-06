import crypto from 'crypto';
import { config } from '../config.js';
import type { AsyncDb } from '../db/async-db.js';
import { createLogger } from './logger.js';

const log = createLogger('captcha');

const CAPTCHA_VERIFY_TIMEOUT_MS = 8_000;

export type CaptchaProvider = 'hcaptcha' | 'turnstile' | 'recaptcha';

export interface PublicCaptchaConfig {
  enabled: boolean;
  provider?: CaptchaProvider;
  site_key?: string;
}

interface CaptchaVerifyResponse {
  success?: boolean;
  challenge_ts?: string;
  hostname?: string;
  score?: number;
  action?: string;
  'error-codes'?: string[];
}

const VERIFY_URLS: Record<CaptchaProvider, string> = {
  hcaptcha: 'https://api.hcaptcha.com/siteverify',
  turnstile: 'https://challenges.cloudflare.com/turnstile/v0/siteverify',
  recaptcha: 'https://www.google.com/recaptcha/api/siteverify',
};

export function getPortalCaptchaPublicConfig(): PublicCaptchaConfig {
  if (!config.portalCaptchaEnabled || !config.portalCaptchaProvider || !config.portalCaptchaSiteKey) {
    return { enabled: false };
  }

  return {
    enabled: true,
    provider: config.portalCaptchaProvider,
    site_key: config.portalCaptchaSiteKey,
  };
}

export async function verifyPortalCaptchaToken(
  token: unknown,
  remoteIp: string,
): Promise<{ ok: boolean; reason?: string }> {
  if (!config.portalCaptchaEnabled || !config.portalCaptchaProvider || !config.portalCaptchaSecret) {
    return { ok: true };
  }

  const responseToken = typeof token === 'string' ? token.trim() : '';
  if (!responseToken) {
    return { ok: false, reason: 'Verification check is required' };
  }

  const provider = config.portalCaptchaProvider;
  const body = new URLSearchParams({
    secret: config.portalCaptchaSecret,
    response: responseToken,
  });
  if (remoteIp && remoteIp !== 'unknown') {
    body.set('remoteip', remoteIp);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), CAPTCHA_VERIFY_TIMEOUT_MS);

  try {
    const response = await fetch(VERIFY_URLS[provider], {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
      signal: controller.signal,
    });

    if (!response.ok) {
      log.warn('captcha provider returned non-2xx status', {
        provider,
        remoteIp,
        status: response.status,
      });
      return { ok: false, reason: 'Verification check failed' };
    }

    const result = await response.json() as CaptchaVerifyResponse;
    const recaptchaScoreOk = provider !== 'recaptcha'
      || config.portalRecaptchaMinScore <= 0
      || typeof result.score !== 'number'
      || result.score >= config.portalRecaptchaMinScore;

    if (result.success === true && recaptchaScoreOk) {
      return { ok: true };
    }

    log.warn('captcha provider rejected token', {
      provider,
      remoteIp,
      hostname: result.hostname,
      score: result.score,
      action: result.action,
      errors: result['error-codes'] ?? [],
    });
    return { ok: false, reason: 'Verification check failed' };
  } catch (err: unknown) {
    log.warn('captcha verification request failed', {
      provider,
      remoteIp,
      error: err instanceof Error ? err.message : String(err),
    });
    return { ok: false, reason: 'Verification check failed' };
  } finally {
    clearTimeout(timeout);
  }
}

function formatSqliteUtc(value: Date): string {
  return value.toISOString().slice(0, 19).replace('T', ' ');
}

export function hashPortalCaptchaIp(ip: string): string {
  return crypto.createHash('sha256').update(ip || 'unknown').digest('hex');
}

export async function hasFreshPortalCaptchaIp(adb: AsyncDb, ip: string): Promise<boolean> {
  const ipHash = hashPortalCaptchaIp(ip);
  await adb.run('DELETE FROM portal_captcha_seen_ips WHERE expires_at <= datetime(\'now\')');
  const row = await adb.get<{ ip_hash: string }>(
    'SELECT ip_hash FROM portal_captcha_seen_ips WHERE ip_hash = ? AND expires_at > datetime(\'now\')',
    ipHash,
  );
  return !!row;
}

export async function rememberPortalCaptchaIp(adb: AsyncDb, ip: string): Promise<void> {
  const ipHash = hashPortalCaptchaIp(ip);
  const ttlMs = config.portalCaptchaSeenIpTtlHours * 60 * 60 * 1000;
  const expiresAt = formatSqliteUtc(new Date(Date.now() + ttlMs));
  await adb.run(`
    INSERT INTO portal_captcha_seen_ips (ip_hash, provider, first_seen_at, last_seen_at, expires_at)
    VALUES (?, ?, datetime('now'), datetime('now'), ?)
    ON CONFLICT(ip_hash) DO UPDATE SET
      provider = excluded.provider,
      last_seen_at = datetime('now'),
      expires_at = excluded.expires_at
  `, ipHash, config.portalCaptchaProvider || 'unknown', expiresAt);
}
