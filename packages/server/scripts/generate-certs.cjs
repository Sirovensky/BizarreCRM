/**
 * Generate self-signed SSL certificates for the bundled HTTPS server.
 *
 * Cert is emitted with Subject Alternative Name entries covering:
 *   - DNS:localhost
 *   - IP:127.0.0.1, IP:::1
 *   - Every IPv4/IPv6 address bound to a non-internal NIC at install time
 *     (so LAN access from phones/tablets/laptops trusts the same cert).
 *   - Any DNS name supplied via the SETUP_HOSTNAME or SETUP_HOSTNAMES env var
 *     (comma-separated for the plural form).
 *
 * Why SAN matters: modern browsers (Firefox/Chrome since ~2017) ignore the
 * cert's CN for hostname verification per RFC 2818 + CA/Browser Forum BR.
 * A SAN-less cert "works" for the top-level page after an explicit security
 * exception, but background subresource fetches (modules, fetch(), WebSocket
 * upgrades) silently fail — hands-off symptom is hung module loads + dead HMR.
 *
 * Existing-install upgrade path: an older cert with no SAN block is detected
 * and replaced (backed up first to *.bak-<ts>). Pass --force to regen even a
 * valid SAN-bearing cert (e.g. after adding a new LAN IP).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const FORCE = process.argv.includes('--force');

const certsDir = path.resolve(__dirname, '../certs');
const certPath = path.join(certsDir, 'server.cert');
const keyPath = path.join(certsDir, 'server.key');

if (!fs.existsSync(certsDir)) {
  fs.mkdirSync(certsDir, { recursive: true });
}

function findOpenssl() {
  const candidates = [
    'openssl',
    'C:\\Program Files\\Git\\usr\\bin\\openssl.exe',
    'C:\\Program Files (x86)\\Git\\usr\\bin\\openssl.exe',
  ];
  for (const p of candidates) {
    try {
      execSync(`"${p}" version`, { stdio: 'pipe' });
      return p;
    } catch { /* try next */ }
  }
  return null;
}

function certHasSAN(certFile) {
  const openssl = findOpenssl();
  if (!openssl) return null; // unknown — be safe, treat as missing
  try {
    const out = execSync(
      `"${openssl}" x509 -in "${certFile}" -noout -text`,
      { stdio: ['ignore', 'pipe', 'pipe'] },
    ).toString();
    return /X509v3 Subject Alternative Name/i.test(out);
  } catch {
    return false;
  }
}

function collectSanEntries() {
  const dns = new Set(['localhost']);
  const ips = new Set(['127.0.0.1', '::1']);

  const extraHostsRaw = process.env.SETUP_HOSTNAMES || process.env.SETUP_HOSTNAME || '';
  for (const h of extraHostsRaw.split(',').map(s => s.trim()).filter(Boolean)) {
    dns.add(h);
  }

  for (const ifaceList of Object.values(os.networkInterfaces())) {
    if (!ifaceList) continue;
    for (const addr of ifaceList) {
      if (addr.internal) continue;
      ips.add(addr.address);
    }
  }

  const parts = [];
  for (const d of dns) parts.push(`DNS:${d}`);
  for (const ip of ips) parts.push(`IP:${ip}`);
  return parts.join(',');
}

function backupExisting() {
  if (!fs.existsSync(certPath) && !fs.existsSync(keyPath)) return;
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  if (fs.existsSync(certPath)) fs.copyFileSync(certPath, `${certPath}.bak-${ts}`);
  if (fs.existsSync(keyPath)) fs.copyFileSync(keyPath, `${keyPath}.bak-${ts}`);
  console.log(`[setup] Existing cert + key backed up with suffix .bak-${ts}`);
}

function shouldRegenerate() {
  if (FORCE) return { regen: true, reason: '--force flag' };
  if (!fs.existsSync(certPath) || !fs.existsSync(keyPath)) {
    return { regen: true, reason: 'cert files missing' };
  }
  const hasSAN = certHasSAN(certPath);
  if (hasSAN === false) {
    return { regen: true, reason: 'existing cert lacks Subject Alternative Name' };
  }
  return { regen: false, reason: 'existing cert already has SAN — skipping (pass --force to regenerate)' };
}

function generate() {
  const openssl = findOpenssl();
  if (!openssl) {
    console.error('[setup] ERROR: openssl not found. Install Git for Windows (bundles openssl) or supply your own cert at:');
    console.error(`        ${certPath}`);
    console.error(`        ${keyPath}`);
    process.exit(1);
  }

  const san = collectSanEntries();
  const subj = '/CN=localhost/O=BizarreCRM';
  const cmd =
    `"${openssl}" req -x509 -newkey rsa:2048 -nodes ` +
    `-keyout "${keyPath}" -out "${certPath}" ` +
    `-days 3650 -subj "${subj}" -addext "subjectAltName=${san}"`;

  try {
    // MSYS_NO_PATHCONV=1 stops Git Bash on Windows from rewriting the leading
    // slash of -subj "/CN=..." into a drive path, which otherwise drops the
    // CN component on the way to openssl. No-op on Linux/macOS.
    execSync(cmd, {
      stdio: 'pipe',
      env: { ...process.env, MSYS_NO_PATHCONV: '1', MSYS2_ARG_CONV_EXCL: '*' },
    });
  } catch (err) {
    console.error('[setup] openssl failed to generate cert:', err.stderr?.toString() || err.message);
    process.exit(1);
  }

  console.log(`[setup] Self-signed cert generated (10-year). SAN: ${san}`);
}

const { regen, reason } = shouldRegenerate();
if (!regen) {
  console.log(`[setup] SSL certificates: ${reason}`);
  process.exit(0);
}

console.log(`[setup] Regenerating SSL cert: ${reason}`);
backupExisting();
generate();
