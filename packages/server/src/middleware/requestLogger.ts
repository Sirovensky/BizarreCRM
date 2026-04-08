/**
 * HTTP request logging middleware (ENR-INFRA3).
 * Logs method, path, status code, and response time in ms
 * using the structured JSON logger.
 */
import { Request, Response, NextFunction } from 'express';
import { createLogger } from '../utils/logger.js';

const log = createLogger('http');

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();

  // Hook into response finish event to capture status and timing
  res.on('finish', () => {
    const duration = Date.now() - start;
    const meta = {
      method: req.method,
      path: req.originalUrl || req.path,
      status: res.statusCode,
      duration_ms: duration,
    };

    if (res.statusCode >= 500) {
      log.error(`${req.method} ${meta.path} ${res.statusCode} ${duration}ms`, meta);
    } else if (res.statusCode >= 400) {
      log.warn(`${req.method} ${meta.path} ${res.statusCode} ${duration}ms`, meta);
    } else {
      log.info(`${req.method} ${meta.path} ${res.statusCode} ${duration}ms`, meta);
    }
  });

  next();
}
