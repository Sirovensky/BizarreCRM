import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import path from 'path';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { config } from '../config.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validateSlug, isSlugAvailable, provisionTenant } from '../services/tenant-provisioning.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { validateEmail, validateRequiredString } from '../utils/validate.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { sendEmail } from '../services/email.js';
import { logSecurityAlert } from '../utils/masterAudit.js';
import { createAsyncDb } from '../db/async-db.js';
import { JWT_SIGN_OPTIONS } from '../middleware/auth.js';

const router = Router();
const logger = createLogger('signup');

// ─── Rate limit windows ────────────────────────────────────────────
// R5: tightened from 5/hr to 3/hr per IP to harden against tenant sprawl.
const SIGNUP_MAX_PER_HOUR = 3;
const SIGNUP_WINDOW_MS = 60 * 60 * 1000;

// SEC-M15: per-admin-email ceiling. An attacker who rotates source IPs can
// currently retry the same email indefinitely; this cap stops them from
// spraying a single victim address with bogus shop creations (each attempt
// provisions and then orphans a tenant under the current TEMP-NO-EMAIL-VERIF
// flow). In-memory is fine for the same reason pendingSignups is — single
// process, short window, abandoned attempts should be cheap to retry later.
const SIGNUP_EMAIL_MAX_PER_HOUR = 3;
const SIGNUP_EMAIL_WINDOW_MS = 60 * 60 * 1000;
interface EmailRateEntry {
  count: number;
  firstAt: number;
}
const signupEmailCounters = new Map<string, EmailRateEntry>();

// Sweep expired counter entries every 5 min so the map cannot grow
// unbounded in long-lived processes.
setInterval(() => {
  const now = Date.now();
  for (const [email, entry] of signupEmailCounters) {
    if (now - entry.firstAt > SIGNUP_EMAIL_WINDOW_MS) {
      signupEmailCounters.delete(email);
    }
  }
}, 5 * 60 * 1000);

/**
 * Returns true if this email is still under the hourly ceiling and bumps the
 * counter. Returns false when the caller has exceeded the cap for the window.
 * Keys are normalized to lowercase before lookup so case variants share a slot.
 */
function consumeEmailSignupQuota(rawEmail: string): boolean {
  const email = rawEmail.trim().toLowerCase();
  if (!email) return true; // validation below will reject empties
  const now = Date.now();
  const entry = signupEmailCounters.get(email);
  if (!entry || now - entry.firstAt > SIGNUP_EMAIL_WINDOW_MS) {
    signupEmailCounters.set(email, { count: 1, firstAt: now });
    return true;
  }
  if (entry.count >= SIGNUP_EMAIL_MAX_PER_HOUR) {
    return false;
  }
  entry.count += 1;
  return true;
}

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

// ─── SEC-L41: slug-check captcha after N free calls per IP ──────────────
// Pair the rate limiter with a per-IP counter. After SLUG_CHECK_FREE_CALLS
// consecutive slug checks (within SLUG_CHECK_COUNTER_WINDOW_MS), the caller
// must submit a hCaptcha token. Prevents a single IP from riding the 1-per-
// 10s rate limit to grind through the slug space over time (360/hour is
// still enumeration territory given how short real slugs tend to be).
const SLUG_CHECK_FREE_CALLS = 3;
const SLUG_CHECK_COUNTER_WINDOW_MS = 60 * 60 * 1000; // 1h sliding window
interface SlugCheckCounter {
  count: number;
  firstAt: number;
}
const slugCheckCounters = new Map<string, SlugCheckCounter>();

// Sweep expired counter entries so the map doesn't grow without bound. Runs
// every 5 min on the same cadence as the pending-signup sweeper above.
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of slugCheckCounters) {
    if (now - entry.firstAt > SLUG_CHECK_COUNTER_WINDOW_MS) {
      slugCheckCounters.delete(ip);
    }
  }
}, 5 * 60 * 1000);

function bumpSlugCheckCount(ip: string): number {
  const now = Date.now();
  const entry = slugCheckCounters.get(ip);
  if (!entry || now - entry.firstAt > SLUG_CHECK_COUNTER_WINDOW_MS) {
    slugCheckCounters.set(ip, { count: 1, firstAt: now });
    return 1;
  }
  entry.count += 1;
  return entry.count;
}

