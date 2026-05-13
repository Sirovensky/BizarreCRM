import { Request, Response, NextFunction } from 'express';
import { SignOptions, VerifyOptions } from 'jsonwebtoken';
import crypto from 'crypto';
import { config } from '../config.js';
import { verifyJwtWithRotation } from '../utils/jwtSecrets.js';
import { ROLE_PERMISSIONS } from '@bizarre-crm/shared';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';
import { audit } from '../utils/audit.js';

const logger = createLogger('auth-middleware');

// SEC (A6/A10): Centralize JWT signing & verification options so both
// auth.routes.ts and middleware/auth.ts use the exact same algorithm,
// issuer, and audience. Mismatches cause silent verification failures.
export const JWT_ISSUER = 'bizarre-crm';
export const JWT_AUDIENCE = 'bizarre-crm-api';
export const JWT_SIGN_OPTIONS: SignOptions = {
  algorithm: 'HS256',
  issuer: JWT_ISSUER,
  audience: JWT_AUDIENCE,
};
export const JWT_VERIFY_OPTIONS: VerifyOptions = {
  algorithms: ['HS256'],
  issuer: JWT_ISSUER,
  audience: JWT_AUDIENCE,
};

export const ACCESS_TOKEN_COOKIE_NAME = 'accessToken';
export const AUTH_CSRF_COOKIE_NAME = 'csrf_token';
export const AUTH_CSRF_HEADER_NAME = 'x-csrf-token';
export const ACCESS_TOKEN_MAX_AGE_MS = 60 * 60 * 1000;

type AccessTokenSource = 'cookie' | 'bearer';

function cookieValue(req: Request, name: string): string | undefined {
  const cookies = (req as Request & { cookies?: Record<string, string> }).cookies;
  const value = cookies?.[name];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function getBearerAccessToken(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;
  const token = authHeader.slice(7).trim();
  return token || null;
}

export function getRequestAccessToken(req: Request): { token: string; source: AccessTokenSource } | null {
  const cookieToken = cookieValue(req, ACCESS_TOKEN_COOKIE_NAME);
  if (cookieToken) return { token: cookieToken, source: 'cookie' };

  const bearerToken = getBearerAccessToken(req);
  if (bearerToken) return { token: bearerToken, source: 'bearer' };

  return null;
}

function isStateChangingMethod(method: string): boolean {
  return method === 'POST' || method === 'PUT' || method === 'PATCH' || method === 'DELETE';
}

export function authCsrfMatches(req: Request): boolean {
  const csrfHeader = req.headers[AUTH_CSRF_HEADER_NAME];
  const csrfHeaderValue = Array.isArray(csrfHeader) ? csrfHeader[0] : csrfHeader;
  const csrfCookieValue = cookieValue(req, AUTH_CSRF_COOKIE_NAME);
  if (!csrfHeaderValue || !csrfCookieValue) return false;

  try {
    const headerBuf = Buffer.from(csrfHeaderValue, 'utf8');
    const cookieBuf = Buffer.from(csrfCookieValue, 'utf8');
    return headerBuf.length === cookieBuf.length && crypto.timingSafeEqual(headerBuf, cookieBuf);
  } catch {
    return false;
  }
}

export function issueAccessTokenCookie(req: Request, res: Response, accessToken: string): void {
  res.cookie(ACCESS_TOKEN_COOKIE_NAME, accessToken, {
    httpOnly: true,
    secure: req.secure || config.nodeEnv === 'production',
    sameSite: 'strict',
    maxAge: ACCESS_TOKEN_MAX_AGE_MS,
    path: '/',
  });
}

export function clearAccessTokenCookie(res: Response): void {
  res.clearCookie(ACCESS_TOKEN_COOKIE_NAME, { path: '/' });
}

// SEC (A8): Reject sessions that haven't been used in this many days.
// Matches the max refresh-token lifetime assumption (30d default / 90d trusted)
// but caps inactivity at 14d to contain stolen tokens sitting idle.
export const IDLE_SESSION_MAX_DAYS = 14;

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  permissions: Record<string, boolean> | null;
  sessionId: string;
  // AUD-H2: when a user has a row in user_custom_roles, this Set holds the
  // permission_keys their assigned custom_role grants (allowed=1). `null`
  // means no custom role is assigned and the legacy ROLE_PERMISSIONS map
  // is authoritative.
  customRolePermissions: Set<string> | null;
  // SEC-M61: table-backed per-user grants/denies. Missing keys inherit from
  // the custom-role/default-role matrix; explicit false is a deny override.
  permissionOverrides?: Map<string, boolean> | null;
}

