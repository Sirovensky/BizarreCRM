import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';
import Database from 'better-sqlite3';
import { verifySync, generateSync } from 'otplib';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../../../../.env') });

const username = process.argv[2] || 'admin';
const dbPath = path.resolve(__dirname, '../../data/bizarre-crm.db');
const db = new Database(dbPath, { readonly: true });

const jwtSecret = process.env.JWT_SECRET || '';
const superAdminSecret = process.env.SUPER_ADMIN_SECRET || '';

function hkdfKey(ikmParts: string[], salt: string, info: string, length = 32): Buffer {
  const ikm = Buffer.from(ikmParts.join(''));
  const derived = crypto.hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from(info), length);
  return Buffer.from(derived);
}

const V1 = crypto.createHash('sha256').update(jwtSecret + ':totp:v1').digest();
const V2 = crypto.createHash('sha256').update(jwtSecret + ':totp-encryption:v2:' + superAdminSecret).digest();
const V3 = hkdfKey([jwtSecret, superAdminSecret], 'bizarre-totp-salt-v3', 'totp-key-v3', 32);
const KEYS: Record<number, Buffer> = { 1: V1, 2: V2, 3: V3 };

function decrypt(ciphertext: string): string {
  if (!ciphertext.includes(':')) return ciphertext;
  if (!ciphertext.startsWith('v')) {
    const key = crypto.createHash('sha256').update(jwtSecret).digest();
    const [ivHex, tagHex, encHex] = ciphertext.split(':');
    const d = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
    d.setAuthTag(Buffer.from(tagHex, 'hex'));
    return Buffer.concat([d.update(Buffer.from(encHex, 'hex')), d.final()]).toString('utf8');
  }
  const [vStr, ivHex, tagHex, encHex] = ciphertext.split(':');
  const version = parseInt(vStr.slice(1), 10);
  const key = KEYS[version];
  if (!key) throw new Error(`Unknown key version: ${version}`);
  const d = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
  d.setAuthTag(Buffer.from(tagHex, 'hex'));
  if (version >= 3) d.setAAD(Buffer.from(`v${version}`));
  return Buffer.concat([d.update(Buffer.from(encHex, 'hex')), d.final()]).toString('utf8');
}

const row = db.prepare('SELECT username, totp_secret, totp_enabled FROM users WHERE username = ?').get(username) as
  | { username: string; totp_secret: string | null; totp_enabled: number }
  | undefined;

if (!row) {
  console.error(`User not found: ${username}`);
  process.exit(1);
}
if (!row.totp_secret) {
  console.error(`User ${username} has no TOTP secret (totp_enabled=${row.totp_enabled})`);
  process.exit(1);
}

const secret = decrypt(row.totp_secret);
const code = generateSync({ secret });
const remaining = 30 - (Math.floor(Date.now() / 1000) % 30);
console.log(`user:      ${row.username}`);
console.log(`code:      ${code}`);
console.log(`expires:   ${remaining}s`);
console.log(`verify:    ${verifySync({ token: code, secret })}`);