function peekSlugCheckCount(ip: string): number {
  const now = Date.now();
  const entry = slugCheckCounters.get(ip);
  if (!entry || now - entry.firstAt > SLUG_CHECK_COUNTER_WINDOW_MS) {
    return 0;
  }
  return entry.count;
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

  // 3. HCAPTCHA_SECRET is missing at runtime.
  // SEC-H94: The boot-time fatal in config.ts is the primary guard. This is
  // defense-in-depth — it ensures no signup succeeds even if the config check
  // is somehow bypassed at runtime (e.g. unit-test mocks, config patching).
  if (!config.hCaptchaEnabled) {
    if (config.nodeEnv === 'production') {
      // Operator explicitly disabled captcha requirement — signup is allowed
      // without hCaptcha and the operator is responsible for upstream bot
      // protection (Cloudflare Turnstile, WAF, etc.). Log loudly so the
      // decision is visible in audit trails and security dashboards.
      if (!config.signupCaptchaRequired) {
        logger.warn('Signup accepted without captcha: SIGNUP_CAPTCHA_REQUIRED=false', { ip });
        logSecurityAlert('captcha_disabled_signup', 'warning', {
          message: 'Signup accepted without captcha. Operator disabled HCAPTCHA requirement — upstream bot protection (Cloudflare/WAF) must be in place.',
          ip
        });
        return { ok: true };
      }
      logger.error('Signup blocked: HCAPTCHA_SECRET not set in production', { ip });
      logSecurityAlert('captcha_not_configured', 'critical', {
        message: 'A signup was BLOCKED because HCAPTCHA_SECRET is not set in production. Server should have refused to boot — investigate immediately.',
        ip
      });
      return { ok: false, reason: 'Signup temporarily unavailable' };
    }
    // Dev/test: bypass active. Log a warning so it's visible in server output.
    logger.warn('[DEV] Captcha bypass active — HCAPTCHA_SECRET not set', { ip });
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

// ─── Post-provision token issuance ────────────────────────────────
// Issues access + refresh JWT tokens for the newly-created admin user,
// recording a session row in the tenant DB. Mirrors the issueTokens()
// helper in auth.routes.ts verbatim so both flows share the same cookie
// shape, JWT claims, and session-table contract.
//
// SECURITY:
//   - In prod this is called ONLY from GET /verify/:token AFTER the
//     single-use pending token has been consumed — the email-verification
//     gate is enforced by the caller, not by this function.
//   - In dev (nodeEnv !== 'production') it is called from the POST handler
//     immediately after provisionTenant() returns, since there is no email
//     step in dev mode.
//   - Token payload contains only id, role, sessionId, tenantSlug, jti.
//     No PII (email, name, password_hash) is embedded in the JWT.

interface SignupTokenResult {
  accessToken: string;
  user: {
    id: number;
    username: string;
    email: string;
    first_name: string;
    last_name: string;
    role: string;
    avatar_url: string | null;
  };
}

async function issueSignupTokens(
  tenantSlug: string,
  req: Request,
  res: Response,
): Promise<SignupTokenResult | null> {
  // Derive the tenant DB path the same way tenant-pool.ts does.
  const dbPath = path.join(config.tenantDataDir, `${tenantSlug}.db`);
  const tenantAdb = createAsyncDb(dbPath);

  // Fetch the admin user that provisionTenant() just created.
  const user = await tenantAdb.get<{
    id: number;
    username: string;
    email: string;
    first_name: string;
    last_name: string;
    role: string;
    avatar_url: string | null;
  }>(
    "SELECT id, username, email, first_name, last_name, role, avatar_url FROM users WHERE role = 'admin' LIMIT 1",
  );

  if (!user) {
    logger.error('issueSignupTokens: admin user not found after provisioning', { tenantSlug });
    return null;
  }

  const sessionId = uuidv4();
  const refreshDays = 30;
  const expiresAt = new Date(Date.now() + refreshDays * 24 * 60 * 60 * 1000).toISOString();

  // Insert session into the TENANT's sessions table (same schema as single-tenant).
  // SEC (A7): no prune-before-insert needed here — brand-new DB has no sessions.
  await tenantAdb.run(
    "INSERT INTO sessions (id, user_id, device_info, expires_at, last_active) VALUES (?, ?, ?, ?, datetime('now'))",
    sessionId,
    user.id,
    req.headers['user-agent'] || 'unknown',
    expiresAt,
  );

  // SEC (A6/A10): Explicit HS256 + iss + aud, matching auth.routes.ts exactly.
  // SEC-L34: jti uniquely identifies the token for future per-token revocation.
  // SEC-H103: sign with dedicated per-purpose secret.
  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role, tenantSlug, jti: crypto.randomUUID() },
    config.accessJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '1h' },
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh', tenantSlug, jti: crypto.randomUUID() },
    config.refreshJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: `${refreshDays}d` },
  );

  // SEC-H17: httpOnly + SameSite=Strict — mirrors auth.routes.ts exactly.
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: config.nodeEnv === 'production',
    sameSite: 'strict',
    maxAge: refreshDays * 24 * 60 * 60 * 1000,
    path: '/',
  });

  // SEC-H89: CSRF double-submit cookie — non-httpOnly so the SPA JS can read it
  // and forward it as X-CSRF-Token header on POST /auth/refresh.
  const csrfToken = crypto.randomBytes(24).toString('base64url');
  res.cookie('csrf_token', csrfToken, {
    httpOnly: false,
    secure: config.nodeEnv === 'production',
    sameSite: 'strict',
    maxAge: refreshDays * 24 * 60 * 60 * 1000,
    path: '/',
  });

  const safeUser = {
    id: user.id,
    username: user.username,
    email: user.email,
    first_name: user.first_name ?? '',
    last_name: user.last_name ?? '',
    role: user.role,
    avatar_url: user.avatar_url ?? null,
  };

  return { accessToken, user: safeUser };
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
    // SEC-H94: 'Signup temporarily unavailable' is the specific reason emitted
    // when HCAPTCHA_SECRET is missing in production (defense-in-depth path).
    // Return 503 so monitoring/alerting can distinguish it from a bad-token 400.
    const status = captcha.reason === 'Signup temporarily unavailable' ? 503 : 400;
    res.status(status).json({ success: false, message: captcha.reason || 'Captcha verification failed' });
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
  // SEC-L42: collapse every post-captcha validation failure into one generic
  // error message so a probe can't tell whether the email was malformed,
  // the shop name was invalid-format, or the slug was already taken. Prior
  // code emitted three distinct strings ("Invalid admin_email", "Invalid
  // shop name", "This shop name is not available") which let an attacker
  // enumerate valid-but-taken slugs (AZ-042). We still DO the validation —
  // just report the same message. Internal logger captures the specific
  // reason for operator debugging without exposing it to the wire.
  const GENERIC_SIGNUP_FAILURE = 'Signup failed. Please check your details and try again.';

  let normalizedEmail: string;
  try {
    normalizedEmail = validateEmail(admin_email, 'admin_email', true) as string;
    validateRequiredString(shop_name, 'shop_name', 100);
  } catch (err) {
    const reason = err instanceof Error ? err.message : 'Invalid input';
    logger.warn('signup rejected: input validation', { reason });
    res.status(400).json({ success: false, message: GENERIC_SIGNUP_FAILURE });
    return;
  }

  // SEC-M15: per-email ceiling — checked AFTER the email is validated so
  // invalid/garbage addresses cannot burn legitimate quota slots. Rotating
  // IPs bypasses signupLimiter; this catches the case where one email is
  // being spammed with tenant creation attempts.
  if (!consumeEmailSignupQuota(normalizedEmail)) {
    res.status(429).json({
      success: false,
      message: 'Too many signup attempts for this email. Please try again later.',
    });
    return;
  }

  // Validate slug format up-front so we do not email the admin a link that
  // will fail at click-time. Slug-format rejection + slug-taken rejection
  // now share the SAME generic message — see GENERIC_SIGNUP_FAILURE above.
  const normalizedSlug = String(slug).toLowerCase().trim();
  const slugCheck = validateSlug(normalizedSlug);
  if (!slugCheck.valid) {
    logger.warn('signup rejected: slug format', { reason: slugCheck.error });
    res.status(400).json({ success: false, message: GENERIC_SIGNUP_FAILURE });
    return;
  }
  if (!isSlugAvailable(normalizedSlug)) {
    logger.warn('signup rejected: slug taken', { slug: normalizedSlug });
    res.status(400).json({ success: false, message: GENERIC_SIGNUP_FAILURE });
    return;
  }

  // SEC-H94 / BH-0002: Email-verification gate — provisioning only happens
  // AFTER the admin clicks the link sent to their address. This prevents
  // unauthenticated callers from creating CF DNS records and tenant directories
  // by simply POSTing to /signup (even if captcha passes, the subdomain does
  // not exist until the email owner confirms).
  //
  // Dev bypass: in non-production environments we skip the email step entirely
  // and provision immediately so local testing does not require working SMTP.
  if (config.nodeEnv !== 'production') {
    logger.warn('[DEV] Email-verification bypass active — provisioning tenant immediately', { slug: normalizedSlug, email: normalizedEmail });
    const result = await provisionTenant({
      slug: normalizedSlug,
      name: String(shop_name).trim(),
      adminEmail: normalizedEmail,
      adminPassword: admin_password,
      adminFirstName: admin_first_name?.toString()?.trim(),
      adminLastName: admin_last_name?.toString()?.trim(),
    });

    if (!result.success) {
      res.status(400).json({ success: false, message: result.error || 'Failed to create shop' });
      return;
    }

    audit(req.db, 'signup_dev_provisioned', null, ip, { slug: result.slug, email: normalizedEmail });

    // Dev mode: issue tokens immediately so the client is authenticated
    // without forcing a re-login after provisioning.
    const tokenResult = await issueSignupTokens(result.slug!, req, res);

    res.status(201).json({
      success: true,
      data: {
        tenant_id: result.tenantId,
        slug: result.slug,
        url: `https://${result.slug}.${config.baseDomain}`,
        message: 'Shop created successfully (dev mode — email verification bypassed).',
        ...(tokenResult && {
          accessToken: tokenResult.accessToken,
          user: tokenResult.user,
          tenant: { id: result.tenantId, slug: result.slug, name: String(shop_name).trim() },
        }),
      },
    });
    return;
  }

  // Production: stash pending signup and send verification email.
  // No DB writes, no CF DNS record, no tenant directory until link is clicked.
  const verifyToken = crypto.randomBytes(32).toString('hex');
  pendingSignups.set(verifyToken, {
    slug: normalizedSlug,
    shopName: String(shop_name).trim(),
    adminEmail: normalizedEmail,
    adminPassword: admin_password,
    adminFirstName: admin_first_name?.toString()?.trim(),
    adminLastName: admin_last_name?.toString()?.trim(),
    createdAt: Date.now(),
    ipAddress: ip,
  });

  const emailSent = await sendVerificationEmail(req.db, normalizedEmail, verifyToken, normalizedSlug, String(shop_name).trim());
  if (!emailSent) {
    // Remove the pending entry so this attempt doesn't occupy the email quota
    // slot without the user being able to complete it.
    pendingSignups.delete(verifyToken);
    logger.error('Failed to send verification email during signup', { email: normalizedEmail, slug: normalizedSlug });
    res.status(500).json({ success: false, message: 'Failed to send verification email. Please try again.' });
    return;
  }

  audit(req.db, 'signup_pending', null, ip, { slug: normalizedSlug, email: normalizedEmail });

  res.status(202).json({
    success: true,
    data: {
      message: 'Check your email to complete signup. Click the link in the message to create your shop.',
    },
  });
}));

