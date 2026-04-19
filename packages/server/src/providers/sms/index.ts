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
import { config } from '../../config.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('sms:factory');

/**
 * Factory options controlling fallback behavior when credentials are missing.
 * In strict mode (used automatically in production) the factory throws instead
 * of silently dropping back to ConsoleProvider, which would otherwise look
 * like successful sends to the rest of the app.
 */
export interface CreateProviderOptions {
  strict?: boolean;
}

export class IncompleteSmsCredentialsError extends Error {
  constructor(public providerType: ProviderType, public missingFields: string[]) {
    super(
      `[SMS] Incomplete credentials for provider "${providerType}": missing ${missingFields.join(', ')}`
    );
    this.name = 'IncompleteSmsCredentialsError';
  }
}

// Re-export types for convenience
export * from './types.js';

// --- Module state ---
let activeProvider: SmsProvider = new ConsoleProvider();

// Multi-tenant: cache providers per tenant slug to avoid re-creating on every request
const tenantProviderCache = new Map<string, { provider: SmsProvider; loadedAt: number }>();
const TENANT_PROVIDER_TTL = 5 * 60 * 1000; // 5 minutes — re-read config if stale
// @audit-fixed: hard cap on the cache so a server with a leaky tenant slug source
// (or a brief test that creates many short-lived slugs) cannot grow this map
// without bound between cleanups. When we exceed the cap we evict the oldest
// entry on insert. The cleanup interval below still removes entries based on age.
const MAX_TENANT_PROVIDER_CACHE_ENTRIES = 1000;

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
  } catch (err) {
    // @audit-fixed: previously swallowed all errors silently, masking schema corruption,
    // missing store_config table, and decryption failures. Log the underlying cause so
    // operators can diagnose why a real provider is silently falling back to console.
    logger.warn('getDbConfig failed', { key, error: err instanceof Error ? err.message : String(err) });
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
  } catch (err) {
    // @audit-fixed: see getDbConfig — surface the failure so a corrupted store_config
    // doesn't appear as a "you forgot to enter creds" log line.
    logger.warn('getDbSmsConfig failed', { error: err instanceof Error ? err.message : String(err) });
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
  } catch (err) {
    // @audit-fixed: same swallow-and-pretend-empty bug as getDbSmsConfig.
    logger.warn('getDbVoiceConfig failed', { error: err instanceof Error ? err.message : String(err) });
    return {};
  }
}

// --- Factory ---

/**
 * Returns a list of missing credential field names for the given provider
 * based on its required fields. Returns an empty array if nothing is missing.
 */
function getMissingFields(type: ProviderType, dbCfg: Record<string, string>): string[] {
  const missing: string[] = [];
  const check = (key: string, label: string) => {
    if (!dbCfg[key]) missing.push(label);
  };
  switch (type) {
    case 'twilio':
      check('sms_twilio_account_sid', 'account_sid');
      check('sms_twilio_auth_token', 'auth_token');
      check('sms_twilio_from_number', 'from_number');
      break;
    case 'telnyx':
      check('sms_telnyx_api_key', 'api_key');
      check('sms_telnyx_from_number', 'from_number');
      break;
    case 'bandwidth':
      check('sms_bandwidth_account_id', 'account_id');
      check('sms_bandwidth_username', 'username');
      check('sms_bandwidth_password', 'password');
      check('sms_bandwidth_application_id', 'application_id');
      check('sms_bandwidth_from_number', 'from_number');
      break;
    case 'plivo':
      check('sms_plivo_auth_id', 'auth_id');
      check('sms_plivo_auth_token', 'auth_token');
      check('sms_plivo_from_number', 'from_number');
      break;
    case 'vonage':
      check('sms_vonage_api_key', 'api_key');
      check('sms_vonage_api_secret', 'api_secret');
      check('sms_vonage_from_number', 'from_number');
      break;
    default:
      break;
  }
  return missing;
}

/**
 * Handles the missing-credentials case. In strict mode (production, or when
 * explicitly requested) this throws an IncompleteSmsCredentialsError so the
 * caller can surface the failure clearly. In non-strict mode it emits an
 * explicit warn log AND returns a ConsoleProvider (which itself reports
 * simulated=true on every send).
 */
