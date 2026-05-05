import crypto from 'crypto';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// ─── HKDF key derivation helper ─────────────────────────────────────────────
// Used to derive scoped keys from JWT_SECRET when the dedicated env vars are
// not set, so existing deployments keep working without env-var churn.
// Salt is a fixed domain separator; info provides per-key isolation.
const HKDF_SALT = Buffer.from('bizarre-crm-v1', 'utf8');
function hkdfDeriveKey(ikm: string, info: string): string {
  const derived = crypto.hkdfSync('sha256', Buffer.from(ikm, 'utf8'), HKDF_SALT, Buffer.from(info, 'utf8'), 32);
  return Buffer.from(derived).toString('hex');
}

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

  // ─── SEC-H103: Dedicated per-purpose key slots ───────────────────────────
  //
  // Each of the five fields below reads a dedicated env var first. When the
  // dedicated var is absent (dev / first-time deploys), the value is derived
  // from JWT_SECRET via HKDF-SHA256 with a scoped info label so every key is
  // cryptographically independent even when all share the same root material.
  //
  // Backward-compatibility contract:
  //   • If ACCESS_JWT_SECRET / REFRESH_JWT_SECRET are not set, the derived
  //     values are used for SIGNING new tokens. Old tokens signed with the
  //     raw JWT_SECRET will still verify during the transition window because
  //     verifyJwtWithRotation() additionally tries config.jwtSecret as a
  //     legacy fallback (see utils/jwtSecrets.ts). Remove that fallback path
  //     after all sessions have expired (max 30 days from deploy).
  //   • CONFIG_ENCRYPTION_KEY / BACKUP_ENCRYPTION_KEY are PRODUCTION-FATAL:
  //     they must be set explicitly in production because their data has a
  //     multi-year blast radius — these keys must not be rotation-coupled to
  //     JWT_SECRET. DB_ENCRYPTION_KEY is wired-up for future use only.

  // Signs / verifies short-lived access tokens (1 h).
  // Falls back to HKDF(JWT_SECRET, info='access') in dev.
  accessJwtSecret: (() => {
    const dedicated = (process.env.ACCESS_JWT_SECRET || '').trim();
    const env = process.env.NODE_ENV || 'development';
    if (dedicated && dedicated.length >= 32) return dedicated;
    if (dedicated && dedicated.length > 0 && dedicated.length < 32) {
      console.warn('\n  [SEC-H103] ACCESS_JWT_SECRET is too short (min 32 chars) — falling back to HKDF derivation.\n');
    }
    // In production with a dedicated var missing: warn and derive (do NOT
    // exit — operators can migrate gradually. The production-fatal gate is
    // reserved for CONFIG_ENCRYPTION_KEY + BACKUP_ENCRYPTION_KEY only.)
    if (env === 'production' && !dedicated) {
      console.warn('\n  [SEC-H103] ACCESS_JWT_SECRET not set in production — deriving from JWT_SECRET via HKDF.');
      console.warn('  [SEC-H103] Set ACCESS_JWT_SECRET to a dedicated 64-byte hex value for independent rotation.\n');
    }
    const base = process.env.JWT_SECRET || 'dev-secret-change-me';
    return hkdfDeriveKey(base, 'access');
  })(),

  // Signs / verifies long-lived refresh tokens (30 d / 90 d trusted).
  // Falls back to HKDF(JWT_SECRET, info='refresh') in dev.
  refreshJwtSecret: (() => {
    const dedicated = (process.env.REFRESH_JWT_SECRET || '').trim();
    const env = process.env.NODE_ENV || 'development';
    if (dedicated && dedicated.length >= 32) return dedicated;
    if (dedicated && dedicated.length > 0 && dedicated.length < 32) {
      console.warn('\n  [SEC-H103] REFRESH_JWT_SECRET is too short (min 32 chars) — falling back to HKDF derivation.\n');
    }
    if (env === 'production' && !dedicated) {
      console.warn('\n  [SEC-H103] REFRESH_JWT_SECRET not set in production — deriving from JWT_SECRET via HKDF.');
      console.warn('  [SEC-H103] Set REFRESH_JWT_SECRET to a dedicated 64-byte hex value for independent rotation.\n');
    }
    const base = process.env.JWT_SECRET || 'dev-secret-change-me';
    return hkdfDeriveKey(base, 'refresh');
  })(),

  // AES-256-GCM key for store_config encrypted values (configEncryption.ts).
  // PRODUCTION-FATAL if not set — encrypted config (BlockChyp keys, SMTP
  // passwords, etc.) has a multi-year blast radius.
  configEncryptionKey: (() => {
    const dedicated = (process.env.CONFIG_ENCRYPTION_KEY || '').trim();
    const env = process.env.NODE_ENV || 'development';
    if (dedicated && dedicated.length >= 32) return dedicated;
    if (env === 'production') {
      if (!dedicated) {
        console.error('\n  FATAL: CONFIG_ENCRYPTION_KEY must be set in production!');
        console.error('  It encrypts API credentials in the database (BlockChyp, SMTP, SMS).');
        console.error('  Generate with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"\n');
        process.exit(1);
      }
      if (dedicated.length < 32) {
        console.error('\n  FATAL: CONFIG_ENCRYPTION_KEY is too short (min 32 chars). Use a 32-byte hex string.\n');
        process.exit(1);
      }
    }
    if (dedicated && dedicated.length < 32) {
      console.warn('\n  [SEC-H103] CONFIG_ENCRYPTION_KEY is too short — falling back to HKDF derivation.\n');
    }
    const base = process.env.JWT_SECRET || 'dev-secret-change-me';
    return hkdfDeriveKey(base, 'config-enc');
  })(),

  // AES key passphrase for encrypted database backups (backup.ts).
  // PRODUCTION-FATAL if not set — backup files can live on disk for years.
  backupEncryptionKey: (() => {
    const dedicated = (process.env.BACKUP_ENCRYPTION_KEY || '').trim();
    const env = process.env.NODE_ENV || 'development';
    if (dedicated && dedicated.length >= 16) return dedicated;
    if (env === 'production') {
      if (!dedicated) {
        console.error('\n  FATAL: BACKUP_ENCRYPTION_KEY must be set in production!');
        console.error('  It encrypts database backups that may persist on disk for years.');
        console.error('  Generate with: node -e "console.log(require(\'crypto\').randomBytes(64).toString(\'hex\'))"\n');
        process.exit(1);
      }
      if (dedicated.length < 16) {
        console.error('\n  FATAL: BACKUP_ENCRYPTION_KEY is too short (min 16 chars). Use a 64-byte hex string.\n');
        process.exit(1);
      }
    }
    if (dedicated && dedicated.length < 16) {
      console.warn('\n  [SEC-H103] BACKUP_ENCRYPTION_KEY is too short — falling back to HKDF derivation.\n');
    }
    if (!dedicated && env !== 'production') {
      console.warn('\n  [SEC-H103] BACKUP_ENCRYPTION_KEY not set — deriving from JWT_SECRET via HKDF (dev only).');
      console.warn('  [SEC-H103] Set BACKUP_ENCRYPTION_KEY in .env to a dedicated 64-byte hex string.\n');
    }
    const base = process.env.JWT_SECRET || 'dev-secret-change-me';
    return hkdfDeriveKey(base, 'backup-enc');
  })(),

  // Per-tenant DB encryption key — reserved for future SQLCipher or similar.
  // Not wired to any consumer yet; exposed here so the env contract is defined
  // before implementation lands (DB_ENCRYPTION_KEY in .env.example).
  dbEncryptionKey: (() => {
    const dedicated = (process.env.DB_ENCRYPTION_KEY || '').trim();
    if (dedicated && dedicated.length >= 32) return dedicated;
    const base = process.env.JWT_SECRET || 'dev-secret-change-me';
    return hkdfDeriveKey(base, 'db-enc');
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
  /** Dedicated directory for cron-generated data-export JSON files. */
  exportsPath: path.resolve(__dirname, '../data/exports'),
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
  // hCaptcha — default-REQUIRED in production multi-tenant mode. If
  // HCAPTCHA_SECRET is missing in production, the server normally refuses to
  // boot so signups cannot be processed without bot protection (SEC-H94 /
  // BH-0001 fail-closed fix). Operators who front the server with an
  // upstream bot filter (Cloudflare Turnstile, WAF, etc.) can opt out by
  // setting SIGNUP_CAPTCHA_REQUIRED=false in .env — the server then boots,
  // and the signup route accepts requests without captcha verification while
  // emitting loud warnings so the decision is auditable.
  // In development/test, the secret is optional — bypasses are logged as warnings.
  hCaptchaSecret: process.env.HCAPTCHA_SECRET || '',
  signupCaptchaRequired: (process.env.SIGNUP_CAPTCHA_REQUIRED ?? 'true').trim().toLowerCase() !== 'false',
  hCaptchaEnabled: (() => {
    const enabled = !!process.env.HCAPTCHA_SECRET;
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const env = process.env.NODE_ENV || 'development';
    const required = (process.env.SIGNUP_CAPTCHA_REQUIRED ?? 'true').trim().toLowerCase() !== 'false';
    if (!enabled && isMultiTenant && env === 'production' && required) {
      // SEC-H94: fail-closed — refuse to boot rather than allow unprotected signups.
      console.error('\n  FATAL: HCAPTCHA_SECRET must be set in production multi-tenant mode!');
      console.error('  Without it, the signup endpoint has no bot protection and any request');
      console.error('  (including automated probes with empty captcha_token) provisions a real tenant.');
      console.error('  Register at https://www.hcaptcha.com/ and add HCAPTCHA_SECRET to .env.');
      console.error('  Or set SIGNUP_CAPTCHA_REQUIRED=false if an upstream bot filter (Cloudflare,');
      console.error('  WAF) already protects the signup endpoint.\n');
      process.exit(1);
    }
    if (!enabled && isMultiTenant && env === 'production' && !required) {
      console.warn('\n  [hCaptcha] SIGNUP_CAPTCHA_REQUIRED=false — booting without HCAPTCHA_SECRET.');
      console.warn('  [hCaptcha] The signup endpoint will accept requests WITHOUT captcha verification.');
      console.warn('  [hCaptcha] Operator is responsible for upstream bot protection (Cloudflare Turnstile, WAF, etc.).\n');
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
