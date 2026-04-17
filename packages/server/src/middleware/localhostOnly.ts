import type { Request, Response, NextFunction } from 'express';

// Localhost-only guard — shared by /management/api and /super-admin/*.
// CRITICAL: Block all requests that don't originate from the loopback
// interface. This prevents external attackers (including anything past
// Cloudflare) from reaching these panels, even if JWT signing keys leak.
//
// SECURITY: req.socket.remoteAddress (actual TCP source) is used, NOT
// req.ip — the latter honours X-Forwarded-For when trust proxy is set and
// can be spoofed by a hostile client or a misconfigured proxy.
//
// `localhost` is NOT in the set because req.socket.remoteAddress never
// returns the literal string 'localhost'; only numeric IPs do.
const LOCALHOST_IPS = new Set<string>([
  '127.0.0.1',
  '::1',
  '::ffff:127.0.0.1',
]);

export function localhostOnly(req: Request, res: Response, next: NextFunction): void {
  const ip = req.socket?.remoteAddress || '';
  if (!LOCALHOST_IPS.has(ip)) {
    // Return 404 — do not confirm the route exists to a non-local caller.
    res.status(404).json({
      success: false,
      message: 'Not found',
    });
    return;
  }
  next();
}
