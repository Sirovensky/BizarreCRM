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
  upgradeModalOpen: false,
  upgradeModalFeature: null,

  fetchPlan: async () => {
    // De-duplicate concurrent calls — return the in-flight promise instead of racing
    if (inFlightFetch) return inFlightFetch;

    inFlightFetch = (async () => {
      set({ isLoading: true });
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
        });
      } catch {
        set({ isLoading: false, hasFetched: true });
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
      upgradeModalOpen: false,
      upgradeModalFeature: null,
    });
  });
}
