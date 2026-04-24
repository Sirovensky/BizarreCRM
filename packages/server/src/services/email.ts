import crypto from 'crypto';
import nodemailer from 'nodemailer';
import { getConfigValue } from '../utils/configEncryption.js';
import { createBreaker } from '../utils/circuitBreaker.js';
import { config } from '../config.js';
import { createLogger } from '../utils/logger.js';

const emailLogger = createLogger('email');

// SEC-H77: Circuit breaker for SMTP — open after 5 consecutive failures.
const smtpBreaker = createBreaker('smtp');

// Cached transporter per-tenant (keyed by config hash) with TTL
const TRANSPORTER_TTL_MS = 5 * 60 * 1000; // 5 minutes

interface CachedTransporter {
  transporter: nodemailer.Transporter;
  createdAt: number;
}

const transporterCache = new Map<string, CachedTransporter>();

interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
}

// PROD105: Email address validation regex (same pattern as EMAIL_RE in settings.routes.ts).
// Guards against header-injection: the regex prohibits whitespace, \r, \n, and other
// characters that could fold extra SMTP headers into the From field.
const EMAIL_FROM_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Read SMTP credentials from per-tenant store_config DB (auto-decrypts sensitive keys).
 *
 * PROD105: from resolution priority (highest to lowest):
 *   1. store_config.from_email  — per-tenant sender identity (e.g. support@tenant.com)
 *   2. store_config.smtp_from   — SMTP envelope from (may be a relay address)
 *   3. store_config.smtp_user   — SMTP auth username (last resort)
 *
 * from_email is validated against EMAIL_FROM_RE before use to prevent SMTP header
 * injection via a user-controlled store_config value.
 */
function getSmtpConfig(db: any): SmtpConfig | null {
  try {
    const get = (key: string) => getConfigValue(db, key) || '';
    const host = get('smtp_host');
    const user = get('smtp_user');
    if (!host || !user) return null;

    // PROD105: resolve the effective From address.
    const fromEmailRaw = get('from_email').trim();
    const smtpFrom = get('smtp_from').trim();

    let from: string;
    let fromSource: 'from_email' | 'smtp_from' | 'smtp_user';

    if (fromEmailRaw && EMAIL_FROM_RE.test(fromEmailRaw)) {
      from = fromEmailRaw;
      fromSource = 'from_email';
    } else if (smtpFrom) {
      from = smtpFrom;
      fromSource = 'smtp_from';
    } else {
      from = user;
      fromSource = 'smtp_user';
    }

    if (fromEmailRaw && !EMAIL_FROM_RE.test(fromEmailRaw)) {
      // Stored value doesn't pass the format check — log so operator can correct.
      emailLogger.warn('[PROD105] from_email invalid format — falling back', {
        stored: fromEmailRaw.slice(0, 20) + (fromEmailRaw.length > 20 ? '…' : ''),
        fallbackTo: fromSource,
      });
    } else {
      emailLogger.info('[PROD105] outbound email from resolved', { fromSource });
    }

    return {
      host,
      port: parseInt(get('smtp_port') || '587', 10),
      user,
      pass: get('smtp_pass'),
      from,
    };
  } catch {
    return null;
  }
}

function getTransporter(db: any): { transporter: nodemailer.Transporter; from: string } | null {
  const cfg = getSmtpConfig(db);
  if (!cfg) return null;

  // Include host, port, user, and pass in the cache key to prevent collisions across
  // tenants that might share the same SMTP host but have different credentials.
  const cacheKey = crypto.createHash('sha256')
    .update(`${cfg.host}:${cfg.port}:${cfg.user}:${cfg.pass}`)
    .digest('hex');
  const cached = transporterCache.get(cacheKey);
  const now = Date.now();

  if (cached && (now - cached.createdAt) < TRANSPORTER_TTL_MS) {
    return { transporter: cached.transporter, from: cfg.from };
  }

  // Expired or missing — create fresh transporter
  if (cached) {
    transporterCache.delete(cacheKey);
  }

  const t = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.port === 465,
    auth: { user: cfg.user, pass: cfg.pass },
    // SEC-H74: cap SMTP handshake and data phases at 15s each so a slow or
    // unresponsive mail server can't tie up an Express request handler for
    // nodemailer's default 10-minute timeout.
    connectionTimeout: 15_000,
    socketTimeout: 15_000,
    greetingTimeout: 15_000,
  });
  transporterCache.set(cacheKey, { transporter: t, createdAt: now });
  return { transporter: t, from: cfg.from };
}

