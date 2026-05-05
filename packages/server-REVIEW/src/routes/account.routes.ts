import { Router, Request, Response } from 'express';
import { config } from '../config.js';
import { getUsage } from '../services/usageTracker.js';
import { getPlanDefinition, type TenantPlan } from '@bizarre-crm/shared';

const router = Router();

// GET /api/v1/account/usage — Returns plan, trial, usage, and feature flags
router.get('/usage', (req: Request, res: Response) => {
  // Single-tenant: return Pro with no limits
  if (!config.multiTenant || !req.tenantId) {
    const proDef = getPlanDefinition('pro');
    res.json({
      success: true,
      data: {
        plan: 'pro',
        plan_name: 'Pro (Self-Hosted)',
        trial_active: false,
        trial_ends_at: null,
        usage: null,
        features: proDef.features,
      },
    });
    return;
  }

  const plan = (req.tenantPlan || 'free') as TenantPlan;
  const planDef = getPlanDefinition(plan);
  const usage = getUsage(req.tenantId);

  res.json({
    success: true,
    data: {
      plan,
      plan_name: planDef.displayName,
      price_cents: planDef.priceCents,
      trial_active: req.tenantTrialActive || false,
      trial_ends_at: req.tenantTrialEndsAt || null,
      usage: {
        tickets_created: usage?.tickets_created ?? 0,
        tickets_limit: planDef.limits.maxTicketsMonth,
        sms_sent: usage?.sms_sent ?? 0,
        active_users: usage?.active_users ?? 0,
        users_limit: planDef.limits.maxUsers,
        storage_bytes: usage?.storage_bytes ?? 0,
        storage_limit_mb: planDef.limits.storageLimitMb,
      },
      features: planDef.features,
    },
  });
});

export default router;