export type PermissionResolutionSource =
  | 'user_grant'
  | 'user_deny'
  | 'custom_role'
  | 'admin_role'
  | 'default_role'
  | 'legacy_user_grant'
  | 'none';

export interface PermissionResolution {
  allowed: boolean;
  source: PermissionResolutionSource;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  const rid = res.locals.requestId as string | undefined;
  let tokenRef = getRequestAccessToken(req);
  if (!tokenRef) {
    res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_NO_TOKEN, 'No token provided', rid));
    return;
  }
  if (tokenRef.source === 'cookie' && isStateChangingMethod(req.method) && !authCsrfMatches(req)) {
    const bearerToken = getBearerAccessToken(req);
    if (bearerToken) {
      tokenRef = { token: bearerToken, source: 'bearer' };
    } else {
      res.status(403).json(errorBody(ERROR_CODES.ERR_CSRF_MISMATCH, 'CSRF token invalid', rid));
      return;
    }
  }

  const token = tokenRef.token;
  try {
    // SEC (A6): Explicit algorithm + issuer + audience prevents alg-confusion
    // attacks (e.g. "none" algorithm, RS256/HS256 confusion) and token reuse
    // across other JWT issuers.
    // SA1-1: verifyJwtWithRotation transparently tries config.jwtSecretPrevious
    // when the current secret fails signature verification, so operators can
    // rotate JWT_SECRET without invalidating every active session.
    const payload = verifyJwtWithRotation(token, 'access', JWT_VERIFY_OPTIONS) as unknown as {
      userId: number;
      sessionId: string;
      role: string;
      type?: string;
      tenantSlug?: string | null;
    };

    // SEC (SCAN-613): Strict positive assertion — only tokens whose payload
    // carries type === 'access' are accepted.  Previously the guard was
    // `type !== undefined && type !== 'access'`, which silently passed tokens
    // where type was absent (legacy tokens, scoped tokens without the field).
    // All issueTokens() call-sites now embed type:'access' so no grace period
    // is needed; any token without the field is definitively not an access token.
    if (payload.type !== 'access') {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_TOKEN_TYPE, 'Invalid token type', rid));
      return;
    }
    if (typeof payload.sessionId !== 'string' || typeof payload.userId !== 'number') {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_PAYLOAD, 'Invalid token payload', rid));
      return;
    }

    // Multi-tenant: verify the token's tenant matches the request's tenant
    if (config.multiTenant) {
      // Both must match: tenant token on tenant request, or null on null
      // SECURITY: In multi-tenant mode, requests without a resolved tenant (req.tenantSlug undefined)
      // must NOT be serviced with tenant auth — only master admin routes should work without a tenant.
      if (!req.tenantSlug) {
        res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_TENANT_REQUIRED, 'Tenant context required', rid));
        return;
      }
      if (payload.tenantSlug !== req.tenantSlug) {
        res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_TENANT_MISMATCH, 'Token not valid for this tenant', rid));
        return;
      }
    }

    // Verify session + fetch user in parallel via worker threads (non-blocking)
    // AUD-H2: also resolve user_custom_roles → role_permissions so
    // requirePermission() can enforce the editable matrix.
    Promise.all([
      req.asyncDb.get<{ id: string; last_active: string | null }>(
        "SELECT id, last_active FROM sessions WHERE id = ? AND expires_at > datetime('now')",
        payload.sessionId
      ),
      req.asyncDb.get<{ id: number; username: string; email: string; first_name: string; last_name: string; role: string; permissions: string | null }>(
        'SELECT id, username, email, first_name, last_name, role, permissions FROM users WHERE id = ? AND is_active = 1',
        payload.userId
      ),
      req.asyncDb.get<{ role_id: number; role_name: string | null; is_active: number | null }>(
        `SELECT ucr.role_id, cr.name AS role_name, cr.is_active
           FROM user_custom_roles ucr
           LEFT JOIN custom_roles cr ON cr.id = ucr.role_id
          WHERE ucr.user_id = ?`,
        payload.userId
      ),
      loadUserPermissionOverrides(req.asyncDb, payload.userId),
    ]).then(async ([session, user, customRole, permissionOverrides]) => {
      if (!session) {
        res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_SESSION_EXPIRED, 'Session expired', rid));
        return;
      }
      if (!user) {
        res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_USER_NOT_FOUND, 'User not found', rid));
        return;
      }

      // SEC (A8): Reject idle sessions whose last_active is > IDLE_SESSION_MAX_DAYS old.
      // Even if refresh token hasn't reached expires_at, an unused session is revoked.
      if (session.last_active) {
        const lastActiveMs = new Date(session.last_active).getTime();
        if (!Number.isNaN(lastActiveMs)) {
          const idleMs = Date.now() - lastActiveMs;
          const maxIdleMs = IDLE_SESSION_MAX_DAYS * 24 * 60 * 60 * 1000;
          if (idleMs > maxIdleMs) {
            // Clean up the idle session so a future refresh can't resurrect it.
            try {
              await req.asyncDb.run('DELETE FROM sessions WHERE id = ?', payload.sessionId);
            } catch { /* audit-log best-effort */ }
            res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_SESSION_IDLE, 'Session idle timeout', rid));
            return;
          }
        }
      }

      // Touch last_active so we don't immediately expire an active user.
      // Best-effort — failure doesn't block the request.
      req.asyncDb
        .run("UPDATE sessions SET last_active = datetime('now') WHERE id = ?", payload.sessionId)
        .catch((err: unknown) => {
          logger.warn('auth: last_active update failed', { err: err instanceof Error ? err.message : String(err) });
        });

      // AUD-H2: if a custom_roles row is assigned, load its explicit matrix.
      // If a built-in role was assigned before role_permissions was lazily
      // materialized, fall back to the shared built-in defaults.
      // BUGHUNT-2026-05-10-08: if user_custom_roles references a deleted
      // custom_roles row, the LEFT JOIN yields role_name=null + is_active=null
      // and we'd silently downgrade the user to legacy grants. Emit a
      // warning + audit row so the operator can see the missing reference.
      if (customRole?.role_id && (customRole.role_name == null || customRole.is_active == null)) {
        logger.warn('auth: user_custom_roles references missing custom_role; user falling back to legacy grants', {
          userId: payload.userId,
          role_id: customRole.role_id,
        });
        try {
          audit(req.db, 'auth_custom_role_missing', payload.userId, req.ip || 'unknown', {
            role_id: customRole.role_id,
            session_id: payload.sessionId,
          });
        } catch { /* non-fatal */ }
      }
      let customRolePermissions: Set<string> | null = null;
      if (customRole?.role_id && customRole.is_active === 1) {
        const rows = await req.asyncDb.all<{ permission_key: string; allowed: number }>(
          'SELECT permission_key, allowed FROM role_permissions WHERE role_id = ?',
          customRole.role_id,
        );
        const defaultRolePerms = customRole.role_name ? ROLE_PERMISSIONS[customRole.role_name] : undefined;
        customRolePermissions = rows.length > 0
          ? new Set(rows.filter(r => r.allowed === 1).map(r => r.permission_key))
          : new Set(defaultRolePerms || []);
      }

      // SCAN-1142: a corrupt users.permissions row (truncated import, manual
      // DB edit) would throw inside JSON.parse — the outer `.catch` then
      // surfaced a misleading 401 "Invalid token" to a user whose token
      // is actually fine. Fall back to null on parse failure so the user
      // can still authenticate with the standard role enum; log a warn so
      // an operator can spot the data corruption.
      let parsedPermissions: Record<string, boolean> | null = null;
      if (user.permissions) {
        try {
          const raw = JSON.parse(user.permissions);
          if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
            parsedPermissions = raw as Record<string, boolean>;
          }
        } catch {
          console.warn('[auth] corrupt users.permissions JSON, treating as null', { userId: user.id });
          parsedPermissions = null;
        }
      }
      req.user = {
        ...user,
        permissions: parsedPermissions,
        sessionId: payload.sessionId,
        customRolePermissions,
        permissionOverrides,
      };
      // Prevent caching of authenticated API responses (sensitive data protection)
      res.setHeader('Cache-Control', 'no-store');
      next();
    }).catch(() => {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_TOKEN, 'Invalid token', rid));
      return;
    });
  } catch (err) {
    res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_TOKEN, 'Invalid token', rid));
  }
}

