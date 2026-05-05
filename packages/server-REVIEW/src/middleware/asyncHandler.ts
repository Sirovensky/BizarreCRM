import { Request, Response, NextFunction } from 'express';

/**
 * Wraps an async Express route handler so thrown errors are passed to next().
 * Avoids the need for try/catch in every async route.
 */
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>
) {
  return (req: Request, res: Response, next: NextFunction) => {
    fn(req, res, next).catch(next);
  };
}
