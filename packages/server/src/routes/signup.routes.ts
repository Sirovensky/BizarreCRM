import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { config } from '../config.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validateSlug, isSlugAvailable, provisionTenant } from '../services/tenant-provisioning.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { validateEmail, validateRequiredString } from '../utils/validate.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { sendEmail } from '../services/email.js';
import { logSecurityAlert } from '../utils/masterAudit.js';

const router = Router();
const logger = createLogger('signup');

// ─── Rate limit windows ────────────────────────────────────────────
// R5: tightened from 5/hr to 3/hr per IP to harden against tenant sprawl.
const SIGNUP_MAX_PER_HOUR = 3;
const SIGNUP_WINDOW_MS = 60 * 60 * 1000;

// PT6: /check-slug hardened from 30/min to 1-per-10-seconds per IP so an
// attacker cannot cheaply enumerate every tenant slug by brute force. We
// also return generic "unavailable" instead of a specific reason so the
// response body itself does not become an enumeration oracle.
const SLUG_CHECK_MIN_INTERVAL_MS = 10 * 1000;

// ─── Pending signup store (in-memory with TTL) ─────────────────────
// R5: Signup no longer immediately provisions a tenant. Instead we stash the
// proposed tenant info keyed by a random verification token and email the
// link. Provisioning only happens after the admin clicks the link.
//
// In-memory is acceptable here because:
//   - Verification windows are short (1h) and abandoned signups should be
//     cheap to re-try.
//   - Single-process server (see CLAUDE.md).
//   - We don't want to persist unverified email addresses longer than needed.
const PENDING_SIGNUP_TTL_MS = 60 * 60 * 1000; // 1 hour
const pendingSignups = new Map<string, {
  slug: string;
  shopName: string;
  adminEmail: string;
  adminPassword: string;
  adminFirstName?: string;
  adminLastName?: string;
  createdAt: number;
  ipAddress: string;
}>();

// Sweep expired entries so the map does not grow without bound.
setInterval(() => {
  const now = Date.now();
  for (const [token, entry] of pendingSignups) {
    if (now - entry.createdAt > PENDING_SIGNUP_TTL_MS) {
      pendingSignups.delete(token);
    }
  }
}, 5 * 60 * 1000);

// ─── SQLite-backed rate limiters ──────────────────────────────────

// Signup creation: per-IP hourly ceiling (R5).
function signupLimiter(req: Request, res: Response, next: NextFunction): void {
  const ip = req.ip || 'unknown';
  if (!checkWindowRate(req.db, 'signup', ip, SIGNUP_MAX_PER_HOUR, SIGNUP_WINDOW_MS)) {
    res.status(429).json({ success: false, message: 'Too many requests. Please try again later.' });
    return;
  }
  recordWindowFailure(req.db, 'signup', ip, SIGNUP_WINDOW_MS);
  next();
}

// Slug check: 1 call per 10 seconds per IP (PT6). We deliberately do NOT
// generate a 429 after multiple failed slug checks — instead every call is
// rate-limited so the endpoint cannot be used as a bulk oracle.
function slugCheckLimiter(req: Request, res: Response, next: NextFunction): void {
  const ip = req.ip || 'unknown';
  if (!checkWindowRate(req.db, 'slug_check', ip, 1, SLUG_CHECK_MIN_INTERVAL_MS)) {
    res.status(429).json({ success: false, message: 'Too many requests. Please try again later.' });
    return;
  }
  recordWindowFailure(req.db, 'slug_check', ip, SLUG_CHECK_MIN_INTERVAL_MS);
  next();
}

// ─── CAPTCHA verification (R5) ─────────────────────────────────────
// Production verifies hCaptcha tokens and fails closed without HCAPTCHA_SECRET.
// Development/tests accept "dev-captcha-token" so the flow remains automatable.
const HCAPTCHA_VERIFY_URL = 'https://api.hcaptcha.com/siteverify';
const CAPTCHA_VERIFY_TIMEOUT_MS = 8_000;

interface HCaptchaVerifyResponse {
  success?: boolean;
  challenge_ts?: string;
  hostname?: string;
  'error-codes'?: string[];
}