async function loadUserPermissionOverrides(adb: AsyncDb, userId: number): Promise<Map<string, boolean> | null> {
  try {
    const rows = await adb.all<{ permission_key: string; allowed: number }>(
      'SELECT permission_key, allowed FROM user_permissions WHERE user_id = ?',
      userId,
    );
    if (rows.length === 0) return null;
    return new Map(rows.map(row => [row.permission_key, row.allowed === 1]));
  } catch (err) {
    // Rolling upgrades and old test fixtures may briefly lack the table.
    // Treat that as "no overrides" so legacy role behavior remains intact.
    if (String((err as Error)?.message || err).includes('no such table: user_permissions')) {
      logger.warn('auth: user_permissions table missing; treating user overrides as empty', { userId });
      return null;
    }
    throw err;
  }
}

export function resolveEffectivePermission(user: AuthUser, permission: string): PermissionResolution {
  if (user.permissionOverrides?.has(permission)) {
    const allowed = user.permissionOverrides.get(permission) === true;
    return { allowed, source: allowed ? 'user_grant' : 'user_deny' };
  }

  // SEC-M61: users.permissions JSON remains a legacy grant-only escape hatch.
  // A stored false never denied before this table existed, so it still only
  // means "no legacy grant"; deny semantics live in user_permissions.
  const legacyGrant = user.permissions?.[permission] === true;

  if (user.customRolePermissions) {
    if (user.customRolePermissions.has(permission)) {
      return { allowed: true, source: 'custom_role' };
    }
    if (legacyGrant) return { allowed: true, source: 'legacy_user_grant' };
    return { allowed: false, source: 'none' };
  }

  // SEC-H18: hard admin bypass kept for the common case where no custom role
  // has been assigned, but SEC-M61 user-level deny overrides have already had
  // the first say above.
  if (user.role === 'admin') {
    return { allowed: true, source: 'admin_role' };
  }

  const rolePerms: string[] = ROLE_PERMISSIONS[user.role] || [];
  if (rolePerms.includes(permission)) {
    return { allowed: true, source: 'default_role' };
  }
  if (legacyGrant) return { allowed: true, source: 'legacy_user_grant' };
  return { allowed: false, source: 'none' };
}

export function hasPermission(user: AuthUser | null | undefined, permission: string): boolean {
  if (!user) return false;
  return resolveEffectivePermission(user, permission).allowed;
}

export function requirePermission(permission: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const rid = res.locals.requestId as string | undefined;
    if (!req.user) {
      res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_NO_TOKEN, 'Not authenticated', rid));
      return;
    }

    if (hasPermission(req.user, permission)) {
      next();
      return;
    }
    res.status(403).json(errorBody(ERROR_CODES.ERR_PERM_INSUFFICIENT, 'Insufficient permissions', rid, { permission }));
  };
}
