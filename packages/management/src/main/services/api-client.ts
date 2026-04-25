/**
 * HTTPS API client for communicating with the local CRM server.
 * Connects to localhost on the configured port (default 443, reads
 * PORT from .env via setServerPort). Self-signed cert support for
 * loopback connections.
 *
 * SECURITY (EL1): Self-signed certs are only accepted when the target is
 * a loopback hostname (localhost / 127.0.0.1 / ::1). Any other hostname
 * requires a valid certificate chain — this guards against a stray
 * SERVER_BASE misconfiguration or DNS hijack turning into silent MITM.
 *
 * SECURITY (SEC-H98): TLS certificate fingerprint is pinned against the
 * known server.cert at startup. A process that port-squats on 443 before
 * the real server can bind will be detected immediately — its TLS cert
 * won't match the pinned SHA-256 fingerprint, and the connection is
 * aborted with an explicit error before any credentials are sent.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import https from 'node:https';
import path from 'node:path';
import tls from 'node:tls';
import { app } from 'electron';

let serverPort = 443;
const REQUEST_TIMEOUT = 30_000;

export function getServerBase(): string {
  return serverPort === 443
    ? 'https://localhost'
    : `https://localhost:${serverPort}`;
}

/**
 * Configure the API client's target port. Called once during startup
 * after the project root is resolved and .env is read. This allows the
 * dashboard to connect to servers running on non-default ports (e.g.
 * PORT=8443 in .env) without hardcoding the port.
 */
export function setServerPort(port: number): void {
  if (Number.isFinite(port) && port > 0 && port < 65536) {
    serverPort = port;
  }
}

/** Loopback hostnames where a self-signed cert is considered safe. */
const LOOPBACK_HOSTS = new Set<string>([
  'localhost',
  '127.0.0.1',
  '::1',
  '[::1]',
]);

function isLoopbackHost(hostname: string): boolean {
  // hostname may arrive bracket-wrapped ([::1]) from URL parsing on some Node
  // versions; normalize before comparing.
  const normalized = hostname.toLowerCase().replace(/^\[|\]$/g, '');
  return LOOPBACK_HOSTS.has(normalized);
}

// ---------------------------------------------------------------------------
// SEC-H98: TLS cert fingerprint pinning
// ---------------------------------------------------------------------------

/**
 * Compute a SHA-256 fingerprint from a PEM certificate, formatted as
 * colon-separated uppercase hex pairs — identical to the format Node exposes
 * via `tlsSocket.getPeerCertificate().fingerprint256`.
 *
 * We hash the raw DER bytes (the Base64 body of the PEM, decoded), not the
 * PEM text, because that is what the TLS stack hashes when it fills in
 * fingerprint256 on the peer-cert object.
 */
function computePemFingerprint(pemContent: string): string {
  const b64 = pemContent
    .replace(/-----BEGIN CERTIFICATE-----/g, '')
    .replace(/-----END CERTIFICATE-----/g, '')
    .replace(/\s+/g, '');
  const der = Buffer.from(b64, 'base64');
  const hash = crypto.createHash('sha256').update(der).digest('hex').toUpperCase();
  return (hash.match(/.{2}/g) as RegExpMatchArray).join(':');
}

/**
 * Resolve the path to server.cert relative to the monorepo root.
 *
 * AUDIT-MGT-007: The previous implementation walked 5 levels of path.dirname
 * from __dirname, which was correct in dev but broken in a packaged ASAR —
 * __dirname resolves inside the asar archive and walking up 5 levels only
 * reaches resources/, not resources/crm-source/.
 *
 * Fix: mirror the same packaged/dev split used by resolveTrustedProjectRoot()
 * in management-api.ts:
 *   - Packaged: <process.resourcesPath>/crm-source/packages/server/certs/server.cert
 *   - Dev:      <app.getAppPath()>/../../packages/server/certs/server.cert
 *               (monorepo layout: app lives in packages/management)
 *
 * Returns null if the cert file does not exist; pinning is skipped with a
 * warning so the dashboard can still start on first-run (before the server
 * has generated certs).
 */
function resolveCertPath(): string | null {
  let crmSource: string;
  if (app.isPackaged) {
    // Packaged build: electron-builder copies crm-source into resourcesPath
    // via the extraResources rule in electron-builder.yml.
    crmSource = path.join(process.resourcesPath, 'crm-source');
  } else {
    // Dev build: monorepo layout — app.getAppPath() === <repo>/packages/management
    crmSource = path.resolve(app.getAppPath(), '..', '..');
  }
  const candidate = path.join(crmSource, 'packages', 'server', 'certs', 'server.cert');
  return fs.existsSync(candidate) ? candidate : null;
}

/**
 * Expected SHA-256 fingerprint of packages/server/certs/server.cert,
 * computed once at module load.  null = cert file not found at startup
 * (pinning is skipped with a warning).
 */
const EXPECTED_FINGERPRINT: string | null = (() => {
  const certPath = resolveCertPath();
  if (certPath === null) {
    console.warn(
      '[api-client] SEC-H98: server.cert not found — TLS fingerprint pinning DISABLED. ' +
      'Start the CRM server at least once to generate certs.'
    );
    return null;
  }
  try {
    const pem = fs.readFileSync(certPath, 'utf8');
    const fp = computePemFingerprint(pem);
    console.info(`[api-client] SEC-H98: TLS cert pinned — expected fingerprint: ${fp}`);
    return fp;
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(`[api-client] SEC-H98: failed to compute cert fingerprint (${msg}) — pinning DISABLED`);
    return null;
  }
})();

/**
 * Constant-time string comparison to prevent timing-oracle attacks on the
 * fingerprint comparison.  Both strings must be the same byte length;
 * fingerprint256 values are always 95 characters (32 bytes × 2 hex + 31
 * colons), so this is safe.
 */
function timingSafeStringEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * `checkServerIdentity` callback injected into every loopback HTTPS request.
 *
 * Node calls this after the TLS handshake completes, passing the hostname and
 * the peer certificate object.  Returning undefined = accept; throwing = abort.
 *
 * We skip the default hostname check (which would fail for a self-signed cert
 * whose CN / SAN doesn't exactly match), then do our own fingerprint check
 * instead.
 */
function checkCertFingerprint(
  _hostname: string,
  cert: tls.PeerCertificate,
): Error | undefined {
  if (EXPECTED_FINGERPRINT === null) {
    // Pinning is disabled — let the connection proceed (rejectUnauthorized
    // already provides self-signed acceptance for loopback only).
    return undefined;
  }

  const presented = cert.fingerprint256;
  if (typeof presented !== 'string') {
    return new Error(
      'Cert fingerprint mismatch — possible port-squat / MITM (no fingerprint256 on peer cert)'
    );
  }

  if (!timingSafeStringEqual(presented.toUpperCase(), EXPECTED_FINGERPRINT)) {
    return new Error(
      `Cert fingerprint mismatch — possible port-squat / MITM\n` +
      `  expected : ${EXPECTED_FINGERPRINT}\n` +
      `  presented: ${presented.toUpperCase()}`
    );
  }

  return undefined;
}

// ---------------------------------------------------------------------------

export interface ApiResult<T = unknown> {
  status: number;
  body: {
    success: boolean;
    data?: T;
    message?: string;
  };
}

let superAdminToken: string | null = null;

export function setSuperAdminToken(token: string | null): void {
  superAdminToken = token;
}

export function getSuperAdminToken(): string | null {
  return superAdminToken;
}

export function apiRequest<T = unknown>(
  method: string,
  endpoint: string,
  body: unknown = null,
  authType: 'authenticated' | 'none' = 'authenticated'
): Promise<ApiResult<T>> {
  return new Promise((resolve, reject) => {
    const base = getServerBase();
    const url = new URL(`${base}${endpoint}`);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      // SEC-H7: The server's production Origin guard rejects requests without
      // an Origin header on sensitive routes. The dashboard is a trusted local
      // client, so we identify ourselves as the server's own origin.
      'Origin': base,
    };

    // All authenticated requests use the super admin JWT
    if (authType === 'authenticated' && superAdminToken) {
      headers['Authorization'] = `Bearer ${superAdminToken}`;
    }

    // Only accept self-signed certs for loopback. Anything else MUST validate.
    const acceptSelfSigned = isLoopbackHost(url.hostname);

    const options: https.RequestOptions = {
      method,
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      rejectUnauthorized: !acceptSelfSigned,
      // @audit-fixed: explicit `servername` so SNI matches the URL hostname
      // even when an upstream HTTPS agent overrides the default. Without
      // this, a future change that swaps SERVER_BASE for a non-loopback
      // hostname could send the wrong SNI value and silently fall back to
      // a "no SNI" cert match — usually the apex cert — which is exactly
      // the kind of subtle MITM hardening we want to prevent.
      servername: url.hostname,
      // @audit-fixed: lock the request to TLS 1.2 minimum. Electron's
      // bundled Node still understands TLS 1.0/1.1 over the loopback
      // adapter; pinning the floor here keeps a downgrade attack on the
      // local server (e.g. attacker spoofing the loopback) from succeeding.
      minVersion: 'TLSv1.2',
      headers,
      // SEC-H98: pin the cert fingerprint for loopback connections so a
      // port-squat impersonator is detected before any data is sent.
      checkServerIdentity: acceptSelfSigned ? checkCertFingerprint : undefined,
    };

    const req = https.request(options, (res) => {
      // AUDIT-MGT-019: Guard against unbounded response buffering. A rogue or
      // misconfigured server could stream an arbitrarily large body; without a
      // cap this accumulates in heap until OOM. Destroy the socket (not just
      // the request) once we exceed the ceiling so the TCP connection is torn
      // down immediately.
      const MAX_RESPONSE_BYTES = 10 * 1024 * 1024; // 10 MB
      let data = '';
      let totalBytes = 0;
      res.on('data', (chunk: Buffer) => {
        totalBytes += chunk.length;
        if (totalBytes > MAX_RESPONSE_BYTES) {
          req.destroy(new Error('Response too large: exceeded 10MB'));
          return;
        }
        data += chunk.toString();
      });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data) as ApiResult<T>['body'];
          resolve({ status: res.statusCode ?? 0, body: parsed });
        } catch {
          resolve({
            status: res.statusCode ?? 0,
            body: { success: false, message: data },
          });
        }
      });
    });

    req.on('error', (err: Error) => reject(err));
    req.setTimeout(REQUEST_TIMEOUT, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    if (body !== null) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

/**
 * AUDIT-MGT-006: Return whether TLS cert fingerprint pinning is currently
 * enabled. Pinning is disabled when server.cert is absent (first run before
 * the CRM server has generated certs). Exported so the IPC layer can expose
 * this status to the renderer without duplicating the cert-path logic.
 */
export function getCertPinningStatus(): { enabled: boolean; reason?: string } {
  const certPath = resolveCertPath();
  if (certPath === null) {
    return {
      enabled: false,
      reason:
        'server.cert not found — start the CRM server at least once to generate certs',
    };
  }
  return { enabled: true };
}

/**
 * Quick health check — resolves true if the server responds, false otherwise.
 */
export async function isServerReachable(): Promise<boolean> {
  try {
    const res = await apiRequest('GET', '/api/v1/health', null, 'none');
    return res.status === 200;
  } catch {
    return false;
  }
}