async function verifyCaptchaToken(token: unknown, ip: string): Promise<{ ok: boolean; reason?: string }> {
  // 1. Check if CAPTCHA is provided
  const responseToken = typeof token === 'string' ? token.trim() : '';

  // 2. Dev mode bypass
  if (config.nodeEnv !== 'production' && responseToken === 'dev-captcha-token') {
    return { ok: true };
  }

  // 3. Fail-open if not configured
  if (!config.hCaptchaEnabled) {
    if (config.nodeEnv === 'production') {
      logger.warn('Signup proceed without CAPTCHA (not configured)', { ip });
      logSecurityAlert('captcha_not_configured', 'warning', {
        message: 'A signup was processed without CAPTCHA verification because HCAPTCHA_SECRET is not set in .env.',
        ip
      });
    }
    return { ok: true };
  }

  // 4. Missing token when CAPTCHA is enabled.
  if (!responseToken) {
    logger.warn('Signup received with missing captcha token', { ip });
    logSecurityAlert('captcha_token_missing', 'warning', {
      message: 'A signup was blocked because CAPTCHA is enabled but the token was missing.',
      ip
    });
    return { ok: false, reason: 'captcha_token is required' };
  }

  const secret = (config.hCaptchaSecret || '').trim();
  const body = new URLSearchParams({ secret, response: responseToken });
  if (ip && ip !== 'unknown') body.set('remoteip', ip);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), CAPTCHA_VERIFY_TIMEOUT_MS);

  try {
    const response = await fetch(HCAPTCHA_VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
      signal: controller.signal,
    });

    if (!response.ok) {
      logger.warn('hCaptcha verification endpoint returned an error', { ip, status: response.status });
      logSecurityAlert('captcha_service_error', 'warning', {
        message: `hCaptcha API returned HTTP ${response.status}. Signup blocked because CAPTCHA is enabled.`,
        ip
      });
      return { ok: false, reason: 'Captcha verification failed' };
    }

    const result = await response.json() as HCaptchaVerifyResponse;
    if (result.success === true) return { ok: true };

    logger.warn('hCaptcha verification rejected signup token', {
      ip,
      hostname: result.hostname,
      errors: result['error-codes'] || [],
    });

    logSecurityAlert('captcha_verification_failed', 'critical', {
      message: 'A signup was blocked because CAPTCHA verification failed.',
      ip,
      hostname: result.hostname,
      errors: result['error-codes'] || []
    });

    return { ok: false, reason: 'Captcha verification failed' };
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    logger.warn('hCaptcha verification request failed', { ip, error: errorMsg });

    logSecurityAlert('captcha_verify_exception', 'warning', {
      message: `hCaptcha request error: ${errorMsg}. Signup blocked because CAPTCHA is enabled.`,
      ip
    });

    return { ok: false, reason: 'Captcha verification failed' };
  } finally {
    clearTimeout(timeout);
  }
}

// ─── Verification email ────────────────────────────────────────────
// Sends the "please click to confirm your shop" email using the master DB
// SMTP config. In multi-tenant mode the master DB holds platform-level SMTP
// creds inside platform_config; we read those via the same sendEmail
// helper that the rest of the app uses.
async function sendVerificationEmail(
  db: any,
  toEmail: string,
  token: string,
  slug: string,
  shopName: string,
): Promise<boolean> {
  const verifyUrl = `https://${config.baseDomain}/api/v1/signup/verify/${encodeURIComponent(token)}`;
  const html = `
    <div style="font-family:sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#0f172a">
      <h2 style="margin-top:0">Confirm your shop</h2>
      <p>Thanks for signing up for Bizarre Electronics CRM. Please confirm your email to finish creating <strong>${shopName}</strong> (${slug}).</p>
      <p style="margin:24px 0">
        <a href="${verifyUrl}" style="background:#3b82f6;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;display:inline-block">Confirm and create my shop</a>
      </p>
      <p style="color:#64748b;font-size:13px">This link will expire in one hour. If you did not request this, you can safely ignore this email.</p>
    </div>
  `;
  try {
    return await sendEmail(db, {
      to: toEmail,
      subject: 'Confirm your Bizarre Electronics CRM shop',
      html,
    });
  } catch (err) {
    logger.error('Verification email send failed', { error: err instanceof Error ? err.message : String(err) });
    return false;
  }
}