// ─── GET /signup/verify/:token — Complete signup after email click ─
// Dual-mode response:
//   - Browser (email link click): redirect to the new tenant's login page
//     with the refreshToken cookie already set (SameSite=Lax is not needed
//     here — the redirect is a top-level navigation on the same domain, and
//     Strict cookies are sent on same-site top-level GET navigations).
//   - API call (iOS/Android, or ?format=json, or Accept: application/json):
//     return JSON { success, data: { accessToken, user, tenant } } so the
//     native client receives tokens inline without a redirect.
//
// SECURITY: Provisioning happens here — AFTER single-use token is consumed —
// so the email-verification gate is fully enforced in production.
router.get('/verify/:token', asyncHandler(async (req: Request, res: Response) => {
  if (!config.multiTenant) {
    res.status(404).json({ success: false, message: 'Not available' });
    return;
  }

  const token = String(req.params.token || '');
  const entry = pendingSignups.get(token);
  if (!entry) {
    // Detect whether the caller wants JSON so error responses are also
    // machine-readable for API clients.
    const wantsJson =
      req.query['format'] === 'json' ||
      (req.headers['accept'] || '').includes('application/json');
    if (wantsJson) {
      res.status(400).json({ success: false, message: 'Invalid or expired verification link. Please sign up again.' });
    } else {
      res.redirect(`https://${config.baseDomain}/signup?error=invalid_link`);
    }
    return;
  }

  // Single-use: delete the token the moment it is consumed so a replay of
  // the URL cannot create a second tenant.
  pendingSignups.delete(token);

  if (Date.now() - entry.createdAt > PENDING_SIGNUP_TTL_MS) {
    const wantsJson =
      req.query['format'] === 'json' ||
      (req.headers['accept'] || '').includes('application/json');
    if (wantsJson) {
      res.status(400).json({ success: false, message: 'This verification link has expired. Please sign up again.' });
    } else {
      res.redirect(`https://${config.baseDomain}/signup?error=link_expired`);
    }
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
    const wantsJson =
      req.query['format'] === 'json' ||
      (req.headers['accept'] || '').includes('application/json');
    if (wantsJson) {
      res.status(400).json({ success: false, message: result.error || 'Failed to create shop' });
    } else {
      res.redirect(`https://${config.baseDomain}/signup?error=provisioning_failed`);
    }
    return;
  }

  audit(req.db, 'signup_verified', null, req.ip || entry.ipAddress, { slug: result.slug, email: entry.adminEmail });

  // Issue JWT tokens now that the tenant exists and the email is verified.
  // This is the only place in the production path where tokens are issued for
  // a signup flow — the POST handler above never provisions in prod.
  const tokenResult = await issueSignupTokens(result.slug!, req, res);

  const tenantUrl = `https://${result.slug}.${config.baseDomain}`;

  // Determine response mode:
  //   ?format=json  — explicit API request (iOS/Android fetch)
  //   Accept: application/json — standard API content negotiation
  //   otherwise     — assume browser email-link click, redirect
  const wantsJson =
    req.query['format'] === 'json' ||
    (req.headers['accept'] || '').includes('application/json');

  if (wantsJson) {
    res.status(201).json({
      success: true,
      data: {
        tenant_id: result.tenantId,
        slug: result.slug,
        url: tenantUrl,
        message: 'Shop created successfully.',
        ...(tokenResult && {
          accessToken: tokenResult.accessToken,
          user: tokenResult.user,
          tenant: { id: result.tenantId, slug: result.slug, name: entry.shopName },
        }),
      },
    });
  } else {
    // Browser path: the refreshToken + csrf_token cookies were already set by
    // issueSignupTokens(). Redirect to the tenant's login page; the browser
    // will carry the cookies automatically.
    res.redirect(`${tenantUrl}/login?verified=1`);
  }
}));

