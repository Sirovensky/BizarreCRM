import type { Request, Response, NextFunction } from 'express';
import path from 'path';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { getTenantDb } from '../db/tenant-pool.js';
import { createAsyncDb } from '../db/async-db.js';

// Reserved subdomains that should never be treated as tenant slugs
const RESERVED_SLUGS = new Set([
  'www', 'api', 'admin', 'master', 'app', 'mail', 'smtp', 'ftp',
  'cdn', 'static', 'assets', 'status', 'docs', 'help', 'support',
  'billing', 'signup', 'login', 'register',
]);

/**
 * Tenant resolution middleware.
 *
 * Extracts the subdomain from the Host header, looks up the tenant in the master DB,
 * and sets req.db to the tenant's database connection.
 *
 * SECURITY:
 * - Slug is extracted from the Host header (not from query params or body — immune to body injection)
 * - Slug is validated with strict regex (a-z, 0-9, hyphens only)
 * - Slug is looked up in the master DB — only registered tenants are accessible
 * - The DB file path comes from the master DB record, NOT from user input
 * - Path traversal is blocked by the tenant pool (verifies resolved path stays within tenantDataDir)
 * - Reserved subdomains (www, api, admin, master) are skipped
 */
export function tenantResolver(req: Request, res: Response, next: NextFunction): void {
  // Skip in single-tenant mode
  if (!config.multiTenant) {
    next();
    return;
  }

  const masterDb = getMasterDb();
  if (!masterDb) {
    next();
    return;
  }

  // Skip tenant resolution for static assets (CSS, JS, images, fonts)
  // These must always be served regardless of host/subdomain
  if (/\.(css|js|map|ico|png|jpg|jpeg|gif|svg|webp|woff2?|ttf|eot|json|webmanifest)$/i.test(req.path)) {
    next();
    return;
  }

  // Skip tenant resolution for platform-level routes (super-admin, signup, webhooks, info)
  const platformPaths = ['/super-admin', '/api/v1/signup', '/api/v1/sms/inbound-webhook', '/api/v1/sms/status-webhook', '/api/v1/voice/', '/api/v1/info', '/api/v1/management', '/api/v1/admin'];
  if (platformPaths.some(p => req.path.startsWith(p))) {
    next();
    return;
  }

  const host = req.hostname; // e.g. "repairshop1.bizarrecrm.com"
  const baseDomain = config.baseDomain; // "bizarrecrm.com"

  // Check if the host ends with the base domain and has a subdomain
  // Also allow bare base domain access and localhost (for super-admin panel, landing page)
  if (!host.endsWith(`.${baseDomain}`) && host !== baseDomain && host !== 'localhost' && !host.endsWith('.localhost')) {
    // In multi-tenant mode, requests not matching the base domain pattern are rejected.
    res.status(404).json({ success: false, message: 'Shop not found. Check the URL and try again.' });
    return;
  }

  // Bare domain (no subdomain) — block most API paths, allow platform routes
  if (host === baseDomain || host === 'localhost') {
    // Allow specific API endpoints that work without a tenant context
    const allowedBareDomainPaths = [
      '/api/v1/auth/setup-status',
      '/api/v1/auth/setup',
      '/api/v1/health',
      '/api/v1/info',
    ];
    const allowedBareDomainPrefixes = [
      '/api/v1/management',
      '/api/v1/admin',
    ];
    const isAllowedPath = allowedBareDomainPaths.some(p => req.path === p)
      || allowedBareDomainPrefixes.some(p => req.path.startsWith(p));

    if (!isAllowedPath && req.path.startsWith('/api/v1/')) {
      res.status(404).json({
        success: false,
        message: 'Please access your shop via its subdomain (e.g., yourshop.localhost).',
      });
      return;
    }

    // Non-API paths (landing page, super-admin, static assets) — let through
    next();
    return;
  }

  // Extract subdomain: "repairshop1.bizarrecrm.com" → "repairshop1"
  // Also handle localhost subdomains: "repairshop1.localhost" → "repairshop1"
  const domainSuffix = host.endsWith('.localhost') ? 'localhost' : baseDomain;
  const slug = host.slice(0, -(domainSuffix.length + 1));

  // Validate slug format (strict: lowercase alphanumeric + hyphens, 3-30 chars)
  if (!slug || slug.length < 3 || slug.length > 30 || !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug)) {
    res.status(404).json({ success: false, message: 'Shop not found. Check the URL and try again.' });
    return;
  }

  // Skip reserved subdomains — these are infrastructure, not tenant shops
  if (RESERVED_SLUGS.has(slug)) {
    res.status(404).json({ success: false, message: 'Shop not found. Check the URL and try again.' });
    return;
  }

  // Look up tenant in master DB
  const tenant = masterDb.prepare(
    "SELECT id, slug, status, db_path FROM tenants WHERE slug = ?"
  ).get(slug) as { id: number; slug: string; status: string; db_path: string } | undefined;

  if (!tenant) {
    res.status(404).json({ success: false, message: 'Shop not found. Check the URL and try again.' });
    return;
  }

  if (tenant.status === 'suspended') {
    res.status(403).json({ success: false, message: 'This account has been suspended. Contact support for assistance.' });
    return;
  }

  if (tenant.status === 'provisioning') {
    res.status(503).json({ success: false, message: 'This shop is still being set up. Please try again in a moment.' });
    return;
  }

  if (tenant.status !== 'active') {
    res.status(404).json({ success: false, message: 'Shop not found.' });
    return;
  }

  // Set tenant context on the request
  req.tenantSlug = tenant.slug;
  req.tenantId = tenant.id;

  try {
    // SECURITY: getTenantDb validates slug format again and verifies path is within tenantDataDir
    req.db = getTenantDb(tenant.slug);
    // Async DB for worker-thread based queries (gradual migration)
    const tenantDbPath = path.join(config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'), `${tenant.slug}.db`);
    req.asyncDb = createAsyncDb(tenantDbPath);
  } catch (err) {
    console.error(`[Tenant] Failed to open DB for ${tenant.slug}:`, err);
    res.status(500).json({ success: false, message: 'Failed to connect to shop database.' });
    return;
  }

  next();
}
