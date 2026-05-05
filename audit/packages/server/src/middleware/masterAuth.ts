import type { Request, Response, NextFunction } from 'express';
import jwt, { VerifyOptions } from 'jsonwebtoken';
import { config } from '../config.js';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';

export interface MasterAuthPayload {
  superAdminId: number;
  username: string;
  role: 'super_admin';
}

// @audit-fixed: Pin the algorithm + issuer + audience so an attacker can't
// submit a token signed with `alg: none` or a different algorithm family
// (the classic HS256/RS256 confusion exploit) and have it accepted.
const MASTER_JWT_VERIFY_OPTIONS: VerifyOptions = {
  algorithms: ['HS256'],
  issuer: 'bizarre-crm',
  audience: 'bizarre-crm-master',
};

/**
 * Authentication middleware for master admin panel.
 * Uses a SEPARATE JWT secret from tenant auth to prevent cross-contamination.
 */
export function masterAuthMiddleware(req: Request, res: Response, next: NextFunction): void {
  const rid = res.locals.requestId as string | undefined;
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_NO_TOKEN, 'Master admin authentication required', rid));
    return;
  }

  const token = authHeader.substring(7);

  try {
    // @audit-fixed: Explicit algorithm whitelist blocks the alg=none attack
    // and the HS/RS confusion where an attacker signs with the public key.
    const decoded = jwt.verify(token, config.superAdminSecret, MASTER_JWT_VERIFY_OPTIONS) as MasterAuthPayload;
    // @audit-fixed: Explicitly re-check the role after verify — a verified
    // but unexpected payload shape should never grant access.
    if (!decoded || typeof decoded !== 'object' || decoded.role !== 'super_admin') {
      res.status(403).json(errorBody(ERROR_CODES.ERR_PERM_ADMIN_REQUIRED, 'Super admin access required', rid));
      return;
    }
    req.superAdmin = decoded;
    next();
  } catch {
    res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_TOKEN, 'Invalid or expired master admin token', rid));
  }
}
