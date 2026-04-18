/**
 * Startup validation: checks required env vars, data directories, and warns
 * about missing optional configurations. Called once at server boot.
 * Does NOT crash the server for missing optional configs — just logs warnings.
 */

import fs from 'fs';
import path from 'path';
import { config } from '../config.js';
import { warnIfPreviousSecretsSet } from './jwtSecrets.js';

const INSECURE_SECRETS = ['dev-secret-change-me', 'change-me-to-a-random-string', 'change-me', ''];
// Minimum acceptable byte-length for JWT secrets (32 bytes = 64 hex chars or 43 base64 chars)
const JWT_SECRET_MIN_LENGTH = 32;

export function validateStartupEnvironment(): void {
  const warnings: string[] = [];
  const errors: string[] = [];

  // ─── Required checks ───────────────────────────────────────────────

  // JWT_SECRET must not be the default in production, and must meet minimum length.
  if (config.nodeEnv === 'production') {
    const jwtSecret = process.env.JWT_SECRET || '';
    const jwtRefresh = process.env.JWT_REFRESH_SECRET || '';
    if (INSECURE_SECRETS.includes(jwtSecret)) {
      errors.push('JWT_SECRET is using an insecure default value. Set a strong random secret for production.');
    } else if (jwtSecret.length < JWT_SECRET_MIN_LENGTH) {
      errors.push(`JWT_SECRET is too short (${jwtSecret.length} chars). Must be at least ${JWT_SECRET_MIN_LENGTH} characters.`);
    }
    if (INSECURE_SECRETS.includes(jwtRefresh)) {
      errors.push('JWT_REFRESH_SECRET is using an insecure default value. Set a strong random secret for production.');
    } else if (jwtRefresh.length < JWT_SECRET_MIN_LENGTH) {
      errors.push(`JWT_REFRESH_SECRET is too short (${jwtRefresh.length} chars). Must be at least ${JWT_SECRET_MIN_LENGTH} characters.`);
    }

    // BACKUP_ENCRYPTION_KEY: strongly recommended in production to decouple backup
    // encryption from JWT key rotation. Warn (not error) since backup.ts falls back
    // to JWT_SECRET with its own warning.
    if (!process.env.BACKUP_ENCRYPTION_KEY) {
      warnings.push('BACKUP_ENCRYPTION_KEY is not set. Encrypted backups will fall back to JWT_SECRET. Set a dedicated key to decouple backup encryption from auth key rotation.');
    }

    // SUPER_ADMIN_SECRET: required when running in multi-tenant mode.
    if (process.env.MULTI_TENANT === 'true') {
      const superAdminSecret = process.env.SUPER_ADMIN_SECRET || '';
      if (!superAdminSecret || INSECURE_SECRETS.includes(superAdminSecret) || superAdminSecret === 'change-me-in-production') {
        errors.push('SUPER_ADMIN_SECRET is missing or using an insecure default. Set a strong random secret when MULTI_TENANT=true.');
      } else if (superAdminSecret.length < JWT_SECRET_MIN_LENGTH) {
        errors.push(`SUPER_ADMIN_SECRET is too short (${superAdminSecret.length} chars). Must be at least ${JWT_SECRET_MIN_LENGTH} characters.`);
      }
    }
  } else {
    // Development — warn but don't crash
    if (!process.env.JWT_SECRET || INSECURE_SECRETS.includes(process.env.JWT_SECRET)) {
      warnings.push('JWT_SECRET is using the default dev value. Set a unique secret before deploying.');
    }
  }

  // PORT validation
  if (!process.env.PORT) {
    warnings.push(`PORT not set — defaulting to ${config.port}.`);
  }

  // Data directory must exist (or be creatable)
  const dataDir = path.resolve(path.dirname(config.dbPath));
  if (!fs.existsSync(dataDir)) {
    try {
      fs.mkdirSync(dataDir, { recursive: true });
      warnings.push(`Data directory created: ${dataDir}`);
    } catch {
      errors.push(`Data directory does not exist and cannot be created: ${dataDir}`);
    }
  }

  // Uploads directory
  if (!fs.existsSync(config.uploadsPath)) {
    try {
      fs.mkdirSync(config.uploadsPath, { recursive: true });
      warnings.push(`Uploads directory created: ${config.uploadsPath}`);
    } catch {
      errors.push(`Uploads directory does not exist and cannot be created: ${config.uploadsPath}`);
    }
  }

  // ─── Optional config warnings (feature flags) ──────────────────────

  // These check the DB-stored config, but we can at least check env-level hints
  if (!process.env.SMTP_HOST && !process.env.SMTP_USER) {
    warnings.push('SMTP not configured via env vars. Email notifications will use DB-stored settings (if any).');
  }

  if (!process.env.SMS_PROVIDER && !process.env.VONAGE_API_KEY && !process.env.TWILIO_ACCOUNT_SID) {
    warnings.push('SMS provider not configured via env vars. SMS features will use DB-stored settings (if any).');
  }

  // ─── Output ────────────────────────────────────────────────────────

  if (errors.length > 0) {
    console.error('');
    console.error('  ╔══════════════════════════════════════════════════╗');
    console.error('  ║  STARTUP VALIDATION ERRORS                       ║');
    console.error('  ╚══════════════════════════════════════════════════╝');
    for (const err of errors) {
      console.error(`  [ERROR] ${err}`);
    }
    if (config.nodeEnv === 'production') {
      console.error('');
      console.error('  Fix the above errors before running in production.');
      process.exit(1);
    }
  }

  if (warnings.length > 0) {
    console.warn('');
    for (const warn of warnings) {
      console.warn(`  [WARN] ${warn}`);
    }
    console.warn('');
  }

  // SA1-1: emit rotation-window reminder if JWT_SECRET_PREVIOUS or
  // JWT_REFRESH_SECRET_PREVIOUS is set so operators are nudged to remove
  // them once the access-token TTL has elapsed.
  warnIfPreviousSecretsSet();
}
