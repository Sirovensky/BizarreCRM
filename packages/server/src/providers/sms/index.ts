/**
 * SMS/MMS + Voice Provider Factory
 *
 * Reads credentials from store_config (DB) first, falls back to env vars.
 * Supports hot-reload via reloadSmsProvider() — no server restart needed.
 */

import { SmsProvider, SmsProviderResult, MmsMedia, ProviderType, PROVIDER_REGISTRY } from './types.js';
import { ConsoleProvider } from './console.js';
import { TwilioProvider } from './twilio.js';
import { TelnyxProvider } from './telnyx.js';
import { BandwidthProvider } from './bandwidth.js';
import { PlivoProvider } from './plivo.js';
import { VonageProvider } from './vonage.js';
import { ENCRYPTED_CONFIG_KEYS, decryptConfigValue } from '../../utils/configEncryption.js';

// Re-export types for convenience
export * from './types.js';

// --- Module state ---
let activeProvider: SmsProvider = new ConsoleProvider();

// Multi-tenant: cache providers per tenant slug to avoid re-creating on every request
const tenantProviderCache = new Map<string, { provider: SmsProvider; loadedAt: number }>();
const TENANT_PROVIDER_TTL = 5 * 60 * 1000; // 5 minutes — re-read config if stale

// Periodic cleanup of stale provider cache entries
setInterval(() => {
  const now = Date.now();
  for (const [slug, cached] of tenantProviderCache) {
    if (now - cached.loadedAt > TENANT_PROVIDER_TTL * 2) tenantProviderCache.delete(slug);
  }
}, 10 * 60 * 1000).unref();

// --- Helpers ---

type AnyRow = Record<string, any>;

/** Read a config value from store_config table (auto-decrypts sensitive keys). */
function getDbConfig(db: any, key: string): string {
  try {
    const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as AnyRow | undefined;
    if (!row?.value) return '';
    return ENCRYPTED_CONFIG_KEYS.has(key) ? decryptConfigValue(row.value) : row.value;
  } catch {
    return '';
  }
}

/** Read all sms_ config keys from store_config (auto-decrypts sensitive keys). */
function getDbSmsConfig(db: any): Record<string, string> {
  try {
    const rows = db.prepare("SELECT key, value FROM store_config WHERE key LIKE 'sms_%'").all() as AnyRow[];
    const cfg: Record<string, string> = {};
    for (const r of rows) {
      cfg[r.key] = ENCRYPTED_CONFIG_KEYS.has(r.key) ? decryptConfigValue(r.value) : r.value;
    }
    return cfg;
  } catch {
    return {};
  }
}

/** Read all voice_ config keys from store_config. */
function getDbVoiceConfig(db: any): Record<string, string> {
  try {
    const rows = db.prepare("SELECT key, value FROM store_config WHERE key LIKE 'voice_%'").all() as AnyRow[];
    const cfg: Record<string, string> = {};
    for (const r of rows) cfg[r.key] = r.value;
    return cfg;
  } catch {
    return {};
  }
}

// --- Factory ---

function createProvider(type: ProviderType, dbCfg: Record<string, string>): SmsProvider {
  switch (type) {
    case 'twilio': {
      const accountSid = dbCfg.sms_twilio_account_sid || '';
      const authToken = dbCfg.sms_twilio_auth_token || '';
      const fromNumber = dbCfg.sms_twilio_from_number || '';
      if (!accountSid || !authToken || !fromNumber) {
        console.warn('[SMS] Twilio credentials incomplete, falling back to console');
        return new ConsoleProvider();
      }
      return new TwilioProvider({ accountSid, authToken, fromNumber });
    }

    case 'telnyx': {
      const apiKey = dbCfg.sms_telnyx_api_key || '';
      const fromNumber = dbCfg.sms_telnyx_from_number || '';
      const publicKey = dbCfg.sms_telnyx_public_key || '';
      const connectionId = dbCfg.sms_telnyx_connection_id || '';
      if (!apiKey || !fromNumber) {
        console.warn('[SMS] Telnyx credentials incomplete, falling back to console');
        return new ConsoleProvider();
      }
      return new TelnyxProvider({ apiKey, fromNumber, publicKey, connectionId });
    }

    case 'bandwidth': {
      const accountId = dbCfg.sms_bandwidth_account_id || '';
      const username = dbCfg.sms_bandwidth_username || '';
      const password = dbCfg.sms_bandwidth_password || '';
      const applicationId = dbCfg.sms_bandwidth_application_id || '';
      const fromNumber = dbCfg.sms_bandwidth_from_number || '';
      if (!accountId || !username || !password || !applicationId || !fromNumber) {
        console.warn('[SMS] Bandwidth credentials incomplete, falling back to console');
        return new ConsoleProvider();
      }
      return new BandwidthProvider({ accountId, username, password, applicationId, fromNumber });
    }

    case 'plivo': {
      const authId = dbCfg.sms_plivo_auth_id || '';
      const authToken = dbCfg.sms_plivo_auth_token || '';
      const fromNumber = dbCfg.sms_plivo_from_number || '';
      if (!authId || !authToken || !fromNumber) {
        console.warn('[SMS] Plivo credentials incomplete, falling back to console');
        return new ConsoleProvider();
      }
      return new PlivoProvider({ authId, authToken, fromNumber });
    }

    case 'vonage': {
      const apiKey = dbCfg.sms_vonage_api_key || '';
      const apiSecret = dbCfg.sms_vonage_api_secret || '';
      const fromNumber = dbCfg.sms_vonage_from_number || '';
      const applicationId = dbCfg.sms_vonage_application_id || '';
      if (!apiKey || !apiSecret || !fromNumber) {
        console.warn('[SMS] Vonage credentials incomplete, falling back to console');
        return new ConsoleProvider();
      }
      return new VonageProvider({ apiKey, apiSecret, fromNumber, applicationId });
    }

    case 'console':
    default:
      return new ConsoleProvider();
  }
}

