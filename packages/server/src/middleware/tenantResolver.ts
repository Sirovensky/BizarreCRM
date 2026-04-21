import type { Request, Response, NextFunction } from 'express';
import path from 'path';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { getTenantDb } from '../db/tenant-pool.js';
import { createAsyncDb } from '../db/async-db.js';
import { getPlanDefinition, type TenantPlan } from '@bizarre-crm/shared';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';

const log = createLogger('tenantResolver');

/**
 * DEBUG-SEC1: module-local flag so the loud "dev-bypass active" banner logs
 * exactly ONCE per process boot instead of every request. Checked + flipped
 * inside the resolver on first bare-IP traffic.
 */
let bareIpBypassBannerShown = false;

// SEC (H1): Default timezone used for trial-expiry math when the tenant's
// timezone has not yet been configured (e.g. early in provisioning). Picked
// deliberately instead of UTC so positive-offset tenants don't silently lose
// hours off their trial window.
const DEFAULT_TENANT_TIMEZONE = 'America/Denver';

/**
 * SEC (H1): Normalize a Host header value by stripping the :port suffix and
 * lower-casing. Returns an empty string for nullish input.
 */
function normalizeHost(raw: string | undefined | null): string {
  if (!raw) return '';
  // Host may include a port (e.g. "shop.example.com:443") — strip it.
  const withoutPort = raw.split(':')[0] ?? '';
  return withoutPort.trim().toLowerCase();
}

/**
 * SEC (H1): Verify the requesting Host header matches an allowed pattern. The
 * only acceptable hostnames are the base domain itself, any subdomain of the
 * base domain, or localhost (for dev + setup flows). This is applied BEFORE we
 * look up the tenant so spoofed Host values can't reach the DB.
 */
function isAllowedHostname(host: string, baseDomain: string): boolean {
  if (!host) return false;
  if (host === baseDomain) return true;
  if (host === 'localhost') return true;
  if (host.endsWith(`.${baseDomain}`)) return true;
  if (host.endsWith('.localhost')) return true;
  // Dev-only: accept bare IPv4 hosts so the Android client + other on-LAN
  // devices can reach a self-hosted instance via "https://<lan-ip>:443"
  // without a real DNS name or subdomain. Never enabled in production.
  if (process.env.NODE_ENV !== 'production' && /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
  return false;
}

/**
 * SEC (H1): Resolve the effective Host header for tenant lookup while
 * rejecting client-controlled X-Forwarded-Host values unless the request
 * arrived from a trusted reverse-proxy IP.
 *
 * Express's `req.hostname` already honors `X-Forwarded-Host` when
 * `trust proxy` is enabled. That's unsafe on the edge where a malicious
 * client could spoof Host and route to another tenant. Instead, we compute
 * the effective host ourselves from the raw `Host` header and only trust
 * `X-Forwarded-Host` when the socket's IP appears in `config.trustedProxyIps`.
 */
function resolveEffectiveHost(req: Request): string {
  const trustedIps = config.trustedProxyIps;
  const socketIp = req.socket?.remoteAddress || '';
  const remoteIsTrusted = trustedIps.length > 0 && trustedIps.includes(socketIp);

  if (remoteIsTrusted) {
    const fwdHostRaw = req.headers['x-forwarded-host'];
    const fwdHost = Array.isArray(fwdHostRaw) ? fwdHostRaw[0] : fwdHostRaw;
    // Only honor the FIRST value in a comma-separated list — that's the
    // outermost proxy's view of the request. Any extra values are downstream.
    if (typeof fwdHost === 'string' && fwdHost.length > 0) {
      const firstHop = fwdHost.split(',')[0] ?? '';
      return normalizeHost(firstHop);
    }
  }

  // Fall back to the direct Host header from the wire. This ignores
  // X-Forwarded-Host from untrusted sources entirely.
  return normalizeHost(req.headers.host);
}

/**
 * SEC (TZ4): Look up the tenant's configured IANA timezone from the tenant's
 * own store_config row. Returns DEFAULT_TENANT_TIMEZONE when the row is
 * missing or the lookup fails (e.g. DB not yet populated during provisioning).
 */
function getTenantTimezoneSafe(tenantDb: unknown, tenantSlug: string): string {
  try {
    const db = tenantDb as { prepare: (sql: string) => { get: () => { value?: string } | undefined } };
    const row = db.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get();
    const tz = row?.value;
    if (tz && typeof tz === 'string' && tz.trim()) {
      return tz.trim();
    }
    log.warn('tenant timezone unset, using default for trial math', {
      tenantSlug,
      default: DEFAULT_TENANT_TIMEZONE,
    });
    return DEFAULT_TENANT_TIMEZONE;
  } catch (err) {
    log.warn('failed to read tenant timezone, using default for trial math', {
      tenantSlug,
      default: DEFAULT_TENANT_TIMEZONE,
      error: err instanceof Error ? err.message : String(err),
    });
    return DEFAULT_TENANT_TIMEZONE;
  }
}

/**
 * SEC (TZ4): Parse a SQLite-style datetime string as UTC. The master DB stores
 * `trial_ends_at` via `datetime('now', '+14 days')` which yields `"YYYY-MM-DD HH:MM:SS"`
 * with NO timezone suffix — `new Date(...)` of that string is parsed as LOCAL
 * time on some platforms, which produces the "lose 8 hours of trial" bug.
 * Force UTC interpretation here.
 */
function parseSqliteUtc(value: string): Date {
  // Handle both "YYYY-MM-DD HH:MM:SS" and full ISO strings. If the value
  // already carries timezone info (Z or +hh:mm), pass through.
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(value)) {
    return new Date(value);
  }
  // Replace the space separator with 'T' and append 'Z' to force UTC.
  const iso = value.includes('T') ? `${value}Z` : `${value.replace(' ', 'T')}Z`;
  return new Date(iso);
}

