const Db = require('better-sqlite3');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

const envText = fs.readFileSync(path.resolve(__dirname, '..', '.env'), 'utf8');
const env = Object.fromEntries(
  envText.split(/\r?\n/)
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'))
    .map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1)]; })
);

const jwtSecret = env.JWT_SECRET;
const superAdminSecret = env.SUPER_ADMIN_SECRET || '';

const V1 = crypto.createHash('sha256').update(jwtSecret + ':totp:v1').digest();
const V2 = crypto.createHash('sha256').update(jwtSecret + ':totp-encryption:v2:' + superAdminSecret).digest();
const V3 = Buffer.from(crypto.hkdfSync('sha256', Buffer.from(jwtSecret + superAdminSecret), Buffer.from('bizarre-totp-salt-v3'), Buffer.from('totp-key-v3'), 32));
const KEYS = { 1: V1, 2: V2, 3: V3 };

function decryptSecret(ct) {
  if (!ct.includes(':')) return ct;
  if (!ct.startsWith('v')) {
    const key = crypto.createHash('sha256').update(jwtSecret).digest();
    const [iv, tag, enc] = ct.split(':');
    const d = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'hex'));
    d.setAuthTag(Buffer.from(tag, 'hex'));
    return d.update(Buffer.from(enc, 'hex')) + d.final('utf8');
  }
  const [vS, iv, tag, enc] = ct.split(':');
  const v = parseInt(vS.slice(1), 10);
  const key = KEYS[v];
  if (!key) throw new Error('unknown key v' + v);
  const d = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'hex'));
  d.setAuthTag(Buffer.from(tag, 'hex'));
  if (v >= 3) d.setAAD(Buffer.from(`v${v}`));
  return d.update(Buffer.from(enc, 'hex')) + d.final('utf8');
}

function b32decode(s) {
  s = s.replace(/=+$/, '').toUpperCase().replace(/\s+/g, '');
  const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = '';
  for (const c of s) {
    const i = alpha.indexOf(c);
    if (i < 0) throw new Error('bad b32: ' + c);
    bits += i.toString(2).padStart(5, '0');
  }
  const out = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(out);
}

function totp(secretB32, t = Math.floor(Date.now() / 1000), step = 30, digits = 6) {
  const key = b32decode(secretB32);
  const counter = Math.floor(t / step);
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const hmac = crypto.createHmac('sha1', key).update(buf).digest();
  const off = hmac[hmac.length - 1] & 0x0f;
  const code = ((hmac[off] & 0x7f) << 24 | (hmac[off + 1] & 0xff) << 16 | (hmac[off + 2] & 0xff) << 8 | (hmac[off + 3] & 0xff)) % 10 ** digits;
  return String(code).padStart(digits, '0');
}

const dbs = [
  'packages/server/data/bizarre-crm.db',
  'packages/server/data/tenants/bizarreelectronics.db',
  'packages/server/data/tenants/bizarre-electronics.db',
];

for (const rel of dbs) {
  const p = path.resolve(__dirname, '..', rel);
  if (!fs.existsSync(p)) { console.log(rel, 'missing'); continue; }
  try {
    const db = new Db(p, { readonly: true });
    const row = db.prepare("SELECT username, totp_secret, totp_enabled FROM users WHERE username='admin' LIMIT 1").get();
    db.close();
    if (!row || !row.totp_secret) { console.log(rel, 'no admin/secret'); continue; }
    const secret = decryptSecret(row.totp_secret);
    const code = totp(secret);
    const now = Math.floor(Date.now() / 1000);
    const remaining = 30 - (now % 30);
    console.log(`${rel}  user=${row.username}  enabled=${row.totp_enabled}  CODE=${code}  (${remaining}s remaining)`);
  } catch (e) {
    console.log(rel, 'ERR', e.message);
  }
}
