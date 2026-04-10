import { usePlanStore } from '@/stores/planStore';
import type { PlanFeatures } from '@bizarre-crm/shared';

interface FeatureGate {
  allowed: boolean;
  hasFetched: boolean;
  showUpgradeModal: () => void;
}

/** Hook to check if a feature is allowed for the current tenant's plan.
 *  Returns { allowed, hasFetched, showUpgradeModal }. While `hasFetched` is false,
 *  callers should treat the gate as "loading" rather than denied — otherwise the UI
 *  flashes upgrade prompts on app startup before the plan store is populated. */
export function useFeatureGate(feature: keyof PlanFeatures): FeatureGate {
  const features = usePlanStore((s) => s.features);
  const hasFetched = usePlanStore((s) => s.hasFetched);
  const openUpgradeModal = usePlanStore((s) => s.openUpgradeModal);

  return {
    // Until plan info loads, default to denied — but consumers should check `hasFetched`
    // to render skeletons/spinners instead of upgrade prompts.
    allowed: hasFetched ? features[feature] : false,
    hasFetched,
    showUpgradeModal: () => openUpgradeModal(feature),
  };
}