/**
 * SEC (TZ4): Decide whether an active trial is still running, comparing the
 * stored UTC trial end against "now" rendered in the tenant's local timezone.
 * The fix is actually to keep both operands in real milliseconds (UTC), which
 * is tz-neutral — the prior bug came from `new Date(sqliteString)` parsing the
 * string as LOCAL, shifting the instant. We also skew the cut-off by the
 * tenant's local-midnight offset so a 14-day trial ends at end-of-day in the
 * tenant's own calendar, not at UTC midnight.
 */
function isTrialActive(trialEndsAt: string | null, tenantTz: string): boolean {
  if (!trialEndsAt) return false;
  const trialEnd = parseSqliteUtc(trialEndsAt);
  if (Number.isNaN(trialEnd.getTime())) return false;

  // Anchor the cut-off to end-of-day (23:59:59) in the tenant's local
  // calendar so UTC-8 shops don't lose 8 hours of the final day.
  const endOfLocalDay = endOfDayInTimezone(trialEnd, tenantTz);
  return endOfLocalDay > Date.now();
}

/**
 * TZ4: Given an instant, return the epoch ms corresponding to 23:59:59 on the
 * same calendar date IN the given IANA timezone. Uses Intl.DateTimeFormat so
 * it works without a full tz library.
 */
