import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../../.env') });
// Also try loading from root
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

export const config = {
  port: parseInt(process.env.PORT || '3020'),
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
  baseDomain: process.env.BASE_DOMAIN || 'bizarrecrm.com',
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
