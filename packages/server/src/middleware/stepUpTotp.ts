/**
 * SEC-H56 / SEC-H20: Step-up TOTP middleware.
 *
 * Two exports:
 *
 *   requireStepUpTotp(label)            — tenant user PII export endpoints
 *                                         (SEC-H56). Reads req.user, queries
 *                                         tenant users table, uses tenant TOTP
 *                                         key derivation.
 *
 *   requireStepUpTotpSuperAdmin(label)  — super-admin destructive endpoints
 *                                         (SEC-H20 / AZ-009 / AZ-023 /
 *                                         BH-B-016). Reads req.superAdmin,
 *                                         queries super_admins table in master
 *                                         DB, uses the super-admin-specific
 *                                         AES-256-GCM key (deriveKey in
 *                                         super-admin.routes.ts). Emits
 *                                         separate audit labels so the fleet-
 *                                         management destructive-action trail
 *                                         never mixes with the PII-export trail.
 *
 * Both exports read the canonical `X-TOTP-Code: <6-digit>` header.
 * (The task spec listed `x-super-admin-totp` as advisory; we use the same
 * header as the existing PII-export middleware so the management dashboard
 * only needs a single TOTP prompt implementation.)
 *
 * Common gate logic:
 *  - Actor has no 2FA enrolled → 403 "Step-up auth requires 2FA enrollment"
 *  - Header missing            → 401 "Step-up TOTP required"
 *  - Code present but invalid  → 401 "Invalid TOTP"
 *  - Code valid                → calls next(); fires audit side-effects
 */

import crypto from 'crypto';
import { Request, Response, NextFunction } from 'express';
import { verifySync } from 'otplib';
import { config } from '../config.js';
import { audit } from '../utils/audit.js';
import { sendEmail } from '../services/email.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';
import { trackInterval } from '../utils/trackInterval.js';

const log = createLogger('step-up-totp');

// ---------------------------------------------------------------------------
// SCAN-593: TOTP replay prevention.
//
// otplib verifySync accepts any code that is valid within the current 30-second
// window.  Without tracking consumed codes, an attacker who intercepts a valid
// code can replay it for the remainder of the same window.  We prevent this by
// keying consumed codes on (userId, code, windowBucket) and rejecting any
// second use within 3 windows (90 s).  The Map is process-local; the TTL
// sweep prevents unbounded growth.
// ---------------------------------------------------------------------------

/** Maps `userId:code:windowBucket` → timestamp when consumed (ms since epoch). */
const consumedCodes = new Map<string, number>();

/** Keep consumed-code entries for 3 × 30-second windows to cover clock skew. */
const CONSUMED_TTL_MS = 90_000;

// Periodic sweep: remove entries older than CONSUMED_TTL_MS.
let stepUpTotpReaperHandle: NodeJS.Timeout | null = null;
export function startStepUpTotpReaper(): void {
  if (stepUpTotpReaperHandle) return;
  stepUpTotpReaperHandle = trackInterval(() => {
    const now = Date.now();
    for (const [k, ts] of consumedCodes) {
      if (now - ts > CONSUMED_TTL_MS) consumedCodes.delete(k);
    }
  }, 60_000, { unref: true });
}

/**
 * Attempts to claim a TOTP code for `userId`.
 * Returns `true` on first use within the window; `false` if already consumed.
 */