// ─── GET /signup/check-slug/:slug ──────────────────────────────────
// PT6: Rate-limited and returns a generic shape. We no longer distinguish
// between "reserved", "invalid format", and "taken" — all unavailable
// results use the same message so the endpoint cannot enumerate.
//
// SEC-L41: After SLUG_CHECK_FREE_CALLS (3) slug checks per IP in a 1-hour
// window, the client must submit a hCaptcha token via `?captcha=<token>`.
// Up to the threshold the endpoint behaves exactly as before; past it, a
// missing or invalid token returns 403 with `captcha_required=true` so
// the frontend can prompt the user. `verifyCaptchaToken` is the same
// helper used by POST /signup, so dev-mode bypass and fail-open when
// HCAPTCHA_SECRET is unset behave consistently across both flows.
router.get('/check-slug/:slug', slugCheckLimiter, asyncHandler(async (req: Request, res: Response): Promise<void> => {
  if (!config.multiTenant) {
    res.status(404).json({ success: false, message: 'Not available' });
    return;
  }

  const ip = req.ip || 'unknown';
  const currentCount = peekSlugCheckCount(ip);
  if (currentCount >= SLUG_CHECK_FREE_CALLS) {
    const captchaToken = req.query.captcha;
    const captchaResult = await verifyCaptchaToken(captchaToken, ip);
    if (!captchaResult.ok) {
      res.status(403).json({
        success: false,
        message: 'Captcha required',
        data: { captcha_required: true, reason: captchaResult.reason ?? 'missing_captcha' },
      });
      return;
    }
  }
  // Only increment after the captcha gate so a caller stuck at the gate
  // doesn't keep ratcheting the counter up forever.
  bumpSlugCheckCount(ip);

  const slug = (req.params.slug as string).toLowerCase().trim();
  const validation = validateSlug(slug);

  if (!validation.valid) {
    res.json({ success: true, data: { available: false, reason: 'This shop name is not available' } });
    return;
  }

  const available = isSlugAvailable(slug);
  res.json({
    success: true,
    data: {
      available,
      reason: available ? null : 'This shop name is not available',
    },
  });
}));

export default router;
