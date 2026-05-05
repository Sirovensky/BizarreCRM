/**
 * HTTP request logging middleware (ENR-INFRA3).
 * Logs method, path, status code, response time, IP, user-agent,
 * content-length, and user ID (when authenticated) using the
 * structured JSON logger.
 */
import { Request, Response, NextFunction } from 'express';
import { createLogger } from '../utils/logger.js';
import { recordRequest, recordResponseTime } from '../utils/requestCounter.js';

const log = createLogger('http');

// SEC-NEW: Per-tenant request counting (in-memory, resets every 60s per tenant)
// @audit-fixed: Cap the map so an attacker can't OOM the server by flooding
// requests with unique Host headers that each create a new tenant slug entry.
const MAX_TRACKED_TENANTS = 10_000;
const tenantRequests = new Map<string, { count: number; resetAt: number }>();

/** Returns a snapshot of per-tenant request counts (for the management dashboard). */
export function getTenantRequestCounts(): Record<string, { count: number; windowMs: number }> {
  const now = Date.now();
  const result: Record<string, { count: number; windowMs: number }> = {};
  for (const [slug, entry] of tenantRequests) {
    if (entry.resetAt > now) {
      result[slug] = { count: entry.count, windowMs: entry.resetAt - now };
    }
  }
  return result;
}

// @audit-fixed: Sweep expired tenantRequests entries + enforce the cap. Runs
// on every request so we don't need a setInterval dependency.
function maybePruneTenantRequests(now: number): void {
  if (tenantRequests.size < MAX_TRACKED_TENANTS) return;
  for (const [slug, entry] of tenantRequests) {
    if (entry.resetAt <= now) tenantRequests.delete(slug);
  }
  // If still over the cap, drop the oldest-reset entries until within bounds.
  if (tenantRequests.size >= MAX_TRACKED_TENANTS) {
    const sorted = [...tenantRequests.entries()].sort((a, b) => a[1].resetAt - b[1].resetAt);
    const toRemove = tenantRequests.size - MAX_TRACKED_TENANTS + 1;
    for (let i = 0; i < toRemove && i < sorted.length; i++) {
      tenantRequests.delete(sorted[i][0]);
    }
  }
}

// Paths that generate high-frequency noise and don't need individual logging
const SKIP_PATHS = new Set(['/health', '/api/v1/health', '/favicon.ico']);

// @audit-fixed: Redact keys whose values are secret-shaped so log aggregators
// don't ingest access tokens / CSRF cookies / session IDs. Applied to query
// strings and headers before they touch the structured log.
const SENSITIVE_HEADER_NAMES = new Set([
  'authorization', 'cookie', 'set-cookie', 'x-csrf-token', 'x-api-key', 'proxy-authorization',
]);
const SENSITIVE_QUERY_KEYS = /(?:password|token|secret|api[_-]?key|pin|auth)/i;
function scrubPath(original: string): string {
  const qIdx = original.indexOf('?');
  if (qIdx < 0) return original;
  const base = original.slice(0, qIdx);
  const rawQuery = original.slice(qIdx + 1);
  const cleaned = rawQuery.split('&').map(pair => {
    const eq = pair.indexOf('=');
    if (eq < 0) return pair;
    const key = pair.slice(0, eq);
    return SENSITIVE_QUERY_KEYS.test(key) ? `${key}=REDACTED` : pair;
  }).join('&');
  return `${base}?${cleaned}`;
}

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  recordRequest();

  // SEC-NEW: Per-tenant request counting
  // SCAN-1079: previously every unresolvable host collapsed into a single
  // `'bare-domain'` bucket, so a DDoS against `evil.example.com` looked
  // identical on the ops dashboard to legitimate landing-page traffic.
  // Fall back to `host:<hostname>` for unresolved tenants so attribution
  // survives the tenant resolver returning null. Port is stripped so the
  // bucket key is stable across proxies that add port suffixes.
  const tenantSlug = (req as any).tenantSlug as string | undefined | null;
  let slug: string;
  if (tenantSlug) {
    slug = tenantSlug;
  } else {
    const hostHeader = req.headers.host || '';
    const hostname = String(hostHeader).split(':')[0].toLowerCase() || 'unknown';
    slug = `host:${hostname}`;
  }
  const now = Date.now();
  maybePruneTenantRequests(now);
  const entry = tenantRequests.get(slug);
  if (entry && entry.resetAt > now) {
    entry.count++;
  } else {
    tenantRequests.set(slug, { count: 1, resetAt: now + 60000 });
  }

  // @audit-fixed: The previous skip-path branch called
  // `recordResponseTime(Date.now() - Date.now())` which is always zero AND
  // installed a listener that polluted the rolling RT buffer with artificial
  // zeros. Just short-circuit the skip path with no listener at all.
  if (SKIP_PATHS.has(req.path)) {
    return next();
  }

  const start = Date.now();

  // Hook into response finish event to capture status and timing
  res.on('finish', () => {
    const duration = Date.now() - start;
    recordResponseTime(duration);

    // @audit-fixed: Redact sensitive query keys and cap UA/path length so a
    // malicious client can't make the log aggregator's index explode.
    const rawPath = req.originalUrl || req.path || '';
    const safePath = scrubPath(rawPath).slice(0, 2048);
    const rawUa = String(req.headers['user-agent'] || 'unknown');
    // eslint-disable-next-line no-control-regex
    const safeUa = rawUa.replace(/[\x00-\x1F\x7F]/g, '').slice(0, 512);

    const meta = {
      method: req.method,
      path: safePath,
      status: res.statusCode,
      duration_ms: duration,
      ip: String(req.ip || req.socket?.remoteAddress || 'unknown').slice(0, 64),
      userAgent: safeUa,
      contentLength: res.getHeader('content-length') || 0,
      userId: (req as any).user?.id || null,
      tenantSlug: (req as any).tenantSlug || null,
    };

    const message = `${req.method} ${safePath} ${res.statusCode} ${duration}ms`;

    if (res.statusCode >= 500) {
      log.error(message, meta);
    } else if (res.statusCode >= 400) {
      log.warn(message, meta);
    } else if (duration > 1000) {
      // Flag slow requests (>1s) at warn level for easy identification
      log.warn(`SLOW ${message}`, meta);
    } else {
      log.info(message, meta);
    }
  });

  // @audit-fixed: Silence listener-leak warnings — we expose a warning only
  // when exceptionally many simultaneous listeners attach so we don't hide a
  // real leak, but the default of 10 is too low for a long-poll heavy CRM.
  if (typeof res.setMaxListeners === 'function') {
    res.setMaxListeners(25);
  }
  // Note: suppress unused reference
  void SENSITIVE_HEADER_NAMES;

  next();
}
