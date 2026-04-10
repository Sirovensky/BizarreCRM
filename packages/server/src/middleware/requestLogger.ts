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

// Paths that generate high-frequency noise and don't need individual logging
const SKIP_PATHS = new Set(['/health', '/api/v1/health', '/favicon.ico']);

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  recordRequest();

  // SEC-NEW: Per-tenant request counting
  const slug = (req as any).tenantSlug || 'bare-domain';
  const now = Date.now();
  const entry = tenantRequests.get(slug);
  if (entry && entry.resetAt > now) {
    entry.count++;
  } else {
    tenantRequests.set(slug, { count: 1, resetAt: now + 60000 });
  }

  // Skip noisy endpoints to reduce log volume
  if (SKIP_PATHS.has(req.path)) {
    res.on('finish', () => {
      recordResponseTime(Date.now() - Date.now());
    });
    return next();
  }

  const start = Date.now();

  // Hook into response finish event to capture status and timing
  res.on('finish', () => {
    const duration = Date.now() - start;
    recordResponseTime(duration);

    const meta = {
      method: req.method,
      path: req.originalUrl || req.path,
      status: res.statusCode,
      duration_ms: duration,
      ip: req.ip || req.socket?.remoteAddress || 'unknown',
      userAgent: req.headers['user-agent'] || 'unknown',
      contentLength: res.getHeader('content-length') || 0,
      userId: (req as any).user?.id || null,
      tenantSlug: (req as any).tenantSlug || null,
    };

    const message = `${req.method} ${meta.path} ${res.statusCode} ${duration}ms`;

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

  next();
}
