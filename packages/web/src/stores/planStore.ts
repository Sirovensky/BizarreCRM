import { create } from 'zustand';
import { api } from '@/api/client';
import type { PlanFeatures, TenantPlan } from '@bizarre-crm/shared';

interface PlanUsage {
  tickets_created: number;
  tickets_limit: number | null;
  sms_sent: number;
  active_users: number;
  users_limit: number | null;
  storage_bytes: number;
  storage_limit_mb: number | null;
}

interface PlanState {
  plan: TenantPlan;
  planName: string;
  priceCents: number;
  trialActive: boolean;
  trialEndsAt: string | null;
  usage: PlanUsage | null;
  features: PlanFeatures;
  isLoading: boolean;
  hasFetched: boolean;
  error: string | null;
  upgradeModalOpen: boolean;
  upgradeModalFeature: keyof PlanFeatures | 'ticket_limit' | null;
  fetchPlan: () => Promise<void>;
  openUpgradeModal: (feature: keyof PlanFeatures | 'ticket_limit') => void;
  closeUpgradeModal: () => void;
}

const DEFAULT_FEATURES: PlanFeatures = {
  advancedReports: false,
  scheduledReports: false,
  customFields: false,
  memberships: false,
  automations: false,
  apiKeys: false,
  customBranding: false,
  automatedBackups: false,
  exportReports: false,
};

// Allowlist of strings the server may send in a 403 `feature` field. Kept in
// sync with `PlanFeatures` + the special `ticket_limit` key used for the
// usage-cap gate. client.ts calls isUpgradeFeatureKey() to reject anything
// else before passing it to openUpgradeModal.
export type UpgradeFeatureKey = keyof PlanFeatures | 'ticket_limit';
const UPGRADE_FEATURE_KEYS = new Set<string>([
  ...Object.keys(DEFAULT_FEATURES),
  'ticket_limit',
]);
export function isUpgradeFeatureKey(value: unknown): value is UpgradeFeatureKey {
  return typeof value === 'string' && UPGRADE_FEATURE_KEYS.has(value);
}

// Singleton in-flight fetch promise — prevents concurrent calls from racing
let inFlightFetch: Promise<void> | null = null;

export const usePlanStore = create<PlanState>((set) => ({
  plan: 'free',
  planName: 'Free',
  priceCents: 0,
  trialActive: false,
  trialEndsAt: null,
  usage: null,
  features: DEFAULT_FEATURES,
  isLoading: false,
  hasFetched: false,
  error: null,
  upgradeModalOpen: false,
  upgradeModalFeature: null,

  fetchPlan: async () => {
    // De-duplicate concurrent calls — return the in-flight promise instead of racing
    if (inFlightFetch) return inFlightFetch;

    inFlightFetch = (async () => {
      set({ isLoading: true, error: null });
      try {
        const res = await api.get('/account/usage');
        const data = res.data.data;
        set({
          plan: data.plan,
          planName: data.plan_name,
          priceCents: data.price_cents ?? 0,
          trialActive: data.trial_active,
          trialEndsAt: data.trial_ends_at,
          usage: data.usage,
          features: data.features,
          isLoading: false,
          hasFetched: true,
          error: null,
        });
      } catch (err) {
        // Expose the failure on the store so feature gates can distinguish
        // "plan fetch failed, retry" from "plan is genuinely empty". Previously
        // every 500 silently defaulted to all-features-off with no way for the
        // UI to surface the problem or offer a retry.
        const message =
          err instanceof Error
            ? err.message
            : typeof err === 'string'
              ? err
              : 'Failed to load plan';
        set({ isLoading: false, hasFetched: true, error: message });
      } finally {
        inFlightFetch = null;
      }
    })();

    return inFlightFetch;
  },

  openUpgradeModal: (feature) => set({ upgradeModalOpen: true, upgradeModalFeature: feature }),
  closeUpgradeModal: () => set({ upgradeModalOpen: false, upgradeModalFeature: null }),
}));

// @audit-fixed: when the auth store fires `bizarre-crm:auth-cleared` (logout or
// forced session-clear) wipe per-tenant plan state so the next sign-in does not
// inherit the previous tenant's plan/usage. Without this, switching shops in the
// same browser tab would still show the OLD tenant's feature gates until the
// first /account/usage round-trip completed.
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => {
    inFlightFetch = null;
    usePlanStore.setState({
      plan: 'free',
      planName: 'Free',
      priceCents: 0,
      trialActive: false,
      trialEndsAt: null,
      usage: null,
      features: DEFAULT_FEATURES,
      isLoading: false,
      hasFetched: false,
      error: null,
      upgradeModalOpen: false,
      upgradeModalFeature: null,
    });
  });
}