function handleMissingCreds(
  type: ProviderType,
  missing: string[],
  opts: CreateProviderOptions,
): SmsProvider {
  const strict = opts.strict ?? config.nodeEnv === 'production';
  logger.warn('SMS provider credentials incomplete', {
    providerType: type,
    missing,
    strict,
    fallbackTo: strict ? null : 'console',
  });
  if (strict) {
    throw new IncompleteSmsCredentialsError(type, missing);
  }
  return new ConsoleProvider();
}

function createProvider(
  type: ProviderType,
  dbCfg: Record<string, string>,
  opts: CreateProviderOptions = {},
): SmsProvider {
  switch (type) {
    case 'twilio': {
      const missing = getMissingFields('twilio', dbCfg);
      if (missing.length > 0) return handleMissingCreds('twilio', missing, opts);
      return new TwilioProvider({
        accountSid: dbCfg.sms_twilio_account_sid,
        authToken: dbCfg.sms_twilio_auth_token,
        fromNumber: dbCfg.sms_twilio_from_number,
      });
    }

    case 'telnyx': {
      const missing = getMissingFields('telnyx', dbCfg);
      if (missing.length > 0) return handleMissingCreds('telnyx', missing, opts);
      return new TelnyxProvider({
        apiKey: dbCfg.sms_telnyx_api_key,
        fromNumber: dbCfg.sms_telnyx_from_number,
        publicKey: dbCfg.sms_telnyx_public_key || '',
        connectionId: dbCfg.sms_telnyx_connection_id || '',
      });
    }

    case 'bandwidth': {
      const missing = getMissingFields('bandwidth', dbCfg);
      if (missing.length > 0) return handleMissingCreds('bandwidth', missing, opts);
      return new BandwidthProvider({
        accountId: dbCfg.sms_bandwidth_account_id,
        username: dbCfg.sms_bandwidth_username,
        password: dbCfg.sms_bandwidth_password,
        applicationId: dbCfg.sms_bandwidth_application_id,
        fromNumber: dbCfg.sms_bandwidth_from_number,
      });
    }

    case 'plivo': {
      const missing = getMissingFields('plivo', dbCfg);
      if (missing.length > 0) return handleMissingCreds('plivo', missing, opts);
      return new PlivoProvider({
        authId: dbCfg.sms_plivo_auth_id,
        authToken: dbCfg.sms_plivo_auth_token,
        fromNumber: dbCfg.sms_plivo_from_number,
      });
    }

    case 'vonage': {
      const missing = getMissingFields('vonage', dbCfg);
      if (missing.length > 0) return handleMissingCreds('vonage', missing, opts);
      return new VonageProvider({
        apiKey: dbCfg.sms_vonage_api_key,
        apiSecret: dbCfg.sms_vonage_api_secret,
        fromNumber: dbCfg.sms_vonage_from_number,
        applicationId: dbCfg.sms_vonage_application_id || '',
      });
    }

    case 'console':
    default:
      return new ConsoleProvider();
  }
}

// --- Public API ---

/**
 * Initialize the SMS provider from store_config (DB) or env vars. Called at startup.
 * Uses strict=true in production by default; catches and logs missing-credential
 * errors so a misconfigured provider can't crash boot in non-strict mode.
 */
export function initSmsProvider(db: any, opts: CreateProviderOptions = {}): void {
  const dbCfg = getDbSmsConfig(db);
  const providerType = (dbCfg.sms_provider_type || dbCfg.sms_provider || 'console') as ProviderType;
  try {
    activeProvider = createProvider(providerType, dbCfg, opts);
  } catch (err) {
    if (err instanceof IncompleteSmsCredentialsError) {
      // In strict mode the factory throws — re-raise so production boot fails
      // loudly instead of silently sending to the console provider.
      logger.error('SMS provider init failed in strict mode', {
        providerType,
        missing: err.missingFields,
      });
      throw err;
    }
    throw err;
  }
  logger.info('SMS provider initialized', { provider: activeProvider.name });
}

/** Hot-reload the SMS provider from store_config. No server restart needed. */
export function reloadSmsProvider(db: any, opts: CreateProviderOptions = {}): string {
  const dbCfg = getDbSmsConfig(db);
  const providerType = (dbCfg.sms_provider_type || dbCfg.sms_provider || 'console') as ProviderType;
  activeProvider = createProvider(providerType, dbCfg, opts);
  logger.info('SMS provider reloaded', { provider: activeProvider.name });
  return activeProvider.name;
}

