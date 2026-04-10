import { Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import { isFeatureAllowed, FEATURE_NAMES, type PlanFeatures } from '@bizarre-crm/shared';

/** Middleware factory: gates access to Pro-only features based on tenant plan. */
export function requireFeature(feature: keyof PlanFeatures) {
  return (req: Request, res: Response, next: NextFunction): void => {
    // Single-tenant mode bypasses all tier checks
    if (!config.multiTenant) { next(); return; }

    // Defensive check: in multi-tenant mode, tenantPlan MUST be set by tenantResolver.
    // If it's missing, the middleware chain is broken — fail closed (reject) rather than
    // silently defaulting to 'free' which could mask bugs.
    if (!req.tenantPlan) {
      console.warn(`[tierGate] Missing tenantPlan on ${req.method} ${req.path} — middleware chain issue? Rejecting.`);
      res.status(500).json({
        success: false,
        message: 'Tenant context not initialized. Please try again.',
      });
      return;
    }

    if (isFeatureAllowed(req.tenantPlan, feature)) { next(); return; }

    console.warn(`[tierGate] Feature "${feature}" blocked for plan "${req.tenantPlan}" on tenant ${req.tenantId} (${req.tenantSlug})`);
    res.status(403).json({
      success: false,
      upgrade_required: true,
      feature,
      feature_name: FEATURE_NAMES[feature],
      message: `${FEATURE_NAMES[feature]} requires a Pro plan. Upgrade to unlock this feature.`,
    });
  };
}
