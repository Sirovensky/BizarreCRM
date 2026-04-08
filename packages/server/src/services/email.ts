import crypto from 'crypto';
import nodemailer from 'nodemailer';
import { getConfigValue } from '../utils/configEncryption.js';

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

/** Read SMTP credentials from per-tenant store_config DB (auto-decrypts sensitive keys) */
function getSmtpConfig(db: any): SmtpConfig | null {
  try {
    const get = (key: string) => getConfigValue(db, key) || '';
    const host = get('smtp_host');
    const user = get('smtp_user');
    if (!host || !user) return null;
    return {
      host,
      port: parseInt(get('smtp_port') || '587', 10),
      user,
      pass: get('smtp_pass'),
      from: get('smtp_from') || user,
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
  });
  transporterCache.set(cacheKey, { transporter: t, createdAt: now });
  return { transporter: t, from: cfg.from };
}

export interface SendEmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

export async function sendEmail(db: any, opts: SendEmailOptions): Promise<boolean> {
  const result = getTransporter(db);
  if (!result) {
    console.warn('[Email] SMTP not configured — skipping email');
    return false;
  }

  try {
    await result.transporter.sendMail({
      from: result.from,
      to: opts.to,
      subject: opts.subject,
      html: opts.html,
      text: opts.text || opts.html.replace(/<[^>]+>/g, ''),
    });
    console.log(`[Email] Sent to ${opts.to}: ${opts.subject}`);
    return true;
  } catch (err) {
    console.error(`[Email] Failed to send to ${opts.to}:`, err);
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