/** Create a temporary provider instance for testing credentials (doesn't replace active). */
export function createTestProvider(type: ProviderType, credentials: Record<string, string>): SmsProvider {
  // Build a fake dbCfg from the credentials
  const dbCfg: Record<string, string> = {};
  for (const [key, value] of Object.entries(credentials)) {
    dbCfg[`sms_${type}_${key}`] = value;
  }
  // Test flow always wants the real error if creds are incomplete so the
  // Settings UI can surface it — use strict mode regardless of NODE_ENV.
  return createProvider(type, dbCfg, { strict: true });
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
 * True if the active provider is a real telephony provider capable of sending
 * SMS/MMS over the wire. False for ConsoleProvider (dev-only simulator).
 * Routes can use this to reject real-world sends when the backend would only
 * simulate them.
 */
export function isProviderRealOrSimulated(provider?: SmsProvider): { real: boolean; simulated: boolean } {
  const p = provider || activeProvider;
  const simulated = p.name === 'console';
  return { real: !simulated, simulated };
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

  // Load provider config from this tenant's DB. Per-tenant provider loads are
  // NON-strict: we don't want a single tenant's misconfiguration to throw and
  // crash unrelated tenant requests. The ConsoleProvider fallback will report
  // simulated=true on every send so callers still know the send wasn't real.
  const dbCfg = getDbSmsConfig(db);
  const providerType = (dbCfg.sms_provider_type || dbCfg.sms_provider || 'console') as ProviderType;
  const provider = createProvider(providerType, dbCfg, { strict: false });

  // @audit-fixed: enforce the hard cap. If we hit it, evict the oldest entry by
  // loadedAt instead of letting the map grow unbounded between cleanups.
  if (tenantProviderCache.size >= MAX_TENANT_PROVIDER_CACHE_ENTRIES && !tenantProviderCache.has(tenantSlug)) {
    let oldestSlug: string | null = null;
    let oldestAt = Number.POSITIVE_INFINITY;
    for (const [slug, cached] of tenantProviderCache) {
      if (cached.loadedAt < oldestAt) {
        oldestAt = cached.loadedAt;
        oldestSlug = slug;
      }
    }
    if (oldestSlug) tenantProviderCache.delete(oldestSlug);
  }

  tenantProviderCache.set(tenantSlug, { provider, loadedAt: Date.now() });
  return provider;
}

/**
 * PROD104: Synthesised SMS result returned when the outbound SMS kill-switch
 * fires. success:true keeps callers from crashing; suppressed:true lets
 * downstream audit records distinguish a suppressed send from a real one.
 *
 * The extra fields (suppressed, reason) are not part of SmsProviderResult;
 * we carry them via Object.assign so the base type is satisfied while
 * audit consumers can still do `(result as any).suppressed === true`.
 */
const SMS_KILL_SWITCH_RESULT: SmsProviderResult = Object.assign(
  { success: true, providerName: 'kill-switch', simulated: true } satisfies SmsProviderResult,
  { suppressed: true, reason: 'kill-switch' } as const,
);

/** Send an SMS or MMS. In multi-tenant mode, pass db and tenantSlug for correct provider. */
export function sendSms(to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
  // PROD104: Emergency kill-switch. When DISABLE_OUTBOUND_SMS=true, suppress
  // all outbound SMS/MMS immediately without a code deployment.
  if (config.disableOutboundSms) {
    logger.warn('[kill-switch] outbound SMS suppressed', { toLength: to.length });
    return Promise.resolve(SMS_KILL_SWITCH_RESULT);
  }
  return activeProvider.send(to, body, from, media);
}

/** Send SMS using the tenant-specific provider. */
export function sendSmsTenant(db: any, tenantSlug: string | null | undefined, to: string, body: string, from?: string, media?: MmsMedia[]): Promise<SmsProviderResult> {
  // PROD104: Emergency kill-switch. When DISABLE_OUTBOUND_SMS=true, suppress
  // all outbound SMS/MMS immediately without a code deployment.
  if (config.disableOutboundSms) {
    logger.warn('[kill-switch] outbound SMS suppressed', { tenantSlug: tenantSlug ?? null, toLength: to.length });
    return Promise.resolve(SMS_KILL_SWITCH_RESULT);
  }
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
