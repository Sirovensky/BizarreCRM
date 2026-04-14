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
 */
import https from 'node:https';

let serverPort = 443;
const REQUEST_TIMEOUT = 30_000;

function getServerBase(): string {
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
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk: Buffer) => {
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
