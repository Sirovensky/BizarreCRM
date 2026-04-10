import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../../.env') });
// Also try loading from root
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

export const config = {
  port: parseInt(process.env.PORT || '443'),
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
  // Stripe billing — required in production multi-tenant mode for SaaS subscriptions.
  // In dev or single-tenant mode, missing keys only cause runtime errors when /billing endpoints are hit.
  stripeSecretKey: (() => {
    const key = process.env.STRIPE_SECRET_KEY;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    if (!key && env === 'production' && isMultiTenant) {
      console.error('\n  FATAL: STRIPE_SECRET_KEY must be set in production multi-tenant mode for billing!\n');
      process.exit(1);
    }
    return key || '';
  })(),
  stripeWebhookSecret: (() => {
    const key = process.env.STRIPE_WEBHOOK_SECRET;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    if (!key && env === 'production' && isMultiTenant) {
      console.error('\n  FATAL: STRIPE_WEBHOOK_SECRET must be set in production multi-tenant mode for billing!\n');
      process.exit(1);
    }
    return key || '';
  })(),
  stripeProPriceId: (() => {
    const id = process.env.STRIPE_PRO_PRICE_ID;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    if (!id && env === 'production' && isMultiTenant) {
      console.error('\n  FATAL: STRIPE_PRO_PRICE_ID must be set in production multi-tenant mode for billing!\n');
      process.exit(1);
    }
    return id || '';
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
  baseDomain: process.env.BASE_DOMAIN || 'localhost',
  // Cloudflare DNS auto-provisioning — required in production multi-tenant mode
  // with a real base domain. Skipped (no-op) in dev, single-tenant, or localhost mode.
  cloudflareApiToken: (() => {
    const token = process.env.CLOUDFLARE_API_TOKEN;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const baseDomain = process.env.BASE_DOMAIN || 'localhost';
    const needsCloudflare = isMultiTenant && baseDomain !== 'localhost' && !baseDomain.endsWith('.localhost');
    if (!token && env === 'production' && needsCloudflare) {
      console.error('\n  FATAL: CLOUDFLARE_API_TOKEN must be set in production multi-tenant mode with a real BASE_DOMAIN!\n');
      console.error('  Create a scoped token at: Cloudflare dashboard > My Profile > API Tokens > Create Token > Custom token');
      console.error('  Permissions: Zone.DNS:Edit. Zone Resources: Include > Specific zone > your domain.\n');
      process.exit(1);
    }
    if (!token && needsCloudflare) {
      console.warn('\n  WARNING: CLOUDFLARE_API_TOKEN not set. Tenant DNS auto-provisioning disabled.\n');
    }
    return token || '';
  })(),
  cloudflareZoneId: (() => {
    const zoneId = process.env.CLOUDFLARE_ZONE_ID;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const baseDomain = process.env.BASE_DOMAIN || 'localhost';
    const needsCloudflare = isMultiTenant && baseDomain !== 'localhost' && !baseDomain.endsWith('.localhost');
    if (!zoneId && env === 'production' && needsCloudflare) {
      console.error('\n  FATAL: CLOUDFLARE_ZONE_ID must be set in production multi-tenant mode with a real BASE_DOMAIN!\n');
      console.error('  Find it at: Cloudflare dashboard > your domain > API section (right sidebar)\n');
      process.exit(1);
    }
    return zoneId || '';
  })(),
  serverPublicIp: (() => {
    const ip = process.env.SERVER_PUBLIC_IP;
    const env = process.env.NODE_ENV || 'development';
    const isMultiTenant = process.env.MULTI_TENANT === 'true';
    const baseDomain = process.env.BASE_DOMAIN || 'localhost';
    const needsCloudflare = isMultiTenant && baseDomain !== 'localhost' && !baseDomain.endsWith('.localhost');
    if (!ip && env === 'production' && needsCloudflare) {
      console.error('\n  FATAL: SERVER_PUBLIC_IP must be set in production multi-tenant mode with a real BASE_DOMAIN!\n');
      console.error('  This is the public IP the tenant DNS records will point to.\n');
      process.exit(1);
    }
    return ip || '';
  })(),
  cloudflareEnabled: !!(process.env.CLOUDFLARE_API_TOKEN && process.env.CLOUDFLARE_ZONE_ID && process.env.SERVER_PUBLIC_IP),
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
};
