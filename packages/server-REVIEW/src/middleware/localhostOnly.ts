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
  // SCAN-1150: Docker + WSL2 on Windows occasionally reports loopback in
  // its fully-expanded form. Include the expanded variant so the super-
  // admin panel is reachable from the host in those configs. Still 100%
  // local — neither form can be sourced from a remote TCP peer.
  '0:0:0:0:0:0:0:1',
]);

export function localhostOnly(req: Request, res: Response, next: NextFunction): void {
  const rawIp = req.socket?.remoteAddress || '';
  const ip = rawIp.toLowerCase();
  // Normalise the IPv4-mapped-v6 form BEFORE the Set lookup: some peers
  // also prefix the mapped form with extra zeros (e.g. `::ffff:0:7f00:1`).
  const isLocal =
    LOCALHOST_IPS.has(ip) ||
    (ip.startsWith('::ffff:') && ip.slice('::ffff:'.length) === '127.0.0.1');
  if (!isLocal) {
    // Return 404 — do not confirm the route exists to a non-local caller.
    res.status(404).json({
      success: false,
      message: 'Not found',
    });
    return;
  }
  next();
}
