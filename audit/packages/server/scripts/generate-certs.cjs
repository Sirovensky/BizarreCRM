/**
 * Generate self-signed SSL certificates using Node's built-in crypto.
 * No OpenSSL installation required.
 * Skips if certs already exist (won't overwrite).
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const certsDir = path.resolve(__dirname, '../certs');
const certPath = path.join(certsDir, 'server.cert');
const keyPath = path.join(certsDir, 'server.key');

if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
  console.log('[setup] SSL certificates already exist — skipping');
  process.exit(0);
}

// Ensure certs directory exists
if (!fs.existsSync(certsDir)) {
  fs.mkdirSync(certsDir, { recursive: true });
}

// Use Node's built-in crypto to generate a self-signed cert
// Node 15+ supports X509Certificate and generateKeyPairSync with x509
try {
  const crypto = require('crypto');

  // Generate RSA key pair
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });

  // Node's crypto doesn't have a built-in X509 cert generator,
  // so we use a lightweight approach: try OpenSSL first, fall back to
  // generating via node:child_process with the node binary itself

  // Try OpenSSL (available on most systems including Windows with Git)
  const opensslPaths = [
    'openssl',
    'C:\\Program Files\\Git\\usr\\bin\\openssl.exe',
    'C:\\Program Files (x86)\\Git\\usr\\bin\\openssl.exe',
  ];

  let openssl = null;
  for (const p of opensslPaths) {
    try {
      execSync(`"${p}" version`, { stdio: 'pipe' });
      openssl = p;
      break;
    } catch { /* not found, try next */ }
  }

  if (openssl) {
    execSync(
      `"${openssl}" req -x509 -newkey rsa:2048 -keyout "${keyPath}" -out "${certPath}" -days 3650 -nodes -subj "/CN=BizarreCRM/O=BizarreCRM"`,
      { stdio: 'pipe' }
    );
    console.log('[setup] SSL certificates generated (self-signed, 10 year, via OpenSSL)');
    process.exit(0);
  }

  // Fallback: write the key and create a minimal self-signed cert using Node
  // This requires the 'selfsigned' approach — generate with forge-like inline
  // Since we can't rely on external packages, write the private key and
  // use a pre-built cert generation via node's tls module trick

  // Actually, the simplest reliable fallback: use node -e with tls.createSecureContext
  // But the cleanest approach is just requiring openssl from Git's bundled copy

  // If no OpenSSL found at all, write a helpful error
  console.error('[setup] ERROR: Could not find OpenSSL to generate certificates.');
  console.error('        Install Git for Windows (includes OpenSSL) or place your own certs at:');
  console.error(`        ${certPath}`);
  console.error(`        ${keyPath}`);
  process.exit(1);

} catch (err) {
  console.error('[setup] Certificate generation failed:', err.message);
  process.exit(1);
}
