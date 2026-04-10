import type { Request, Response, NextFunction } from 'express';
import path from 'path';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { getTenantDb } from '../db/tenant-pool.js';
import { createAsyncDb } from '../db/async-db.js';
import { getPlanDefinition, type TenantPlan } from '@bizarre-crm/shared';

// Plan info cache (60s TTL) — avoids querying master DB on every request
interface PlanCacheEntry {
  plan: string;
  max_tickets_month: number | null;
  max_users: number | null;
  storage_limit_mb: number | null;
  trial_ends_at: string | null;
  cachedAt: number;
}
const planCache = new Map<number, PlanCacheEntry>();
const PLAN_CACHE_TTL_MS = 60_000;

/**
 * Invalidate a tenant's plan cache entry. Call this after updating tenant plan/limits
 * in the master DB so the next request re-reads fresh data instead of serving a stale
 * cached plan for up to 60 seconds.
 */
export function clearPlanCache(tenantId: number): void {
  planCache.delete(tenantId);
}

/**
 * Invalidate every cached plan entry. Use sparingly (e.g. bulk admin operations).
 */
export function clearAllPlanCache(): void {
  planCache.clear();
}

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
  const platformPaths = ['/super-admin', '/api/v1/signup', '/api/v1/sms/inbound-webhook', '/api/v1/sms/status-webhook', '/api/v1/voice/', '/api/v1/info', '/api/v1/management', '/api/v1/admin', '/api/v1/billing/webhook'];
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

  // Look up tenant in master DB — wrapped in try-catch to prevent 500 JSON on DB errors
  let tenant: { id: number; slug: string; status: string; db_path: string; plan: string; max_tickets_month: number | null; max_users: number | null; storage_limit_mb: number | null; trial_ends_at: string | null } | undefined;
  try {
    tenant = masterDb.prepare(
      "SELECT id, slug, status, db_path, plan, max_tickets_month, max_users, storage_limit_mb, trial_ends_at FROM tenants WHERE slug = ?"
    ).get(slug) as typeof tenant;
  } catch (err) {
    console.error('[TenantResolver] DB query failed for slug:', slug, err);
    next(); // Let the request through — better to serve static assets than crash
    return;
  }

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

  // Open tenant DB first — only cache plan on successful connection
  try {
    // SECURITY: getTenantDb validates slug format again and verifies path is within tenantDataDir
    req.db = getTenantDb(tenant.slug);
    // Async DB for worker-thread based queries (gradual migration)
    const tenantDbPath = path.join(config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'), `${tenant.slug}.db`);
    req.asyncDb = createAsyncDb(tenantDbPath);
  } catch (err) {
    console.error(`[Tenant] Failed to open DB for ${tenant.slug}:`, err);
    // Invalidate cached plan so next request retries fresh
    planCache.delete(tenant.id);
    res.status(500).json({ success: false, message: 'Failed to connect to shop database.' });
    return;
  }

  // Resolve effective plan (Pro during active trial) — check cache first
  const cached = planCache.get(tenant.id);
  const now = Date.now();
  let planData: { plan: string; max_tickets_month: number | null; max_users: number | null; storage_limit_mb: number | null; trial_ends_at: string | null };

  if (cached && (now - cached.cachedAt) < PLAN_CACHE_TTL_MS) {
    planData = cached;
  } else {
    planData = {
      plan: tenant.plan,
      max_tickets_month: tenant.max_tickets_month,
      max_users: tenant.max_users,
      storage_limit_mb: tenant.storage_limit_mb,
      trial_ends_at: tenant.trial_ends_at,
    };
    planCache.set(tenant.id, { ...planData, cachedAt: now });
  }

  // Parse trial date safely (Date-based, not string comparison) — handles microsecond/timezone edge cases
  let trialActive = false;
  if (planData.trial_ends_at) {
    const trialEnd = new Date(planData.trial_ends_at);
    if (!Number.isNaN(trialEnd.getTime())) {
      trialActive = trialEnd.getTime() > now;
    }
  }

  // Normalize stored plan to a valid TenantPlan (unknown/corrupted values fall back to 'free')
  const storedPlan: TenantPlan = (planData.plan === 'pro' ? 'pro' : 'free');
  const effectivePlan: TenantPlan = trialActive ? 'pro' : storedPlan;
  const planDef = getPlanDefinition(effectivePlan);

  req.tenantPlan = effectivePlan;
  req.tenantLimits = {
    // Pro: use plan definition (includes 2GB storage cap, not null!)
    // Free: prefer tenant row overrides (super-admin can grant custom caps) then plan defaults
    maxTicketsMonth: effectivePlan === 'pro'
      ? planDef.limits.maxTicketsMonth
      : (planData.max_tickets_month ?? planDef.limits.maxTicketsMonth),
    maxUsers: effectivePlan === 'pro'
      ? planDef.limits.maxUsers
      : (planData.max_users ?? planDef.limits.maxUsers),
    storageLimitMb: effectivePlan === 'pro'
      ? planDef.limits.storageLimitMb
      : (planData.storage_limit_mb ?? planDef.limits.storageLimitMb),
  };
  req.tenantTrialActive = trialActive;
  req.tenantTrialEndsAt = planData.trial_ends_at || null;

  next();
}
