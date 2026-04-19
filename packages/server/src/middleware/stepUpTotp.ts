/**
 * SEC-H56: Step-up TOTP middleware for PII export endpoints.
 *
 * Requires the caller to supply a valid `X-TOTP-Code: <6-digit>` header.
 * Uses the same decryption + verify path as auth.routes.ts (decryptTotpSecret +
 * verifySync from otplib) so there is exactly one TOTP-verify code path.
 *
 * Gate logic:
 *  - User has no 2FA enrolled → 403 "Step-up auth requires 2FA enrollment"
 *  - Header missing            → 401 "Step-up TOTP required"
 *  - Code present but invalid  → 401 "Invalid TOTP"
 *  - Code valid                → calls next(); fires audit + email side-effects
 */

import crypto from 'crypto';
import { Request, Response, NextFunction } from 'express';
import { verifySync } from 'otplib';
import { config } from '../config.js';
import { audit } from '../utils/audit.js';
import { sendEmail } from '../services/email.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('step-up-totp');

// ---------------------------------------------------------------------------
// TOTP secret decryption — mirrors auth.routes.ts `decryptSecret` exactly.
// Keys match the derivation in auth.routes.ts; inlined here to avoid a
// circular import (auth.routes.ts imports middleware/auth.ts, which would
// create a cycle if we imported from auth.routes.ts).
// ---------------------------------------------------------------------------

const TOTP_DECRYPT_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':totp:v1').digest(),
  2: crypto
    .createHash('sha256')
    .update(config.jwtSecret + ':totp-encryption:v2:' + config.superAdminSecret)
    .digest(),
};

// v3 key via HKDF — matches auth.routes.ts SEC-M51
const V3_KEY = crypto.hkdfSync(
  'sha256',
  Buffer.from(config.jwtSecret + config.superAdminSecret, 'utf8'),
  Buffer.from('bizarre-totp-salt-v3', 'utf8'),
  Buffer.from('totp-key-v3', 'utf8'),
  32,
);
(TOTP_DECRYPT_KEYS as Record<number, Buffer>)[3] = Buffer.from(V3_KEY);

function decryptTotpSecret(ciphertext: string): string {
  // Legacy unencrypted (plain base32)
  if (!ciphertext.includes(':')) return ciphertext;

  // Legacy v0 format (no version prefix): iv:tag:data
  if (!ciphertext.startsWith('v')) {
    const key = crypto.createHash('sha256').update(config.jwtSecret).digest();
    const [ivHex, tagHex, encHex] = ciphertext.split(':');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
    return decipher.update(Buffer.from(encHex, 'hex')) + decipher.final('utf8');
  }

  // Versioned format: v{n}:{iv}:{tag}:{data}
  const [vStr, ivHex, tagHex, encHex] = ciphertext.split(':');
  const version = parseInt(vStr.slice(1), 10);
  const key = TOTP_DECRYPT_KEYS[version];
  if (!key) throw new Error(`Unknown TOTP encryption key version: ${version}`);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  // SEC-M51: v3+ ciphertexts were encrypted with AAD = `v{version}`
  if (version >= 3) {
    decipher.setAAD(Buffer.from(`v${version}`));
  }
  return decipher.update(Buffer.from(encHex, 'hex')) + decipher.final('utf8');
}

// ---------------------------------------------------------------------------
// Email notification (fire-and-forget)
// ---------------------------------------------------------------------------

function firePiiExportEmail(
  db: unknown,
  userEmail: string | undefined,
  endpoint: string,
  ip: string,
  userAgent: string,
  timestamp: string,
): void {
  if (!userEmail) return;

  const body = `
<p>A PII export was completed on your BizarreCRM account.</p>
<ul>
  <li><strong>Endpoint:</strong> ${endpoint}</li>
  <li><strong>IP address:</strong> ${ip}</li>
  <li><strong>User-Agent:</strong> ${userAgent}</li>
  <li><strong>Timestamp (UTC):</strong> ${timestamp}</li>
</ul>
<p>If you did not perform this export, contact your system administrator immediately.</p>
`.trim();

  sendEmail(db, {
    to: userEmail,
    subject: 'BizarreCRM: PII export completed',
    html: body,
  }).catch((err: unknown) => {
    log.error('Failed to send PII export email', { error: err });
  });
}

// ---------------------------------------------------------------------------
// Middleware factory
// ---------------------------------------------------------------------------

/**
 * Returns an Express middleware that enforces step-up TOTP verification.
 *
 * @param endpointLabel  Human-readable label used in audit + email body.
 */
export function requireStepUpTotp(endpointLabel: string) {
  return async function stepUpTotpMiddleware(
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    const user = req.user;
    if (!user) {
      res.status(401).json({ success: false, message: 'Not authenticated' });
      return;
    }

    const db = (req as any).db as import('better-sqlite3').Database;
    const ip = req.ip || 'unknown';
    const userAgent = req.headers['user-agent'] || 'unknown';
    const timestamp = new Date().toISOString();

    // ── 1. Look up totp_secret + totp_enabled for the current user ──────────
    const dbUser = db
      .prepare('SELECT email, totp_secret, totp_enabled FROM users WHERE id = ? AND is_active = 1')
      .get(user.id) as { email: string | null; totp_secret: string | null; totp_enabled: number } | undefined;

    if (!dbUser) {
      res.status(401).json({ success: false, message: 'Not authenticated' });
      return;
    }

    // ── 2. 2FA not enrolled → hard gate ────────────────────────────────────
    if (!dbUser.totp_enabled || !dbUser.totp_secret) {
      res.status(403).json({
        success: false,
        message: 'Step-up auth requires 2FA enrollment',
        hint: 'Enable two-factor authentication in your account settings before using PII export.',
      });
      return;
    }

    // ── 3. Header missing → prompt ──────────────────────────────────────────
    const rawCode = req.headers['x-totp-code'];
    const totpCode = typeof rawCode === 'string' ? rawCode.trim() : '';

    if (!totpCode) {
      res.status(401).json({ success: false, message: 'Step-up TOTP required' });
      return;
    }

    // ── 4. Validate format ──────────────────────────────────────────────────
    if (!/^\d{6}$/.test(totpCode)) {
      res.status(401).json({ success: false, message: 'Invalid TOTP' });
      return;
    }

    // ── 5. Decrypt + verify ─────────────────────────────────────────────────
    let valid = false;
    try {
      const secret = decryptTotpSecret(dbUser.totp_secret);
      valid = Boolean(verifySync({ token: totpCode, secret }));
    } catch (err) {
      log.error('TOTP decryption failed during step-up', { userId: user.id, error: err });
      valid = false;
    }

    if (!valid) {
      audit(db, 'pii_export_totp_failed', user.id, ip, { endpoint: endpointLabel, user_agent: userAgent });
      res.status(401).json({ success: false, message: 'Invalid TOTP' });
      return;
    }

    // ── 6. Success — audit + email (fire-and-forget) + continue ────────────
    const meta = { endpoint: endpointLabel, ip, user_agent: userAgent, timestamp };
    audit(db, 'pii_export_success', user.id, ip, meta);

    firePiiExportEmail(db, dbUser.email ?? undefined, endpointLabel, ip, userAgent, timestamp);

    next();
  };
}
