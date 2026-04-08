import crypto from 'crypto';
import { config } from '../config.js';

/**
 * AES-256-GCM encryption/decryption for sensitive config values stored in store_config.
 * Uses a key derived from JWT_SECRET with a dedicated purpose string, so a compromised
 * database file alone cannot reveal API credentials.
 *
 * Format: enc:v{version}:{iv}:{authTag}:{ciphertext}  (all hex-encoded)
 * Unencrypted values (legacy) are returned as-is on decrypt.
 */

const ENCRYPTION_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':config-secrets:v1').digest(),
};
const CURRENT_KEY_VERSION = 1;

/** Keys whose values should be encrypted at rest in store_config */
export const ENCRYPTED_CONFIG_KEYS = new Set([
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'smtp_pass',
  'rd_api_key',
  'tcx_password',
]);

export function encryptConfigValue(plaintext: string): string {
  if (!plaintext) return plaintext;
  const key = ENCRYPTION_KEYS[CURRENT_KEY_VERSION];
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `enc:v${CURRENT_KEY_VERSION}:${iv.toString('hex')}:${tag.toString('hex')}:${encrypted.toString('hex')}`;
}

export function decryptConfigValue(ciphertext: string): string {
  if (!ciphertext) return ciphertext;
  // Unencrypted legacy value — return as-is
  if (!ciphertext.startsWith('enc:v')) return ciphertext;

  const parts = ciphertext.split(':');
  // Format: enc:v{n}:{iv}:{tag}:{data}
  if (parts.length !== 5) return ciphertext;

  const version = parseInt(parts[1].slice(1), 10);
  const key = ENCRYPTION_KEYS[version];
  if (!key) {
    console.error(`[ConfigEncryption] Unknown key version: ${version}`);
    return ciphertext;
  }

  try {
    const iv = Buffer.from(parts[2], 'hex');
    const tag = Buffer.from(parts[3], 'hex');
    const data = Buffer.from(parts[4], 'hex');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    return decipher.update(data) + decipher.final('utf8');
  } catch (err) {
    console.error('[ConfigEncryption] Decryption failed:', (err as Error).message);
    return ciphertext; // Return raw value as fallback (likely unencrypted legacy)
  }
}

/**
 * Helper: read a config value from store_config, auto-decrypting if the key is sensitive.
 */
export function getConfigValue(db: any, key: string): string | null {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value: string } | undefined;
  if (!row) return null;
  if (ENCRYPTED_CONFIG_KEYS.has(key)) return decryptConfigValue(row.value);
  return row.value;
}

/**
 * Helper: write a config value to store_config, auto-encrypting if the key is sensitive.
 */
export function setConfigValue(db: any, key: string, value: string): void {
  const storedValue = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(value) : value;
  db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)').run(key, storedValue);
}
