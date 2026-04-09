/**
 * HTTPS API client for communicating with the local CRM server.
 * All requests go to localhost:443 with self-signed cert support.
 */
import https from 'node:https';

const SERVER_BASE = 'https://localhost';
const REQUEST_TIMEOUT = 30_000;

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
    const url = new URL(`${SERVER_BASE}${endpoint}`);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    // All authenticated requests use the super admin JWT
    if (authType === 'authenticated' && superAdminToken) {
      headers['Authorization'] = `Bearer ${superAdminToken}`;
    }

    const options: https.RequestOptions = {
      method,
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      rejectUnauthorized: false,
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
