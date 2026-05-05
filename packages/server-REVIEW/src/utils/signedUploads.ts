import crypto from 'crypto';
import { config } from '../config.js';

/**
 * SEC-H54: HMAC-signed URL helpers for public-facing upload access.
 *
 * Scope: /uploads/<slug>/<file> is now auth-gated (Bearer token + tenant
 * check). Customer-facing contexts can't present a JWT — email receipt
 * images, MMS media links, portal approval attachments — so we issue a
 * short-lived signed URL instead.
 *
 * Scheme:
 *   canonical = `${type}|${slug}|${file}|${exp}`
 *   sig = HMAC-SHA256(uploadsSecret, canonical) as base64url
 *   url = `/signed-url/${type}/${slug}/${file}?exp=${exp}&sig=${sig}`
 *
 * Verifier recomputes canonical → HMAC → constant-time compares bytes.
 * Rejects expired or malformed requests with 403.
 *
 * `type` distinguishes the backend directory when ambiguous (e.g. 'mms'
 * vs 'uploads'); defaults to 'uploads' which resolves under
 * config.uploadsPath/<slug>/<file>.
 */

export type SignedUploadType = 'uploads' | 'mms' | 'recordings' | 'bench' | 'shrinkage' | 'inventory';

// Default 1h TTL. Caller can override (receipts may want shorter, MMS
// providers may need longer to fetch). Clamp to [60s, 7d] to prevent
// both trivially-short and pseudo-permanent signed URLs.
const TTL_MIN_SECONDS = 60;
const TTL_MAX_SECONDS = 7 * 24 * 60 * 60;

function canonicalString(type: SignedUploadType, slug: string, file: string, exp: number): string {
  return `${type}|${slug}|${file}|${exp}`;
}

function hmacSignature(canonical: string): string {
  return crypto
    .createHmac('sha256', config.uploadsSecret)
    .update(canonical)
    .digest('base64url');
}

/**
 * Build a signed URL path for a tenant-owned upload. The returned value
 * is ALWAYS a relative path starting with `/signed-url/...`; the caller
 * decides whether to prefix it with a host (emails / SMS need absolute
 * URLs, in-app links can stay relative).
 *
 * IMPORTANT: `file` is the RELATIVE path under the tenant's upload root.
 * For nested dirs like `mms/photo.jpg` pass the whole relative path;
 * the verifier normalises path traversal before serving.
 */
export function signUploadUrl(
  slug: string,
  file: string,
  ttlSeconds: number = 3600,
  type: SignedUploadType = 'uploads',
): string {
  if (!slug || !file) {
    throw new Error('signUploadUrl: slug and file are required');
  }
  const ttl = Math.max(TTL_MIN_SECONDS, Math.min(TTL_MAX_SECONDS, Math.floor(ttlSeconds)));
  const exp = Math.floor(Date.now() / 1000) + ttl;
  const canonical = canonicalString(type, slug, file, exp);
  const sig = hmacSignature(canonical);
  // encodeURIComponent the file portion — filenames can contain spaces /
  // unicode. Callers rebuilding the URL themselves must do the same.
  const encodedFile = encodeURIComponent(file);
  return `/signed-url/${encodeURIComponent(type)}/${encodeURIComponent(slug)}/${encodedFile}?exp=${exp}&sig=${sig}`;
}

export interface VerifyResult {
  ok: boolean;
  reason?: 'expired' | 'bad_signature' | 'malformed';
}

/**
 * Verify an inbound signed-URL request. Used by the express handler
 * at GET /signed-url/:type/:slug/:file. Rejects expired timestamps
 * and signature mismatches with distinct reasons so the handler can
 * emit the correct HTTP code.
 */
export function verifySignedUpload(
  type: string,
  slug: string,
  file: string,
  expRaw: unknown,
  sigRaw: unknown,
): VerifyResult {
  if (!type || !slug || !file || typeof expRaw !== 'string' || typeof sigRaw !== 'string') {
    return { ok: false, reason: 'malformed' };
  }
  const exp = parseInt(expRaw, 10);
  if (!Number.isFinite(exp) || exp <= 0) {
    return { ok: false, reason: 'malformed' };
  }
  if (exp < Math.floor(Date.now() / 1000)) {
    return { ok: false, reason: 'expired' };
  }
  const canonical = canonicalString(type as SignedUploadType, slug, file, exp);
  const expected = hmacSignature(canonical);
  // Constant-time compare to block timing oracles.
  const providedBuf = Buffer.from(sigRaw, 'utf8');
  const expectedBuf = Buffer.from(expected, 'utf8');
  if (providedBuf.length !== expectedBuf.length) {
    return { ok: false, reason: 'bad_signature' };
  }
  if (!crypto.timingSafeEqual(providedBuf, expectedBuf)) {
    return { ok: false, reason: 'bad_signature' };
  }
  return { ok: true };
}
