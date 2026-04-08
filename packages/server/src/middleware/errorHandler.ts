import { Request, Response, NextFunction } from 'express';

export class AppError extends Error {
  statusCode: number;
  constructor(message: string, statusCode: number = 400) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'AppError';
  }
}

export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction): void {
  // Always log the full stack server-side (never sent to client).
  // Stack traces are essential for diagnosing production issues.
  console.error('Error:', err.message);
  console.error(err.stack);

  if (err instanceof AppError) {
    res.status(err.statusCode).json({ success: false, message: err.message });
    return;
  }

  // Malformed JSON body → 400 not 500
  if (err instanceof SyntaxError && 'body' in err) {
    res.status(400).json({ success: false, message: 'Invalid JSON in request body' });
    return;
  }

  res.status(500).json({ success: false, message: 'Internal server error' });
}
