import { Request, Response, NextFunction } from 'express';
import { WorkerPoolQueueFullError } from '../db/worker-pool.js';
import { ERROR_CODES, type ErrorCode } from '../utils/errorCodes.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('errorHandler');

/**
 * Thrown inside route handlers to surface a specific HTTP status + message
 * to the client through the central errorHandler. The optional `code` field
 * carries a stable ERR_* identifier so support / the client UI can branch
 * on error kind without parsing `message`.
 */
export class AppError extends Error {
  statusCode: number;
  code: ErrorCode | string;
  extra?: Record<string, unknown>;
  constructor(
    message: string,
    statusCode: number = 400,
    code: ErrorCode | string = ERROR_CODES.ERR_INT_GENERIC,
    extra?: Record<string, unknown>,
  ) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.extra = extra;
    this.name = 'AppError';
  }
}

function pickRequestId(res: Response): string | undefined {
  const id = res.locals?.requestId;
  return typeof id === 'string' ? id : undefined;
}

export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction): void {
  // SEC-L28: Stack traces are only logged outside production to avoid leaking
  // internal file paths / source-structure hints through any log shipper that
  // forwards stderr to a less-trusted sink. `err.message` remains for triage.
  // Client responses never include the stack regardless of env — that was
  // already the case and is preserved below.
  logger.error('unhandled_error', { message: err?.message });
  if (process.env.NODE_ENV !== 'production') {
    logger.error('unhandled_error_stack', { stack: err?.stack });
  }

  // @audit-fixed: Guard against headers already sent — writing a status
  // after `res.end()` has been called throws ERR_HTTP_HEADERS_SENT which
  // becomes an unhandledException and can crash the process.
  if (res.headersSent) return;

  const requestId = pickRequestId(res);

  // SEC-M48: Worker pool queue full → 503 with Retry-After so upstream
  // proxies and clients back off rather than hammering the already-saturated
  // pool. 2 s is conservative; at ~50-100 ops/s per thread the 200-slot
  // queue drains in well under 2 s under normal load.
  if (err instanceof WorkerPoolQueueFullError) {
    res.setHeader('Retry-After', '2');
    res.status(503).json({
      success: false,
      code: ERROR_CODES.ERR_SERVER_BUSY,
      message: 'Server busy, retry',
      request_id: requestId,
    });
    return;
  }

  if (err instanceof AppError) {
    res.status(err.statusCode).json({
      success: false,
      code: err.code,
      message: err.message,
      request_id: requestId,
      ...(err.extra ?? {}),
    });
    return;
  }

  // Malformed JSON body → 400 not 500
  // @audit-fixed: `'body' in err` without the instanceof narrowing can throw
  // on primitive err values ("in" requires an object on the RHS). Guard it.
  if (err instanceof SyntaxError && typeof err === 'object' && err !== null && 'body' in err) {
    res.status(400).json({
      success: false,
      code: ERROR_CODES.ERR_INPUT_JSON_MALFORMED,
      message: 'Invalid JSON in request body',
      request_id: requestId,
    });
    return;
  }

  res.status(500).json({
    success: false,
    code: ERROR_CODES.ERR_INT_GENERIC,
    message: 'Internal server error',
    request_id: requestId,
  });
}
