/**
 * Ensure production-blocking auth secrets in the root .env are real secrets.
 *
 * Safe to run on every setup/update:
 * - Missing, empty, known-placeholder, or too-short values are generated.
 * - Existing strong values are preserved so updates do not invalidate sessions.
 */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const envPath = path.resolve(__dirname, '../../../.env');

const SECRET_RULES = [
  {
    key: 'JWT_SECRET',
    bytes: 64,
    minLength: 32,
    insecure: new Set(['dev-secret-change-me', 'change-me-to-a-random-string', 'change-me', '']),
  },
  {
    key: 'JWT_REFRESH_SECRET',
    bytes: 64,
    minLength: 32,
    insecure: new Set(['dev-refresh-secret-change-me', 'change-me-to-another-random-string', 'change-me', '']),
  },
  {
    key: 'SUPER_ADMIN_SECRET',
    bytes: 32,
    minLength: 32,
    insecure: new Set(['super-admin-dev-secret', 'change-me', 'change-me-in-production', '']),
  },
];

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function unquote(raw) {
  let value = String(raw ?? '').trim().replace(/\r$/, '');
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  value = value.replace(/\s+#.*$/, '').trim();
  return value;
}

function getEnvValue(content, key) {
  const re = new RegExp(`^(?:export\\s+)?${escapeRegex(key)}\\s*=\\s*(.*)$`, 'gm');
  let value = null;
  let match;
  while ((match = re.exec(content)) !== null) {
    value = unquote(match[1]);
  }
  return value;
}

function needsSecret(value, rule) {
  return value === null || value.length < rule.minLength || rule.insecure.has(value);
}

function setEnvValue(content, key, value) {
  const liveRe = new RegExp(`^(?:export\\s+)?${escapeRegex(key)}\\s*=.*$`, 'gm');
  const commentedRe = new RegExp(`^#\\s*${escapeRegex(key)}\\s*=.*$`, 'm');
  const line = `${key}=${value}`;

  if (liveRe.test(content)) return content.replace(liveRe, line);
  if (commentedRe.test(content)) return content.replace(commentedRe, line);

  const sep = content === '' || content.endsWith('\n') ? '' : '\n';
  return `${content}${sep}${line}\n`;
}

if (!fs.existsSync(envPath)) {
  fs.writeFileSync(envPath, '# BizarreCRM Server Configuration\n\n', 'utf-8');
}

let content = fs.readFileSync(envPath, 'utf-8');
const updatedKeys = [];

for (const rule of SECRET_RULES) {
  const value = getEnvValue(content, rule.key);
  if (!needsSecret(value, rule)) continue;

  content = setEnvValue(content, rule.key, crypto.randomBytes(rule.bytes).toString('hex'));
  updatedKeys.push(rule.key);
}

if (updatedKeys.length > 0) {
  fs.writeFileSync(envPath, content, 'utf-8');
  console.log(`[setup] Generated secure .env secrets: ${updatedKeys.join(', ')}`);
} else {
  console.log('[setup] .env auth secrets are present');
}