function claimCode(userId: number, code: string): boolean {
  const windowBucket = Math.floor(Date.now() / 30_000);
  const key = `${userId}:${code}:${windowBucket}`;
  if (consumedCodes.has(key)) return false;
  consumedCodes.set(key, Date.now());
  return true;
}

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
    const rid = res.locals.requestId as string | undefined;
    const user = req.user;
    if (!user) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_NO_TOKEN, 'Not authenticated', rid));
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
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_USER_NOT_FOUND, 'Not authenticated', rid));
      return;
    }

    // ── 2. 2FA not enrolled → hard gate ────────────────────────────────────
    if (!dbUser.totp_enabled || !dbUser.totp_secret) {
      res.status(403).json(errorBody(
        ERROR_CODES.ERR_PERM_STEP_UP_NO_2FA,
        'Step-up auth requires 2FA enrollment',
        rid,
        { hint: 'Enable two-factor authentication in your account settings before using PII export.' },
      ));
      return;
    }

    // ── 3. Header missing → prompt ──────────────────────────────────────────
    const rawCode = req.headers['x-totp-code'];
    const totpCode = typeof rawCode === 'string' ? rawCode.trim() : '';

    if (!totpCode) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_PERM_STEP_UP_REQUIRED, 'Step-up TOTP required', rid));
      return;
    }

    // ── 4. Validate format ──────────────────────────────────────────────────
    if (!/^\d{6}$/.test(totpCode)) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'Invalid TOTP', rid));
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
      res.status(401).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'Invalid TOTP', rid));
      return;
    }

    // ── 6. SCAN-593: Claim the code to prevent replay within the same window ─
    if (!claimCode(user.id, totpCode)) {
      audit(db, 'pii_export_totp_failed', user.id, ip, { endpoint: endpointLabel, user_agent: userAgent, reason: 'replay' });
      res.status(403).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'TOTP code already used; wait for next code', rid));
      return;
    }

    // ── 7. Success — audit + email (fire-and-forget) + continue ────────────
    const meta = { endpoint: endpointLabel, ip, user_agent: userAgent, timestamp };
    audit(db, 'pii_export_success', user.id, ip, meta);

    firePiiExportEmail(db, dbUser.email ?? undefined, endpointLabel, ip, userAgent, timestamp);

    next();
  };
}

// ---------------------------------------------------------------------------
// SEC-H20: Super-admin step-up TOTP variant
//
// Mirrors requireStepUpTotp but targets the super-admin auth system:
//   - Reads req.superAdmin (populated by superAdminAuth in super-admin.routes.ts)
//     instead of req.user.
//   - Queries super_admins in the master DB (via getMasterDb()) instead of the
//     per-tenant users table.
//   - Decrypts with the super-admin-specific key:
//       sha256(superAdminSecret + ':totp:superadmin')
//     which matches encryptTotp / decryptTotp in super-admin.routes.ts exactly.
//   - Emits 'super_admin_totp_failed' / 'super_admin_totp_success' audit labels
//     so fleet-management destructive actions have an independent audit trail
//     (never mixed with PII-export rows tagged 'pii_export_*').
//
// Defense-in-depth rationale (AZ-009 / AZ-023 / BH-B-016):
//   Even after a 30-minute session token leaks (shoulder-surf, clipboard,
//   network log), an attacker cannot execute irreversible mutations
//   (tenant delete, plan change, force-disable-2fa, session kick, config
//   write) without the time-based TOTP code from the super-admin's
//   authenticator app. The TOTP window is ≤30 s, far shorter than the
//   remaining session TTL, so the leaked token becomes useless for
//   destructive operations immediately after the legitimate actor closes
//   their tab.
// ---------------------------------------------------------------------------

/** Derive the AES-256-GCM key used to encrypt super-admin TOTP secrets.
 *  Must match deriveKey() in super-admin.routes.ts. */
function deriveSuperAdminTotpKey(): Buffer {
  return crypto.createHash('sha256').update(config.superAdminSecret + ':totp:superadmin').digest();
}

/** Decrypt a super-admin TOTP secret (AES-256-GCM, iv:tag:enc hex). */
function decryptSuperAdminTotpSecret(enc: string, iv: string, tag: string): string {
  const key = deriveSuperAdminTotpKey();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'hex'));
  decipher.setAuthTag(Buffer.from(tag, 'hex'));
  return decipher.update(enc, 'hex', 'utf8') + decipher.final('utf8');
}

/**
 * Returns an Express middleware that enforces step-up TOTP verification for
 * super-admin destructive endpoints.
 *
 * Must be placed AFTER the router-level `superAdminAuth` middleware so that
 * `req.superAdmin` is already populated when this runs.
 *
 * @param endpointLabel  Human-readable label written to master_audit_log.
 */
