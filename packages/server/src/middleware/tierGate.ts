import { Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import { isFeatureAllowed, FEATURE_NAMES, type PlanFeatures } from '@bizarre-crm/shared';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('tierGate');

/** Middleware factory: gates access to Pro-only features based on tenant plan. */
export function requireFeature(feature: keyof PlanFeatures) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const rid = res.locals.requestId as string | undefined;
    // Single-tenant mode bypasses all tier checks
    if (!config.multiTenant) { next(); return; }

    // Defensive check: in multi-tenant mode, tenantPlan MUST be set by tenantResolver.
    // If it's missing, the middleware chain is broken — fail closed (reject) rather than
    // silently defaulting to 'free' which could mask bugs.
    if (!req.tenantPlan) {
      logger.warn('tenant_plan_missing', { method: req.method, path: req.path, note: 'middleware chain issue — rejecting' });
      res.status(403).json(errorBody(
        ERROR_CODES.ERR_TENANT_CONTEXT_MISSING,
        'Tenant plan context missing.',
        rid,
      ));
      return;
    }

    if (isFeatureAllowed(req.tenantPlan, feature)) { next(); return; }

    logger.warn('feature_gated', { feature, plan: req.tenantPlan, tenantId: req.tenantId, tenantSlug: req.tenantSlug });
    res.status(403).json(errorBody(
      ERROR_CODES.ERR_PERM_FEATURE_GATED,
      `${FEATURE_NAMES[feature]} requires a Pro plan. Upgrade to unlock this feature.`,
      rid,
      { upgrade_required: true, feature, feature_name: FEATURE_NAMES[feature] },
    ));
  };
}