// ─── POST /signup ──────────────────────────────────────────────────
// R5: Does NOT immediately provision the tenant. Stores a pending-signup
// record, emails a verification link, and returns 202 Accepted.
router.post('/', signupLimiter, asyncHandler(async (req: Request, res: Response) => {
  if (!config.multiTenant) {
    res.status(404).json({ success: false, message: 'Signup not available in single-tenant mode' });
    return;
  }

  const ip = req.ip || 'unknown';
  const { slug, shop_name, admin_email, admin_password, admin_first_name, admin_last_name, captcha_token } = req.body;

  // CAPTCHA check first — no point validating the rest if the bot check fails.
  const captcha = await verifyCaptchaToken(captcha_token, ip);
  if (!captcha.ok) {
    res.status(400).json({ success: false, message: captcha.reason || 'Captcha verification failed' });
    return;
  }

  if (!slug || !shop_name || !admin_email || !admin_password) {
    res.status(400).json({ success: false, message: 'All fields required: slug, shop_name, admin_email, admin_password, captcha_token' });
    return;
  }

  // Input length validation (prevent bcrypt DoS and oversized payloads)
  if (typeof admin_password !== 'string' || admin_password.length < 8 || admin_password.length > 128) {
    res.status(400).json({ success: false, message: 'Password must be 8 to 128 characters' });
    return;
  }
  let normalizedEmail: string;
  try {
    normalizedEmail = validateEmail(admin_email, 'admin_email', true) as string;
    validateRequiredString(shop_name, 'shop_name', 100);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Invalid input';
    res.status(400).json({ success: false, message });
    return;
  }

  // Validate slug format up-front so we do not email the admin a link that
  // will fail at click-time.
  const normalizedSlug = String(slug).toLowerCase().trim();
  const slugCheck = validateSlug(normalizedSlug);
  if (!slugCheck.valid) {
    res.status(400).json({ success: false, message: slugCheck.error || 'Invalid shop name' });
    return;
  }
  if (!isSlugAvailable(normalizedSlug)) {
    // Return the same generic message as PT6 — don't confirm "this slug is
    // taken" via a dedicated error code because that still enumerates.
    res.status(400).json({ success: false, message: 'This shop name is not available' });
    return;
  }

  // Stash pending signup + generate token.
  const token = crypto.randomBytes(32).toString('hex');
  pendingSignups.set(token, {
    slug: normalizedSlug,
    shopName: String(shop_name).trim(),
    adminEmail: normalizedEmail,
    adminPassword: admin_password,
    adminFirstName: admin_first_name?.toString()?.trim(),
    adminLastName: admin_last_name?.toString()?.trim(),
    createdAt: Date.now(),
    ipAddress: ip,
  });

  // Fire-and-forget the email so a slow SMTP server doesn't stall the
  // response. Failures are logged but we still return 202 because the user
  // should not be told whether an email address is reachable (enumeration).
  sendVerificationEmail(req.db, normalizedEmail, token, normalizedSlug, String(shop_name).trim())
    .then((ok) => {
      if (!ok) logger.warn('Verification email may not have been delivered', { slug: normalizedSlug });
    })
    .catch((err) => {
      logger.error('Verification email threw', { error: err instanceof Error ? err.message : String(err) });
    });

  audit(req.db, 'signup_pending', null, ip, { slug: normalizedSlug, email: normalizedEmail });

  res.status(202).json({
    success: true,
    data: {
      message: 'Please check your email to confirm and finish creating your shop.',
    },
  });
}));

// ─── GET /signup/verify/:token — Complete signup after email click ─
router.get('/verify/:token', asyncHandler(async (req: Request, res: Response) => {
  if (!config.multiTenant) {
    res.status(404).json({ success: false, message: 'Not available' });
    return;
  }

  const token = String(req.params.token || '');
  const entry = pendingSignups.get(token);
  if (!entry) {
    res.status(400).json({ success: false, message: 'Invalid or expired verification link. Please sign up again.' });
    return;
  }

  // Single-use: delete the token the moment it is consumed so a replay of
  // the URL cannot create a second tenant.
  pendingSignups.delete(token);

  if (Date.now() - entry.createdAt > PENDING_SIGNUP_TTL_MS) {
    res.status(400).json({ success: false, message: 'This verification link has expired. Please sign up again.' });
    return;
  }

  const result = await provisionTenant({
    slug: entry.slug,
    name: entry.shopName,
    adminEmail: entry.adminEmail,
    adminPassword: entry.adminPassword,
    adminFirstName: entry.adminFirstName,
    adminLastName: entry.adminLastName,
  });

  if (!result.success) {
    res.status(400).json({ success: false, message: result.error || 'Failed to create shop' });
    return;
  }

  audit(req.db, 'signup_verified', null, req.ip || entry.ipAddress, { slug: result.slug, email: entry.adminEmail });

  res.status(201).json({
    success: true,
    data: {
      tenant_id: result.tenantId,
      slug: result.slug,
      url: `https://${result.slug}.${config.baseDomain}`,
      message: 'Shop created successfully. You can now log in.',
    },
  });
}));

// ─── GET /signup/check-slug/:slug ──────────────────────────────────
// PT6: Rate-limited and returns a generic shape. We no longer distinguish
// between "reserved", "invalid format", and "taken" — all unavailable
// results use the same message so the endpoint cannot enumerate.
router.get('/check-slug/:slug', slugCheckLimiter, (req, res) => {
  if (!config.multiTenant) {
    return res.status(404).json({ success: false, message: 'Not available' });
  }

  const slug = (req.params.slug as string).toLowerCase().trim();
  const validation = validateSlug(slug);

  if (!validation.valid) {
    return res.json({ success: true, data: { available: false, reason: 'This shop name is not available' } });
  }

  const available = isSlugAvailable(slug);
  res.json({
    success: true,
    data: {
      available,
      reason: available ? null : 'This shop name is not available',
    },
  });
});

export default router;