// --- Public API ---

/** Initialize the SMS provider from store_config (DB) or env vars. Called at startup. */
export function initSmsProvider(db: any): void {
  const dbCfg = getDbSmsConfig(db);
  const providerType = (dbCfg.sms_provider_type || dbCfg.sms_provider || 'console') as ProviderType;
  activeProvider = createProvider(providerType, dbCfg);
  console.log(`[SMS] Provider initialized: ${activeProvider.name}`);
}

/** Hot-reload the SMS provider from store_config. No server restart needed. */
export function reloadSmsProvider(db: any): string {
  const dbCfg = getDbSmsConfig(db);
  const providerType = (dbCfg.sms_provider_type || dbCfg.sms_provider || 'console') as ProviderType;
  activeProvider = createProvider(providerType, dbCfg);
  console.log(`[SMS] Provider reloaded: ${activeProvider.name}`);
  return activeProvider.name;
}

/** Create a temporary provider instance for testing credentials (doesn't replace active). */
export function createTestProvider(type: ProviderType, credentials: Record<string, string>): SmsProvider {
  // Build a fake dbCfg from the credentials
  const dbCfg: Record<string, string> = {};
  for (const [key, value] of Object.entries(credentials)) {
    dbCfg[`sms_${type}_${key}`] = value;
  }
  return createProvider(type, dbCfg);
}

/** Get the active provider. */
export function getSmsProvider(): SmsProvider {
  return activeProvider;
}

/** Set a specific provider instance (for testing). */
export function setSmsProvider(provider: SmsProvider): void {
  activeProvider = provider;
}

/**
 * Get the SMS provider for a specific tenant database.
 * In multi-tenant mode, each tenant may have different provider credentials.
 * Providers are cached per tenant slug for 5 minutes.
 */
export function getProviderForDb(db: any, tenantSlug?: string | null): SmsProvider {
  if (!tenantSlug) return activeProvider; // Single-tenant: use global

  const cached = tenantProviderCache.get(tenantSlug);
  if (cached && Date.now() - cached.loadedAt < TENANT_PROVIDER_TTL) {
    return cached.provider;
  }

  // Load provider config from this tenant's DB
  const dbCfg = getDbSmsConfig(db);
  const providerType = (dbCfg.sms_provider_type || dbCfg.sms_provider || 'console') as ProviderType;
  const provider = createProvider(providerType, dbCfg);
  tenantProviderCache.set(tenantSlug, { provider, loadedAt: Date.now() });
  return provider;
}

/** Send an SMS or MMS. In multi-tenant mode, pass db and tenantSlug for correct provider. */
export function sendSms(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
  return activeProvider.send(to, body, from, media);
}

/** Send SMS using the tenant-specific provider. */
export function sendSmsTenant(db: any, tenantSlug: string | null | undefined, to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
  const provider = getProviderForDb(db, tenantSlug);
  return provider.send(to, body, from, media);
}

/** Get voice config from DB. */
export function getVoiceConfig(db: any): Record<string, string> {
  return getDbVoiceConfig(db);
}

/** Get provider registry (for Settings UI). */
export function getProviderRegistry() {
  return PROVIDER_REGISTRY;
}
