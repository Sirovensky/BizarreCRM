import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { ROLE_PERMISSIONS } from '@bizarre-crm/shared';

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  permissions: Record<string, boolean> | null;
  sessionId: string;
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
    const payload = jwt.verify(token, config.jwtSecret) as { userId: number; sessionId: string; role: string; type?: string; tenantSlug?: string | null };

    // Reject refresh tokens used as access tokens
    if (payload.type === 'refresh') {
      res.status(401).json({ success: false, message: 'Invalid token type' });
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

    // Verify session is still valid
    const session = req.db.prepare('SELECT id FROM sessions WHERE id = ? AND expires_at > datetime(\'now\')').get(payload.sessionId) as any;
    if (!session) {
      res.status(401).json({ success: false, message: 'Session expired' });
      return;
    }

    // Get user
    const user = req.db.prepare('SELECT id, username, email, first_name, last_name, role, permissions FROM users WHERE id = ? AND is_active = 1').get(payload.userId) as any;
    if (!user) {
      res.status(401).json({ success: false, message: 'User not found' });
      return;
    }

    req.user = {
      ...user,
      permissions: user.permissions ? JSON.parse(user.permissions) : null,
      sessionId: payload.sessionId,
    };
    // Prevent caching of authenticated API responses (sensitive data protection)
    res.setHeader('Cache-Control', 'no-store');
    next();
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
    if (req.user.role === 'admin') {
      next();
      return;
    }
    // Check role-based + per-user permissions
    // ROLE_PERMISSIONS imported at top level to avoid require() in ESM
    const rolePerms: string[] = ROLE_PERMISSIONS[req.user.role] || [];
    const userPerms = req.user.permissions || {};

    if (rolePerms.includes(permission) || userPerms[permission]) {
      next();
      return;
    }
    res.status(403).json({ success: false, message: 'Insufficient permissions' });
  };
}
