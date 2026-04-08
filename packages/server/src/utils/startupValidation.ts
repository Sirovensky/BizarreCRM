/**
 * Startup validation: checks required env vars, data directories, and warns
 * about missing optional configurations. Called once at server boot.
 * Does NOT crash the server for missing optional configs — just logs warnings.
 */

import fs from 'fs';
import path from 'path';
import { config } from '../config.js';

const INSECURE_SECRETS = ['dev-secret-change-me', 'change-me-to-a-random-string', 'change-me', ''];

export function validateStartupEnvironment(): void {
  const warnings: string[] = [];
  const errors: string[] = [];

  // ─── Required checks ───────────────────────────────────────────────

  // JWT_SECRET must not be the default in production
  if (config.nodeEnv === 'production') {
    if (INSECURE_SECRETS.includes(process.env.JWT_SECRET || '')) {
      errors.push('JWT_SECRET is using an insecure default value. Set a strong random secret for production.');
    }
    if (INSECURE_SECRETS.includes(process.env.JWT_REFRESH_SECRET || '')) {
      errors.push('JWT_REFRESH_SECRET is using an insecure default value. Set a strong random secret for production.');
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
}