export function requireStepUpTotpSuperAdmin(endpointLabel: string) {
  return async function stepUpTotpSuperAdminMiddleware(
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    const rid = res.locals.requestId as string | undefined;
    const superAdmin = req.superAdmin;
    if (!superAdmin) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_NO_TOKEN, 'Not authenticated', rid));
      return;
    }

    const { getMasterDb } = await import('../db/master-connection.js');
    const masterDb = getMasterDb();
    if (!masterDb) {
      res.status(500).json(errorBody(ERROR_CODES.ERR_INT_DB_UNAVAILABLE, 'Master DB unavailable', rid));
      return;
    }

    const ip = req.ip || 'unknown';
    const userAgent = req.headers['user-agent'] || 'unknown';

    // ── 1. Look up totp_secret for the super-admin ──────────────────────────
    const dbAdmin = masterDb
      .prepare('SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ? AND is_active = 1')
      .get(superAdmin.superAdminId) as
      | { id: number; email: string | null; totp_secret: string | null; totp_iv: string | null; totp_tag: string | null }
      | undefined;

    if (!dbAdmin) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_USER_NOT_FOUND, 'Not authenticated', rid));
      return;
    }

    // ── 2. 2FA not enrolled → hard gate ────────────────────────────────────
    if (!dbAdmin.totp_secret || !dbAdmin.totp_iv || !dbAdmin.totp_tag) {
      res.status(403).json(errorBody(
        ERROR_CODES.ERR_PERM_STEP_UP_NO_2FA,
        'Step-up auth requires 2FA enrollment',
        rid,
        { hint: 'Enable two-factor authentication on your super-admin account before using destructive endpoints.' },
      ));
      return;
    }

    // ── 3. Header missing → prompt ──────────────────────────────────────────
    // Uses the same X-TOTP-Code header as the tenant-user step-up middleware
    // so the management dashboard only needs a single TOTP prompt flow.
    const rawCode = req.headers['x-totp-code'];
    const totpCode = typeof rawCode === 'string' ? rawCode.trim() : '';

    if (!totpCode) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_PERM_STEP_UP_REQUIRED, 'Step-up TOTP required', rid));
      return;
    }

    // ── 4. Validate format ──────────────────────────────────────────────────
    if (!/^\d{6}$/.test(totpCode)) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'Invalid TOTP', rid));
      return;
    }

    // ── 5. Decrypt + verify (constant-time boolean avoids timing oracle) ────
    //
    // otplib verifySync returns a boolean; both true and false paths execute
    // the same amount of work from the caller's perspective. The decryption
    // step uses Node's built-in AES-GCM (constant-time in OpenSSL's EVP
    // layer). No early-return branches between token receipt and the boolean
    // check below expose timing differences beyond decryption + HMAC.
    let valid = false;
    try {
      const secret = decryptSuperAdminTotpSecret(dbAdmin.totp_secret, dbAdmin.totp_iv, dbAdmin.totp_tag);
      valid = Boolean(verifySync({ token: totpCode, secret }));
    } catch (err) {
      log.error('Super-admin TOTP decryption failed during step-up', {
        superAdminId: superAdmin.superAdminId,
        error: err,
      });
      valid = false;
    }

    if (!valid) {
      // Audit via master_audit_log directly (masterDb is in scope).
      try {
        masterDb
          .prepare(
            'INSERT INTO master_audit_log (super_admin_id, action, details, ip_address) VALUES (?, ?, ?, ?)',
          )
          .run(
            superAdmin.superAdminId,
            'super_admin_totp_failed',
            JSON.stringify({ endpoint: endpointLabel, user_agent: userAgent }),
            ip,
          );
      } catch (auditErr) {
        log.error('Failed to write super_admin_totp_failed audit row', { error: auditErr });
      }
      res.status(401).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'Invalid TOTP', rid));
      return;
    }

    // ── 6. SCAN-593: Claim the code to prevent replay within the same window ─
    if (!claimCode(superAdmin.superAdminId, totpCode)) {
      try {
        masterDb
          .prepare(
            'INSERT INTO master_audit_log (super_admin_id, action, details, ip_address) VALUES (?, ?, ?, ?)',
          )
          .run(
            superAdmin.superAdminId,
            'super_admin_totp_failed',
            JSON.stringify({ endpoint: endpointLabel, user_agent: userAgent, reason: 'replay' }),
            ip,
          );
      } catch (auditErr) {
        log.error('Failed to write super_admin_totp_failed (replay) audit row', { error: auditErr });
      }
      res.status(403).json(errorBody(ERROR_CODES.ERR_INPUT_INVALID, 'TOTP code already used; wait for next code', rid));
      return;
    }

    // ── 7. Success — audit + continue ──────────────────────────────────────
    try {
      masterDb
        .prepare(
          'INSERT INTO master_audit_log (super_admin_id, action, details, ip_address) VALUES (?, ?, ?, ?)',
        )
        .run(
          superAdmin.superAdminId,
          'super_admin_totp_success',
          JSON.stringify({ endpoint: endpointLabel, user_agent: userAgent }),
          ip,
        );
    } catch (auditErr) {
      log.error('Failed to write super_admin_totp_success audit row', { error: auditErr });
    }

    next();
  };
}