function endOfDayInTimezone(instant: Date, tz: string): number {
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    })
      .formatToParts(instant)
      .reduce<Record<string, string>>((acc, p) => {
        if (p.type !== 'literal') acc[p.type] = p.value;
        return acc;
      }, {});
    // Calendar date in tenant's timezone.
    const y = parts.year;
    const m = parts.month;
    const d = parts.day;
    // Walk the offset: compute local midnight (as UTC), then figure out what
    // offset the tz had at that moment, then add 23:59:59.999.
    const localMidnightUtc = new Date(`${y}-${m}-${d}T00:00:00Z`).getTime();
    // Format the localMidnightUtc in the tz — if the displayed hour is not 0,
    // that difference tells us the offset of that tz at that instant.
    const offsetFmt = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hour: '2-digit',
      hour12: false,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(new Date(localMidnightUtc));
    const offsetHour = Number(offsetFmt.find(p => p.type === 'hour')?.value || '0');
    // offsetHour is the tz-local hour that corresponds to UTC midnight on that
    // calendar date. e.g. UTC-8 -> 16 (previous day's 4pm). Convert to signed
    // offset in ms: offsetMs = (offsetHour <= 12 ? offsetHour : offsetHour - 24) * 3600_000.
    const signedHours = offsetHour <= 12 ? offsetHour : offsetHour - 24;
    // Real local midnight (in UTC) = localMidnightUtc - signedHours.
    const realLocalMidnightUtc = localMidnightUtc - signedHours * 3_600_000;
    return realLocalMidnightUtc + 86_399_999;
  } catch {
    // Fallback: compare the raw instant (no tz adjustment).
    return instant.getTime();
  }
}

// Plan info cache (60s TTL) — avoids querying master DB on every request
interface PlanCacheEntry {
  plan: string;
  max_tickets_month: number | null;
  max_users: number | null;
  storage_limit_mb: number | null;
  trial_started_at: string | null;
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

  // SEC (H1): Resolve the effective host ourselves — do NOT trust
  // req.hostname. Express applies trust-proxy rules that make req.hostname
  // honor X-Forwarded-Host from ANY upstream, which an attacker can spoof to
  // route a request into a different tenant. We only honor X-Forwarded-Host
  // when the socket peer IP is in config.trustedProxyIps.
  const host = resolveEffectiveHost(req);
  const baseDomain = config.baseDomain.toLowerCase();

