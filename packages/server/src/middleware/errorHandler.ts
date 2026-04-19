import { Request, Response, NextFunction } from 'express';
import { WorkerPoolQueueFullError } from '../db/worker-pool.js';

export class AppError extends Error {
  statusCode: number;
  constructor(message: string, statusCode: number = 400) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'AppError';
  }
}

export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction): void {
  // SEC-L28: Stack traces are only logged outside production to avoid leaking
  // internal file paths / source-structure hints through any log shipper that
  // forwards stderr to a less-trusted sink. `err.message` remains for triage.
  // Client responses never include the stack regardless of env — that was
  // already the case and is preserved below.
  console.error('Error:', err?.message);
  if (process.env.NODE_ENV !== 'production') {
    console.error(err?.stack);
  }

  // @audit-fixed: Guard against headers already sent — writing a status
  // after `res.end()` has been called throws ERR_HTTP_HEADERS_SENT which
  // becomes an unhandledException and can crash the process.
  if (res.headersSent) return;

  // SEC-M48: Worker pool queue full → 503 with Retry-After so upstream
  // proxies and clients back off rather than hammering the already-saturated
  // pool. 2 s is conservative; at ~50-100 ops/s per thread the 200-slot
  // queue drains in well under 2 s under normal load.
  if (err instanceof WorkerPoolQueueFullError) {
    res.setHeader('Retry-After', '2');
    res.status(503).json({ success: false, message: 'Server busy, retry' });
    return;
  }

  if (err instanceof AppError) {
    res.status(err.statusCode).json({ success: false, message: err.message });
    return;
  }

  // Malformed JSON body → 400 not 500
  // @audit-fixed: `'body' in err` without the instanceof narrowing can throw
  // on primitive err values ("in" requires an object on the RHS). Guard it.
  if (err instanceof SyntaxError && typeof err === 'object' && err !== null && 'body' in err) {
    res.status(400).json({ success: false, message: 'Invalid JSON in request body' });
    return;
  }

  res.status(500).json({ success: false, message: 'Internal server error' });
}