function sanitizeSubject(s: string): string {
  return s.replace(/[\r\n]+/g, ' ').slice(0, 998);
}

// SCAN-1051b: best-effort HTML sanitizer for outbound email bodies. We strip
// `<script>` and inline event handlers (e.g. `onerror=`, `onclick=`) before
// handing the blob to nodemailer. Not a full HTML parser — adversarial HTML
// needs a library like DOMPurify or sanitize-html — but it closes the easy
// XSS path from admin-authored automation templates while keeping the
// normal styling/images untouched. Also caps total body length to stop a
// runaway template from pushing megabytes through SMTP.
const EMAIL_HTML_MAX_BYTES = 200_000;
function sanitizeEmailHtml(raw: string): string {
  if (!raw) return '';
  let out = raw;
  // Drop <script>...</script> blocks entirely.
  out = out.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
  // Drop standalone inline `on*=` event handlers (e.g. onclick="...", onerror='...').
  // Two passes cover both " and ' quoting.
  out = out.replace(/\s+on[a-z]+\s*=\s*"[^"]*"/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*'[^']*'/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*[^\s>]+/gi, '');
  // Drop `javascript:` URLs from href/src (best-effort).
  out = out.replace(/(href|src)\s*=\s*"\s*javascript:[^"]*"/gi, '$1="#"');
  out = out.replace(/(href|src)\s*=\s*'\s*javascript:[^']*'/gi, "$1='#'");
  if (Buffer.byteLength(out, 'utf8') > EMAIL_HTML_MAX_BYTES) {
    out = out.slice(0, EMAIL_HTML_MAX_BYTES);
    emailLogger.warn('email body truncated to 200KB cap');
  }
  return out;
}

export interface SendEmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

export async function sendEmail(db: any, opts: SendEmailOptions): Promise<boolean> {
  // PROD104: Emergency kill-switch. When DISABLE_OUTBOUND_EMAIL=true, suppress
  // all outbound email immediately without a code deployment. Log domain-only
  // (never the full address or body) so the audit trail stays clean.
  if (config.disableOutboundEmail) {
    const domain = opts.to.includes('@') ? opts.to.split('@')[1] : 'unknown';
    emailLogger.warn('[kill-switch] outbound email suppressed', { toDomain: domain });
    return false;
  }

  const result = getTransporter(db);
  if (!result) {
    emailLogger.warn('SMTP not configured — skipping email');
    return false;
  }

  const safeSubject = sanitizeSubject(opts.subject || '');
  const safeHtml = sanitizeEmailHtml(opts.html || '');
  // Regex is best-effort for non-adversarial HTML; proper parser library preferable if ever processing untrusted HTML.
  const plainText = opts.text || safeHtml
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();

  try {
    await smtpBreaker.run(() =>
      result.transporter.sendMail({
        from: result.from,
        to: opts.to,
        subject: safeSubject,
        html: safeHtml,
        text: plainText,
      }),
    );
    // Log only the domain of the recipient, not the full address, for privacy.
    const toDomain = opts.to.includes('@') ? opts.to.split('@')[1] : 'unknown';
    emailLogger.info('email sent', { toDomain, subject: opts.subject });
    return true;
  } catch (err) {
    emailLogger.error('email send failed', { error: err instanceof Error ? err.message : String(err) });
    return false;
  }
}

export function isEmailConfigured(db: any): boolean {
  return getSmtpConfig(db) !== null;
}

/** Clear cached transporter (call after SMTP settings change) */
export function clearEmailCache(): void {
  transporterCache.clear();
}
