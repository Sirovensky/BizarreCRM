import crypto from 'crypto';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env — single source of truth for all config including NODE_ENV.
// Repo-root .env is loaded last so it wins over a package-local fallback.
const serverRoot = path.resolve(__dirname, '..');
const projectRoot = path.resolve(serverRoot, '..', '..');
const envPaths = [
  path.join(serverRoot, '.env'),
  path.join(projectRoot, '.env'),
];
for (const envPath of envPaths) {
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath, override: true });
  }
}

export const config = {
  // @audit-fixed: parseInt() without a radix previously relied on the implicit
  // base-10 interpretation. Explicit radix 10 is the standards-compliant form
  // and sidesteps the edge case where `0x1bb` or `071` in .env would be parsed
  // unexpectedly. Also falls back to 443 if the parse returns NaN.
  port: (() => {
    const raw = process.env.PORT || '443';
    const n = parseInt(raw, 10);
    return Number.isFinite(n) && n > 0 && n < 65536 ? n : 443;
  })(),
  host: process.env.HOST || '0.0.0.0',
  jwtSecret: (() => {
    const secret = process.env.JWT_SECRET;
    const env = process.env.NODE_ENV || 'development';
    const INSECURE_SECRETS = ['dev-secret-change-me', 'change-me-to-a-random-string', 'change-me', ''];
    if (env === 'production') {
      if (!secret || INSECURE_SECRETS.includes(secret)) {
        console.error('\n  FATAL: JWT_SECRET must be set to a secure random value in production!');
        console.error('  Generate one with: node -e "console.log(require(\'crypto\').randomBytes(64).toString(\'hex\'))"\n');
        process.exit(1);
      }
      if (secret.length < 32) {
        console.error('\n  FATAL: JWT_SECRET is too short (min 32 chars). Use a 64-byte hex string.\n');
        process.exit(1);
      }
    }
    if (!secret || INSECURE_SECRETS.includes(secret)) {
      console.warn('\n  WARNING: Using default JWT secret. Set JWT_SECRET env var for production.\n');
    }
    return secret || 'dev-secret-change-me';
  })(),
  // SA1-1: optional rotation fallback. When set, tokens signed with the OLD
  // secret continue to verify until they naturally expire, so rotating
  // JWT_SECRET no longer invalidates every active session. See
  // utils/jwtSecrets.ts + docs/operator-guide.md for the full procedure.
  jwtSecretPrevious: (() => {
    const raw = (process.env.JWT_SECRET_PREVIOUS || '').trim();
    // An empty string means "not rotating" — undefined is clearer to callers.
    if (!raw) return undefined;
    // Defensive: refuse to accept an obviously-insecure placeholder as the
    // previous secret. Operators who land here accidentally would otherwise
    // widen the verification surface to a well-known string.
    const INSECURE_SECRETS = ['dev-secret-change-me', 'change-me-to-a-random-string', 'change-me', ''];
    if (INSECURE_SECRETS.includes(raw) || raw.length < 32) {
      console.warn('\n  [JWT Rotation] JWT_SECRET_PREVIOUS is too short or insecure — ignored.\n');
      return undefined;
    }
    return raw;
  })(),
  jwtRefreshSecret: (() => {
    const secret = process.env.JWT_REFRESH_SECRET;
    const env = process.env.NODE_ENV || 'development';
    const INSECURE_SECRETS = ['dev-refresh-secret-change-me', 'change-me-to-another-random-string', 'change-me', ''];
    if (env === 'production') {
      if (!secret || INSECURE_SECRETS.includes(secret)) {
        console.error('\n  FATAL: JWT_REFRESH_SECRET must be set to a secure random value in production!');
        console.error('  Generate one with: node -e "console.log(require(\'crypto\').randomBytes(64).toString(\'hex\'))"\n');
        process.exit(1);
      }
      if (secret.length < 32) {
        console.error('\n  FATAL: JWT_REFRESH_SECRET is too short (min 32 chars). Use a 64-byte hex string.\n');
        process.exit(1);
      }
    }
    if (!secret || INSECURE_SECRETS.includes(secret)) {
      console.warn('\n  WARNING: Using default JWT refresh secret. Set JWT_REFRESH_SECRET env var for production.\n');
    }
    return secret || 'dev-refresh-secret-change-me';
  })(),
  // SA1-1: rotation fallback for refresh tokens. Same semantics as
  // jwtSecretPrevious above.
  jwtRefreshSecretPrevious: (() => {
    const raw = (process.env.JWT_REFRESH_SECRET_PREVIOUS || '').trim();
    if (!raw) return undefined;
    const INSECURE_SECRETS = ['dev-refresh-secret-change-me', 'change-me-to-another-random-string', 'change-me', ''];
    if (INSECURE_SECRETS.includes(raw) || raw.length < 32) {
      console.warn('\n  [JWT Rotation] JWT_REFRESH_SECRET_PREVIOUS is too short or insecure — ignored.\n');
      return undefined;
    }
    return raw;
  })(),
  nodeEnv: process.env.NODE_ENV || 'development',
  // Stripe billing — OPTIONAL feature. Previously fatal in production multi-tenant
  // mode, but per the project rule "server should never refuse to boot because of
  // an optional feature's config" (same as the Cloudflare fix in af34542), missing
  // Stripe vars now emit a warning and disable billing routes at runtime. The
  // /billing/* endpoints check stripeEnabled and return a clear error if the
  // feature is off. All three vars must be set together to enable billing.
  stripeSecretKey: process.env.STRIPE_SECRET_KEY || '',
  stripeWebhookSecret: process.env.STRIPE_WEBHOOK_SECRET || '',
  stripeProPriceId: process.env.STRIPE_PRO_PRICE_ID || '',
  stripeEnabled: (() => {
    const enabled = !!(
      process.env.STRIPE_SECRET_KEY &&
      process.env.STRIPE_WEBHOOK_SECRET &&
      process.env.STRIPE_PRO_PRICE_ID
    );
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const env = process.env.NODE_ENV || 'development';
    if (!enabled && isMultiTenant && env === 'production') {
      console.warn('\n  [Stripe] Billing disabled: one or more of STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET / STRIPE_PRO_PRICE_ID is not set.');
      console.warn('  [Stripe] /billing/* endpoints will return errors until all three are configured.\n');
    }
    return enabled;
  })(),
  dbPath: path.resolve(__dirname, '../data/bizarre-crm.db'),
  uploadsPath: path.resolve(__dirname, '../uploads'),
  // SEC-H54: separate directory for sensitive super-admin artefacts (tenant
  // license docs, signed agreements, KYC attachments). Served under
  // /admin-uploads/* behind localhostOnly + superAdminAuth — distinct
  // handler from the regular /uploads/* path so a tenant-auth bypass
  // cannot reach these files.
  adminUploadsPath: path.resolve(__dirname, '../data/admin-uploads'),
  // SEC-H54: HMAC secret for signed-URL tokens (portal receipts, outbound
  // MMS media). Distinct from JWT_SECRET so a JWT leak doesn't grant blanket
  // read access to every uploaded file. In production we REFUSE to boot
  // without an explicit value; dev mode falls back to a derived dev secret
  // so local smoke tests still work without editing .env.
  uploadsSecret: (() => {
    const secret = process.env.UPLOADS_SECRET;
    const env = process.env.NODE_ENV || 'development';
    const INSECURE_SECRETS = ['change-me', 'change-me-to-a-random-string', ''];
    if (env === 'production') {
      if (!secret || INSECURE_SECRETS.includes(secret)) {
        console.error('\n  FATAL: UPLOADS_SECRET must be set to a secure random value in production!');
        console.error('  Generate one with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"\n');
        process.exit(1);
      }
      if (secret.length < 32) {
        console.error('\n  FATAL: UPLOADS_SECRET is too short (min 32 chars). Use a 32-byte hex string.\n');
        process.exit(1);
      }
    }
    if (!secret || INSECURE_SECRETS.includes(secret)) {
      console.warn('\n  WARNING: Using default UPLOADS_SECRET (dev fallback). Set UPLOADS_SECRET env var for production.\n');
    }
    // Dev fallback: derive from JWT_SECRET so the signed-URL verifier has a
    // stable non-empty string to work with. NEVER used when NODE_ENV=production
    // because the exit(1) above fires first.
    return secret || `dev-uploads-secret-${(process.env.JWT_SECRET || 'dev').slice(0, 16)}`;
  })(),
  // ---------------------------------------------------------------------------
  // PROD104: Outbound kill-switches — emergency suppression of all outbound
  // communications. Set to "true" in .env to immediately halt all sends of
  // that channel system-wide without a code deployment. Every suppressed send
  // emits a WARN-level log so the audit trail is never silent. Callers receive
  // a synthesised success-shape with { suppressed: true, reason: 'kill-switch' }
  // so downstream code (invoice emails, status SMS, click-to-call) does not
  // crash, but audit records can distinguish a suppressed send from a real one.
  // ---------------------------------------------------------------------------
  disableOutboundEmail: process.env.DISABLE_OUTBOUND_EMAIL === 'true',
  disableOutboundSms: process.env.DISABLE_OUTBOUND_SMS === 'true',
  disableOutboundVoice: process.env.DISABLE_OUTBOUND_VOICE === 'true',

  // NOTE: Store info, 3CX, SMTP, SMS, RepairDesk, and BlockChyp credentials
  // are all stored per-tenant in each tenant's store_config DB table.
  // They are configured via the Settings UI, NOT in this file or .env.
  // Multi-tenancy
  multiTenant: process.env.MULTI_TENANT === 'true',
  masterDbPath: path.resolve(__dirname, '../data/master.db'),
  tenantDataDir: path.resolve(__dirname, '../data/tenants'),
  templateDbPath: path.resolve(__dirname, '../data/template.db'),
  baseDomain: (() => {
    const raw = (process.env.BASE_DOMAIN || '').trim();
    const value = raw || 'localhost';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const env = process.env.NODE_ENV || 'development';
    if (isMultiTenant && env === 'production' && !raw) {
      console.error('\n  FATAL: BASE_DOMAIN must be set in production multi-tenant mode.');
      console.error('  Use the bare hostname only, for example BASE_DOMAIN=crm.example.com or BASE_DOMAIN=localhost.\n');
      process.exit(1);
    }
    if (isMultiTenant && (/^https?:\/\//i.test(value) || value.includes('/') || value.includes(':'))) {
      console.error('\n  FATAL: BASE_DOMAIN must be a bare hostname, not a URL.');
      console.error(`  Current BASE_DOMAIN=${value}`);
      console.error('  Use the bare hostname only, without protocol, path, or port.\n');
      process.exit(1);
    }
    return value.toLowerCase();
  })(),
  // SEC (H1): Trusted reverse-proxy IPs that may set X-Forwarded-Host.
  // Comma-separated list (e.g. "127.0.0.1,10.0.0.5"). Empty list means no
  // proxy is trusted and X-Forwarded-Host is ignored — only req.hostname
  // (from the direct socket's Host header) is used for tenant resolution.
  trustedProxyIps: (() => {
    const raw = process.env.TRUSTED_PROXY_IPS || '';
    return raw
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
  })(),
  // Cloudflare DNS auto-provisioning — OPTIONAL feature.
  // If any of the three vars is missing, the feature stays disabled (cloudflareEnabled=false)
  // and tenant provisioning falls back to assuming DNS is managed manually (e.g. wildcard
  // A record). The server must boot regardless — do NOT exit on missing CF config.
  cloudflareApiToken: process.env.CLOUDFLARE_API_TOKEN || '',
  cloudflareZoneId: process.env.CLOUDFLARE_ZONE_ID || '',
  serverPublicIp: process.env.SERVER_PUBLIC_IP || '',
  cloudflareEnabled: (() => {
    const enabled = !!(
      process.env.CLOUDFLARE_API_TOKEN &&
      process.env.CLOUDFLARE_ZONE_ID &&
      process.env.SERVER_PUBLIC_IP
    );
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const baseDomain = process.env.BASE_DOMAIN || 'localhost';
    const wantsCloudflare = isMultiTenant && baseDomain !== 'localhost' && !baseDomain.endsWith('.localhost');
    if (!enabled && wantsCloudflare) {
      // TPH10: louder warning. Silent signups that end in "Server Not Found"
      // (2026-04-10 newshop.bizarrecrm.com incident) happen exactly here.
      console.warn('\n\x1b[41m\x1b[97m  [Cloudflare] CRITICAL: Auto-DNS disabled in MULTI-TENANT PRODUCTION mode!  \x1b[0m');
      console.warn(`  [Cloudflare] BASE_DOMAIN = ${baseDomain}  MULTI_TENANT = true`);
      console.warn('  [Cloudflare] Missing: ' + [
        process.env.CLOUDFLARE_API_TOKEN ? null : 'CLOUDFLARE_API_TOKEN',
        process.env.CLOUDFLARE_ZONE_ID ? null : 'CLOUDFLARE_ZONE_ID',
        process.env.SERVER_PUBLIC_IP ? null : 'SERVER_PUBLIC_IP',
      ].filter(Boolean).join(', '));
      console.warn('  [Cloudflare] Every new signup will succeed but the subdomain will NOT resolve.');
      console.warn('  [Cloudflare] Users will see "Server Not Found" errors after signup.');
      console.warn('  [Cloudflare] Fix: add the three vars to .env (see .env.example) OR manage DNS via a manual wildcard A record.\n');
    }
    return enabled;
  })(),
  superAdminSecret: (() => {
    const secret = process.env.SUPER_ADMIN_SECRET;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const INSECURE_SECRETS = ['super-admin-dev-secret', 'change-me', 'change-me-in-production', ''];
    // SEC-H105: In production, ALWAYS require a secure SUPER_ADMIN_SECRET regardless of MULTI_TENANT.
    if (env === 'production') {
      if (!secret || INSECURE_SECRETS.includes(secret)) {
        console.error('\n  FATAL: SUPER_ADMIN_SECRET must be set to a secure random value in production!');
        console.error('  Generate one with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"\n');
        process.exit(1);
      }
      if (secret.length < 32) {
        console.error('\n  FATAL: SUPER_ADMIN_SECRET is too short (min 32 chars). Use a 32-byte hex string.\n');
        process.exit(1);
      }
    }
    // SEC-H4: In multi-tenant mode (non-production), ALWAYS require SUPER_ADMIN_SECRET.
    if (!secret && isMultiTenant) {
      console.error('\n  FATAL: SUPER_ADMIN_SECRET environment variable is required in multi-tenant mode (even in development).\n');
      console.error('  Generate one with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"\n');
      process.exit(1);
    }
    if (!secret || INSECURE_SECRETS.includes(secret)) {
      console.warn('\n  WARNING: Using derived super-admin dev secret (single-tenant dev mode). Set SUPER_ADMIN_SECRET env var for production.\n');
    }
    // Dev fallback: derive from JWT_SECRET so the secret is non-trivial and
    // process-specific. NEVER used when NODE_ENV=production (exit(1) fires first).
    return secret || crypto.createHash('sha256').update((process.env.JWT_SECRET || 'dev') + ':super-admin-dev-v1').digest('hex');
  })(),
  // hCaptcha — REQUIRED in production multi-tenant mode. If HCAPTCHA_SECRET is
  // missing in production, the server refuses to boot so signups cannot be
  // processed without bot protection (SEC-H94 / BH-0001 fail-closed fix).
  // In development/test, the secret is optional — bypasses are logged as warnings.
  hCaptchaSecret: process.env.HCAPTCHA_SECRET || '',
  hCaptchaEnabled: (() => {
    const enabled = !!process.env.HCAPTCHA_SECRET;
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const env = process.env.NODE_ENV || 'development';
    if (!enabled && isMultiTenant && env === 'production') {
      // SEC-H94: fail-closed — refuse to boot rather than allow unprotected signups.
      console.error('\n  FATAL: HCAPTCHA_SECRET must be set in production multi-tenant mode!');
      console.error('  Without it, the signup endpoint has no bot protection and any request');
      console.error('  (including automated probes with empty captcha_token) provisions a real tenant.');
      console.error('  Register at https://www.hcaptcha.com/ and add HCAPTCHA_SECRET to .env.\n');
      process.exit(1);
    }
    if (!enabled && env !== 'production') {
      console.warn('\n  [hCaptcha] WARNING: HCAPTCHA_SECRET is not set — captcha bypass active in dev mode.');
      console.warn('  [hCaptcha] Signups using "dev-captcha-token" will be accepted without verification.');
      console.warn('  [hCaptcha] This MUST NOT be deployed to production without HCAPTCHA_SECRET set.\n');
    }
    return enabled;
  })(),
  // SEC-H60: dedicated secret for HMAC-signed backup metadata sidecars.
  // Prevents an attacker with filesystem access to the backup store from
  // swapping tenant A's `.db.enc` into tenant B's slot — the sidecar's HMAC
  // is computed over `${slug}|${tenant_id}|${backup_version}|${written_at}`
  // with this secret, and restore rejects any file whose recomputed HMAC
  // doesn't match. If BACKUP_METADATA_KEY is unset we derive a process-local
  // fallback via HKDF over (JWT_SECRET || BACKUP_ENCRYPTION_KEY || '') so the
  // feature works out of the box in single-tenant / dev deployments.
  backupMetadataKey: (() => {
    const raw = (process.env.BACKUP_METADATA_KEY || '').trim();
    if (raw && raw.length >= 32) return raw;
    const env = process.env.NODE_ENV || 'development';
    if (env === 'production' && !raw) {
      console.warn('\n  [Backup] BACKUP_METADATA_KEY not set — deriving sidecar HMAC key from JWT_SECRET + BACKUP_ENCRYPTION_KEY via HKDF.');
      console.warn('  [Backup] This is acceptable but rotating either of those secrets will invalidate existing backup sidecars — restores would fall back to the unsigned path (requires --allow-unsigned).');
      console.warn('  [Backup] For independent key rotation, set BACKUP_METADATA_KEY to a dedicated 64-byte hex string.\n');
    }
    // HKDF derivation happens lazily in services/backup.ts (needs crypto
    // imports) — expose an explicit marker so downstream code knows to derive
    // instead of using a raw value. The empty string is the signal.
    return raw.length >= 32 ? raw : '';
  })(),
};
