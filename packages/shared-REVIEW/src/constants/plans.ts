/** Tenant plan definitions — single source of truth for both server and frontend. */

export type TenantPlan = 'free' | 'pro';

export interface PlanLimits {
  maxTicketsMonth: number | null;  // null = unlimited
  maxUsers: number | null;
  storageLimitMb: number | null;
}

export interface PlanFeatures {
  advancedReports: boolean;
  scheduledReports: boolean;
  customFields: boolean;
  memberships: boolean;
  automations: boolean;
  apiKeys: boolean;
  customBranding: boolean;
  automatedBackups: boolean;
  exportReports: boolean;
}

export interface PlanDefinition {
  name: string;
  displayName: string;
  priceCents: number;        // monthly price in cents (0 = free)
  limits: PlanLimits;
  features: PlanFeatures;
}

export const PLAN_DEFINITIONS: Record<TenantPlan, PlanDefinition> = {
  free: {
    name: 'free',
    displayName: 'Free',
    priceCents: 0,
    limits: { maxTicketsMonth: 50, maxUsers: 1, storageLimitMb: 500 },
    features: {
      advancedReports: false,
      scheduledReports: false,
      customFields: false,
      memberships: false,
      automations: false,
      apiKeys: false,
      customBranding: false,
      automatedBackups: false,
      exportReports: false,
    },
  },
  pro: {
    name: 'pro',
    displayName: 'Pro',
    priceCents: 6900, // $69/month
    limits: { maxTicketsMonth: null, maxUsers: null, storageLimitMb: 30720 }, // 30 GB
    features: {
      advancedReports: true,
      scheduledReports: true,
      customFields: true,
      memberships: true,
      automations: true,
      apiKeys: true,
      customBranding: true,
      automatedBackups: true,
      exportReports: true,
    },
  },
};

export const FEATURE_NAMES: Record<keyof PlanFeatures, string> = {
  advancedReports: 'Advanced Reports',
  scheduledReports: 'Scheduled Reports',
  customFields: 'Custom Fields',
  memberships: 'Membership Billing',
  automations: 'Automations',
  apiKeys: 'API Access',
  customBranding: 'Custom Branding',
  automatedBackups: 'Automated Backups',
  exportReports: 'Report Exports',
};

export const TRIAL_DURATION_DAYS = 14;

export function getPlanDefinition(plan: TenantPlan): PlanDefinition {
  return PLAN_DEFINITIONS[plan] || PLAN_DEFINITIONS.free;
}

export function isFeatureAllowed(plan: TenantPlan, feature: keyof PlanFeatures): boolean {
  return getPlanDefinition(plan).features[feature];
}

export function getPlanLimit(plan: TenantPlan, limit: keyof PlanLimits): number | null {
  return getPlanDefinition(plan).limits[limit];
}
