import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export interface MasterAuthPayload {
  superAdminId: number;
  username: string;
  role: 'super_admin';
}

/**
 * Authentication middleware for master admin panel.
 * Uses a SEPARATE JWT secret from tenant auth to prevent cross-contamination.
 */
export function masterAuthMiddleware(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ success: false, message: 'Master admin authentication required' });
    return;
  }

  const token = authHeader.substring(7);

  try {
    const decoded = jwt.verify(token, config.superAdminSecret) as MasterAuthPayload;
    if (decoded.role !== 'super_admin') {
      res.status(403).json({ success: false, message: 'Super admin access required' });
      return;
    }
    req.superAdmin = decoded;
    next();
  } catch {
    res.status(401).json({ success: false, message: 'Invalid or expired master admin token' });
  }
}
