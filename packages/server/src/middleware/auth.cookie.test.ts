import { describe, expect, it, vi } from 'vitest';
import jwt from 'jsonwebtoken';
import type { Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import {
  authMiddleware,
  JWT_SIGN_OPTIONS,
  ACCESS_TOKEN_COOKIE_NAME,
  AUTH_CSRF_COOKIE_NAME,
} from './auth.js';

function makeAccessToken(userId: number, sessionId: string): string {
  return jwt.sign(
    { userId, sessionId, role: 'admin', tenantSlug: null, type: 'access' },
    config.accessJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '1h' },
  );
}

function makeReq(overrides: Partial<Request> & { cookies?: Record<string, string> }): Request {
  const asyncDb = {
    get: vi.fn((sql: string, param: unknown) => {
      if (sql.includes('FROM sessions')) return Promise.resolve({ id: param, last_active: new Date().toISOString() });
      if (sql.includes('FROM users')) {
        return Promise.resolve({
          id: 42,
          username: 'admin',
          email: 'admin@example.com',
          first_name: 'Ada',
          last_name: 'Lovelace',
          role: 'admin',
          permissions: '{}',
        });
      }
      if (sql.includes('FROM user_custom_roles')) return Promise.resolve(undefined);
      return Promise.resolve(undefined);
    }),
    all: vi.fn(() => Promise.resolve([])),
    run: vi.fn(() => Promise.resolve({ changes: 1, lastInsertRowid: 1 })),
  };
  return {
    method: 'GET',
    headers: {},
    tenantSlug: null,
    asyncDb,
    ...overrides,
  } as unknown as Request;
}

function makeRes(): Response {
  return {
    locals: { requestId: 'req-test' },
    status: vi.fn().mockReturnThis(),
    json: vi.fn().mockReturnThis(),
    setHeader: vi.fn(),
  } as unknown as Response;
}

function runAuth(req: Request, res: Response): Promise<void> {
  return new Promise((resolve) => {
    const next: NextFunction = vi.fn(() => resolve());
    authMiddleware(req, res, next);
    setTimeout(resolve, 20);
  });
}

describe('authMiddleware access token sources', () => {
  it('accepts the httpOnly access-token cookie for web requests', async () => {
    const token = makeAccessToken(42, 'cookie-session');
    const req = makeReq({ cookies: { [ACCESS_TOKEN_COOKIE_NAME]: token } });
    const res = makeRes();

    await runAuth(req, res);

    expect(res.status).not.toHaveBeenCalled();
    expect(req.user?.id).toBe(42);
    expect(req.user?.sessionId).toBe('cookie-session');
  });

  it('continues accepting bearer tokens without CSRF for API clients', async () => {
    const token = makeAccessToken(42, 'bearer-session');
    const req = makeReq({
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
      cookies: {},
    });
    const res = makeRes();

    await runAuth(req, res);

    expect(res.status).not.toHaveBeenCalled();
    expect(req.user?.sessionId).toBe('bearer-session');
  });

  it('falls back to bearer on mutating API requests even if a cookie jar is present', async () => {
    const cookieToken = makeAccessToken(42, 'cookie-session');
    const bearerToken = makeAccessToken(42, 'bearer-session');
    const req = makeReq({
      method: 'POST',
      headers: { authorization: `Bearer ${bearerToken}` },
      cookies: { [ACCESS_TOKEN_COOKIE_NAME]: cookieToken },
    });
    const res = makeRes();

    await runAuth(req, res);

    expect(res.status).not.toHaveBeenCalled();
    expect(req.user?.sessionId).toBe('bearer-session');
  });

  it('rejects state-changing cookie-auth requests without matching CSRF', async () => {
    const token = makeAccessToken(42, 'cookie-session');
    const req = makeReq({
      method: 'POST',
      headers: {},
      cookies: {
        [ACCESS_TOKEN_COOKIE_NAME]: token,
        [AUTH_CSRF_COOKIE_NAME]: 'csrf-cookie',
      },
    });
    const res = makeRes();

    await runAuth(req, res);

    expect(res.status).toHaveBeenCalledWith(403);
    expect(req.user).toBeUndefined();
  });
});
