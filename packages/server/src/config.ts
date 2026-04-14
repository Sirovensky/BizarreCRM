import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env deterministically for both src/ (tsx) and dist/ (production PM2)
// execution. The repo-root .env is the source of truth and is loaded last so it
// wins over stale PM2/inherited values and over a package-local fallback.
const keepProductionNodeEnv = process.env.NODE_ENV === 'production';
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
if (keepProductionNodeEnv) {
  process.env.NODE_ENV = 'production';
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
      console.warn('\n  [Cloudflare] Auto-DNS disabled: one or more of CLOUDFLARE_API_TOKEN / CLOUDFLARE_ZONE_ID / SERVER_PUBLIC_IP is not set.');
      console.warn('  [Cloudflare] Tenant subdomains must be managed manually (e.g. via wildcard DNS).');
      console.warn('  [Cloudflare] To enable: add all three to .env. See .env.example for details.\n');
    }
    return enabled;
  })(),
  superAdminSecret: (() => {
    const secret = process.env.SUPER_ADMIN_SECRET;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    // SEC-H4: In multi-tenant mode, ALWAYS require SUPER_ADMIN_SECRET regardless of NODE_ENV.
    // The default fallback is only acceptable in single-tenant mode (local repair shop use).
    if (!secret && isMultiTenant) {
      if (env === 'production') {
        console.error('\n  FATAL: SUPER_ADMIN_SECRET environment variable is required in production multi-tenant mode!\n');
        process.exit(1);
      } else {
        console.error('\n  FATAL: SUPER_ADMIN_SECRET environment variable is required in multi-tenant mode (even in development).\n');
        console.error('  Generate one with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"\n');
        process.exit(1);
      }
    }
    if (!secret) {
      console.warn('\n  WARNING: Using default super-admin secret (single-tenant mode). Set SUPER_ADMIN_SECRET env var for production.\n');
    }
    return secret || 'super-admin-dev-secret';
  })(),
  // hCaptcha — OPTIONAL feature. If HCAPTCHA_SECRET is missing, signup verification
  // falls open (allowing signups) but creates a security alert for the super-admin.
  hCaptchaSecret: process.env.HCAPTCHA_SECRET || '',
  hCaptchaEnabled: (() => {
    const enabled = !!process.env.HCAPTCHA_SECRET;
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const env = process.env.NODE_ENV || 'development';
    if (!enabled && isMultiTenant && env === 'production') {
      console.warn('\n  [hCaptcha] Signup verification disabled: HCAPTCHA_SECRET is not set.');
      console.warn('  [hCaptcha] Online signups will proceed WITHOUT CAPTCHA verification.');
      console.warn('  [hCaptcha] To enable: add HCAPTCHA_SECRET to .env. See .env.example for details.\n');
    }
    return enabled;
  })(),
};