  // Dev-only: bare IPv4 host → resolve to a configured dev tenant so the
  // Android self-hosted flow (URL = https://<lan-ip>) reaches the right DB
  // without needing a real DNS subdomain. Prefer DEV_TENANT_SLUG; fall back
  // to the first active tenant. MUST run BEFORE isAllowedHostname() — the
  // allow-list rejects anything that isn't baseDomain / *.baseDomain /
  // localhost, and a raw LAN IP clearly fails that test. We rewrite the
  // Host header to the tenant's subdomain form here so the allow-list and
  // the downstream subdomain extraction both see the canonical value.
  //
  // DEBUG-SEC1 hardening (2026-04-17): two-key gate required before the
  // bypass fires. Production MUST satisfy neither: (1) NODE_ENV != production
  // keeps the historic gate, (2) APP_ENV=development is the new explicit
  // opt-in. A misconfigured deploy that flips NODE_ENV back to `development`
  // still requires an operator to also set APP_ENV=development so the
  // bypass can't silently re-enable on a typo. First request through the
  // bypass also emits a one-shot logger.warn banner so ops dashboards
  // make the dev-mode state loud rather than invisible.
  const isNonProdNodeEnv = process.env.NODE_ENV !== 'production';
  const isDevAppEnv = process.env.APP_ENV === 'development';
  const bareIpBypassAllowed = isNonProdNodeEnv && isDevAppEnv;
  const isBareIp = bareIpBypassAllowed && /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host);
  if (isBareIp && !bareIpBypassBannerShown) {
    log.warn(
      'DEBUG-SEC1 active: bare-IPv4 Host headers routed to dev tenant. Must be off in production.',
      {
        node_env: process.env.NODE_ENV,
        app_env: process.env.APP_ENV,
        dev_tenant_slug: process.env.DEV_TENANT_SLUG || '(first active tenant)',
      },
    );
    bareIpBypassBannerShown = true;
  }
  if (isBareIp) {
    const preferred = process.env.DEV_TENANT_SLUG?.trim().toLowerCase();
    let devTenant: { slug: string } | undefined;
    try {
      if (preferred) {
        devTenant = masterDb.prepare("SELECT slug FROM tenants WHERE slug = ? AND status = 'active'").get(preferred) as typeof devTenant;
      }
      if (!devTenant) {
        devTenant = masterDb.prepare("SELECT slug FROM tenants WHERE status = 'active' ORDER BY id ASC LIMIT 1").get() as typeof devTenant;
      }
    } catch (err) {
      log.warn('dev-tenant lookup failed for bare-IP host', { host, err: (err as Error).message });
    }
    if (devTenant) {
      log.info('routing bare-IP dev request to tenant', { host, slug: devTenant.slug });
      // Rewrite the effective host to the tenant's subdomain so the allow-list
      // below + the downstream subdomain extraction both resolve cleanly.
      (req.headers as Record<string, string>).host = `${devTenant.slug}.${baseDomain}`;
    }
  }

  // SEC (H1): Strictly reject Host headers that don't match our domain
  // pattern. Anything not matching baseDomain/*.baseDomain/localhost is
  // treated as a bogus / spoofed request and returns 404 — never looks up
  // tenants. Re-resolve host after the bare-IP rewrite above so the
  // dev flow passes the allow-list as a tenant subdomain.
  const effectiveHost = isBareIp ? resolveEffectiveHost(req) : host;
  const rid = res.locals.requestId as string | undefined;
  if (!isAllowedHostname(effectiveHost, baseDomain)) {
    log.warn('rejected request with unexpected Host header', {
      host: effectiveHost || '(empty)',
      ip: req.socket?.remoteAddress || 'unknown',
      path: req.path,
      requestId: rid,
    });
    res.status(404).json(errorBody(
      ERROR_CODES.ERR_TENANT_HOST_INVALID,
      'Shop not found. Check the URL and try again.',
      rid,
    ));
    return;
  }

  // effectiveHost already resolved above (via resolveEffectiveHost post-rewrite
  // or the original host). Downstream resolver logic uses this canonical form.

  // Bare domain (no subdomain) — block most API paths, allow platform routes
  if (effectiveHost === baseDomain || effectiveHost === 'localhost') {
    // Allow specific API endpoints that work without a tenant context
    const allowedBareDomainPaths = [
      '/api/v1/auth/setup-status',
      '/api/v1/auth/setup',
      '/api/v1/health',
      '/api/v1/health/ready',
      '/api/v1/info',
    ];
    const allowedBareDomainPrefixes = [
      '/api/v1/management',
      '/api/v1/admin',
    ];
    const isAllowedPath = allowedBareDomainPaths.some(p => req.path === p)
      || allowedBareDomainPrefixes.some(p => req.path.startsWith(p));

    if (!isAllowedPath && req.path.startsWith('/api/v1/')) {
      res.status(404).json(errorBody(
        ERROR_CODES.ERR_TENANT_BARE_DOMAIN,
        `Please access your shop via its subdomain (e.g., yourshop.${baseDomain}).`,
        rid,
      ));
      return;
    }

    // Non-API paths (landing page, super-admin, static assets) — let through
    next();
    return;
  }

  // Extract subdomain: "repairshop1.example.com" → "repairshop1"
  // Also handle localhost subdomains: "repairshop1.localhost" → "repairshop1"
  const domainSuffix = effectiveHost.endsWith('.localhost') ? 'localhost' : baseDomain;
  const slug = effectiveHost.slice(0, -(domainSuffix.length + 1));

  // Validate slug format (strict: lowercase alphanumeric + hyphens, 3-30 chars)
  if (!slug || slug.length < 3 || slug.length > 30 || !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug)) {
    res.status(404).json(errorBody(
      ERROR_CODES.ERR_TENANT_NOT_FOUND,
      'Shop not found. Check the URL and try again.',
      rid,
    ));
    return;
  }

  // Skip reserved subdomains — these are infrastructure, not tenant shops
  if (RESERVED_SLUGS.has(slug)) {
    res.status(404).json(errorBody(
      ERROR_CODES.ERR_TENANT_NOT_FOUND,
      'Shop not found. Check the URL and try again.',
      rid,
    ));
    return;
  }

  // Look up tenant in master DB — wrapped in try-catch to prevent 500 JSON on DB errors
  let tenant: { id: number; slug: string; status: string; db_path: string; plan: string; max_tickets_month: number | null; max_users: number | null; storage_limit_mb: number | null; trial_started_at: string | null; trial_ends_at: string | null } | undefined;
  try {
    tenant = masterDb.prepare(
      "SELECT id, slug, status, db_path, plan, max_tickets_month, max_users, storage_limit_mb, trial_started_at, trial_ends_at FROM tenants WHERE slug = ?"
    ).get(slug) as typeof tenant;
  } catch (err) {
    console.error('[TenantResolver] DB query failed for slug:', slug, err);
    next(); // Let the request through — better to serve static assets than crash
    return;
  }

  // SEC (E8): When a tenant does not exist OR is suspended OR is in any
  // non-active/non-provisioning state, we MUST return the same 404 response
  // so outsiders can't discriminate between "shop never existed" and "shop
  // was suspended" via a simple probing loop. Log the real status for ops.
  if (!tenant) {
    log.info('tenant not found', { slug, ip: req.socket?.remoteAddress || 'unknown', requestId: rid });
    res.status(404).json(errorBody(
      ERROR_CODES.ERR_TENANT_NOT_FOUND,
      'Shop not found. Check the URL and try again.',
      rid,
    ));
    return;
  }

  if (tenant.status === 'suspended') {
    log.warn('request to suspended tenant', { slug, ip: req.socket?.remoteAddress || 'unknown', requestId: rid });
    res.status(404).json(errorBody(
      ERROR_CODES.ERR_TENANT_NOT_FOUND,
      'Shop not found. Check the URL and try again.',
      rid,
    ));
    return;
  }

  if (tenant.status === 'provisioning') {
    // Provisioning is a transient legitimate state — distinct 503 is OK
    // because the tenant DID just sign up in this browser session.
    res.status(503).json(errorBody(
      ERROR_CODES.ERR_TENANT_PROVISIONING,
      'This shop is still being set up. Please try again in a moment.',
      rid,
    ));
    return;
  }

  if (tenant.status !== 'active') {
    log.warn('tenant in unknown status', { slug, status: tenant.status, requestId: rid });
    res.status(404).json(errorBody(
      ERROR_CODES.ERR_TENANT_NOT_FOUND,
      'Shop not found. Check the URL and try again.',
      rid,
    ));
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
    res.status(500).json(errorBody(
      ERROR_CODES.ERR_TENANT_DB_FAILED,
      'Failed to connect to shop database.',
      rid,
    ));
    return;
  }

  // Resolve effective plan (Pro during active trial) — check cache first
  const cached = planCache.get(tenant.id);
  const now = Date.now();
  let planData: { plan: string; max_tickets_month: number | null; max_users: number | null; storage_limit_mb: number | null; trial_started_at: string | null; trial_ends_at: string | null };

  if (cached && (now - cached.cachedAt) < PLAN_CACHE_TTL_MS) {
    planData = cached;
  } else {
    planData = {
      plan: tenant.plan,
      max_tickets_month: tenant.max_tickets_month,
      max_users: tenant.max_users,
      storage_limit_mb: tenant.storage_limit_mb,
      trial_started_at: tenant.trial_started_at,
      trial_ends_at: tenant.trial_ends_at,
    };
    planCache.set(tenant.id, { ...planData, cachedAt: now });
  }

  // SEC (TZ4): Trial expiry math must run in the tenant's LOCAL timezone, not
  // against raw UTC milliseconds. The master DB stores `trial_ends_at` via
  // SQLite's `datetime('now', '+14 days')` which has no tz suffix — parsing
  // that string with `new Date(...)` silently picks up the SERVER's local tz,
  // shifting the cut-off. We fix this by (a) parsing the stored string as UTC
  // and (b) anchoring the cut-off to end-of-day in the tenant's store_timezone.
  const tenantTz = getTenantTimezoneSafe(req.db, tenant.slug);
  const trialActive = isTrialActive(planData.trial_ends_at, tenantTz);

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
