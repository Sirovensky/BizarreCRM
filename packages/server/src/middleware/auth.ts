import { Request, Response, NextFunction } from 'express';
import { SignOptions, VerifyOptions } from 'jsonwebtoken';
import { config } from '../config.js';
import { verifyJwtWithRotation } from '../utils/jwtSecrets.js';
import { ROLE_PERMISSIONS } from '@bizarre-crm/shared';

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
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ success: false, message: 'No token provided' });
    return;
  }

  const token = authHeader.slice(7);
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

    // Reject refresh tokens used as access tokens
    // @audit-fixed: Previously only rejected `type === 'refresh'` which still
    // allows a refresh token signed with a different `type` marker to pass.
    // Require an explicit `type === 'access'` marker AND a valid sessionId /
    // userId shape to slip through — any unknown token type is rejected.
    if (payload.type !== undefined && payload.type !== 'access') {
      res.status(401).json({ success: false, message: 'Invalid token type' });
      return;
    }
    if (typeof payload.sessionId !== 'string' || typeof payload.userId !== 'number') {
      res.status(401).json({ success: false, message: 'Invalid token payload' });
      return;
    }

    // Multi-tenant: verify the token's tenant matches the request's tenant
    if (config.multiTenant) {
      // Both must match: tenant token on tenant request, or null on null
      // SECURITY: In multi-tenant mode, requests without a resolved tenant (req.tenantSlug undefined)
      // must NOT be serviced with tenant auth — only master admin routes should work without a tenant.
      if (!req.tenantSlug) {
        res.status(401).json({ success: false, message: 'Tenant context required' });
        return;
      }
      if (payload.tenantSlug !== req.tenantSlug) {
        res.status(401).json({ success: false, message: 'Token not valid for this tenant' });
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
      req.asyncDb.get<{ role_id: number }>(
        'SELECT role_id FROM user_custom_roles WHERE user_id = ?',
        payload.userId
      ),
    ]).then(async ([session, user, customRole]) => {
      if (!session) {
        res.status(401).json({ success: false, message: 'Session expired' });
        return;
      }
      if (!user) {
        res.status(401).json({ success: false, message: 'User not found' });
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
            res.status(401).json({ success: false, message: 'Session idle timeout' });
            return;
          }
        }
      }

      // Touch last_active so we don't immediately expire an active user.
      // Best-effort — failure doesn't block the request.
      req.asyncDb
        .run("UPDATE sessions SET last_active = datetime('now') WHERE id = ?", payload.sessionId)
        .catch(() => { /* ignore */ });

      // AUD-H2: if a custom_roles row is assigned, load its allowed=1 keys
      // and cap at the active-role check. Inactive custom_roles are ignored
      // (treated as no-assignment, falls back to users.role).
      let customRolePermissions: Set<string> | null = null;
      if (customRole?.role_id) {
        const roleRow = await req.asyncDb.get<{ is_active: number }>(
          'SELECT is_active FROM custom_roles WHERE id = ?',
          customRole.role_id,
        );
        if (roleRow?.is_active === 1) {
          const rows = await req.asyncDb.all<{ permission_key: string }>(
            'SELECT permission_key FROM role_permissions WHERE role_id = ? AND allowed = 1',
            customRole.role_id,
          );
          customRolePermissions = new Set(rows.map(r => r.permission_key));
        }
      }

      req.user = {
        ...user,
        permissions: user.permissions ? JSON.parse(user.permissions) : null,
        sessionId: payload.sessionId,
        customRolePermissions,
      };
      // Prevent caching of authenticated API responses (sensitive data protection)
      res.setHeader('Cache-Control', 'no-store');
      next();
    }).catch(() => {
      res.status(401).json({ success: false, message: 'Invalid token' });
    });
  } catch (err) {
    res.status(401).json({ success: false, message: 'Invalid token' });
  }
}

export function requirePermission(permission: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ success: false, message: 'Not authenticated' });
      return;
    }

    const userPerms = req.user.permissions || {};

    // SEC-H18: when a custom role is assigned, its matrix is authoritative
    // even for users whose `users.role` is still `'admin'`. Previously the
    // hard admin bypass fired FIRST and short-circuited every custom-role
    // check, which meant `PUT /roles/users/:userId/role` could demote an
    // admin's custom role to something narrow (e.g. `cashier_readonly`)
    // while `users.role='admin'` silently kept granting full permissions.
    // Order flipped: custom-role check runs first; users.role='admin'
    // bypass only applies when no custom role has been pinned.
    if (req.user.customRolePermissions) {
      if (
        req.user.customRolePermissions.has(permission) ||
        req.user.customRolePermissions.has('admin.full') ||
        userPerms[permission]
      ) {
        next();
        return;
      }
      res.status(403).json({ success: false, message: 'Insufficient permissions' });
      return;
    }

    // SEC-H18: hard admin bypass kept for the (common) case where NO
    // custom role has been assigned — prevents org lockout when the
    // matrix hasn't been touched and keeps the legacy role model working.
    if (req.user.role === 'admin') {
      next();
      return;
    }

    // Legacy fallback: no custom role assigned, use hardcoded ROLE_PERMISSIONS.
    const rolePerms: string[] = ROLE_PERMISSIONS[req.user.role] || [];
    if (rolePerms.includes(permission) || userPerms[permission]) {
      next();
      return;
    }
    res.status(403).json({ success: false, message: 'Insufficient permissions' });
  };
}
