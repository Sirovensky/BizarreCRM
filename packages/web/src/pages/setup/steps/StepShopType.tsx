/**
 * StepShopType — Setup wizard step (audit section 42, idea 4)
 *
 * Asks the new shop owner what kind of shop they run so the backend can
 * apply a starter template (SMS templates today; repair pricing + device
 * models are a v2 enhancement once a curated seed exists — see the
 * README "Onboarding & Day-1 Experience" section).
 *
 * This step is NON-BLOCKING:
 *   - A "Skip" button lets the user move on without picking anything.
 *   - If they pick a type, we POST /onboarding/set-shop-type. A failure
 *     surfaces a toast but does NOT prevent advancing — the user can
 *     re-run the same pick from Settings later.
 *
 * Wired in by SetupPage via a new 'shopType' wizard phase. The step reuses
 * the shared StepProps shape so the shell can navigate it like any other.
 */
import { useCallback, useState } from 'react';
import {
  Smartphone,
  Layers,
  Gamepad2,
  ArrowRight,
  ArrowLeft,
  Loader2,
  Check,
} from 'lucide-react';
import toast from 'react-hot-toast';
import type { StepProps } from '../wizardTypes';
import { onboardingApi, type OnboardingShopType } from '@/api/endpoints';
import { cn } from '@/utils/cn';

interface ShopTypeOption {
  id: OnboardingShopType;
  label: string;
  description: string;
  /** Concrete seed counts shown on the card so the user knows what they
   *  get day-1. Pulled from the actual seed data in `device-models-seed.ts`
   *  + service-template counts; update whenever those seeds expand. */
  modelCount: number;
  serviceCount: number;
  Icon: typeof Smartphone;
}

// Three mockup-aligned cards (mockups/web-setup-wizard.html#screen-5):
//   Phone repair  (143 models, 11 services) — most common shop type, shown first
//   Multi-device  (236 models, ~30 services) — covers phones + tablets + laptops + consoles
//   Console / PC  (19 models, 4 services)   — niche, thin seed today (DPI-12)
//
// Backend OnboardingShopType enum has four values; the wizard maps onto three
// of them. 'watch_repair' stays in the enum for shops that later flip it from
// Settings, but isn't surfaced in the wizard because the repair-shop universe
// overwhelmingly does phone / multi-device / console-PC.
const SHOP_TYPES: ReadonlyArray<ShopTypeOption> = [
  {
    id: 'phone_repair',
    label: 'Phone repair',
    description: 'iPhones, Androids — screens, batteries, charge ports, water damage, unlocking.',
    modelCount: 143,
    serviceCount: 11,
    Icon: Smartphone,
  },
  {
    id: 'general_electronics',
    label: 'Multi-device',
    description: 'Phones + tablets + laptops + consoles. Pick this if you take in anything customers bring.',
    modelCount: 236,
    serviceCount: 30,
    Icon: Layers,
  },
  {
    id: 'computer_repair',
    label: 'Console / PC',
    description: 'Xbox, PlayStation, Switch, gaming PCs — board-level + peripherals.',
    modelCount: 19,
    serviceCount: 4,
    Icon: Gamepad2,
  },
];

export function StepShopType({ onNext, onBack }: StepProps) {
  const [selected, setSelected] = useState<OnboardingShopType | null>(null);
  const [saving, setSaving] = useState(false);

  const handleContinue = useCallback(async () => {
    if (!selected) {
      onNext();
      return;
    }
    setSaving(true);
    try {
      await onboardingApi.setShopType(selected);
      // Don't await toast — let it dismiss on its own while we advance.
      toast.success('Starter templates installed');
      onNext();
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      toast.error(`Couldn't install starter templates: ${message}. You can pick a type later in Settings.`);
      // Still advance — this step is non-blocking by design.
      onNext();
    } finally {
      setSaving(false);
    }
  }, [selected, onNext]);

  const handleSkip = useCallback(() => {
    onNext();
  }, [onNext]);

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 mt-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Smartphone className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          What kind of shop do you run?
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Drives default seed data — repair categories, services, base prices, device library.
          Pick the closest match. You can change this later in Settings.
        </p>
      </div>

      <div className="space-y-6 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
          {SHOP_TYPES.map(({ id, label, description, modelCount, serviceCount, Icon }) => {
            const isSelected = selected === id;
            return (
              <button
                key={id}
                type="button"
                onClick={() => setSelected(id)}
                className={cn(
                  'flex flex-col gap-3 rounded-xl border-2 p-4 text-left transition-all',
                  isSelected
                    ? 'border-primary-500 bg-primary-50 ring-2 ring-primary-500/20 dark:border-primary-400 dark:bg-primary-500/10'
                    : 'border-surface-200 bg-white hover:border-surface-300 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:hover:border-surface-600 dark:hover:bg-surface-700',
                )}
              >
                <div
                  className={cn(
                    'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg',
                    isSelected
                      ? 'bg-primary-500 text-primary-950'
                      : 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
                  )}
                >
                  {isSelected ? <Check className="h-5 w-5" /> : <Icon className="h-5 w-5" />}
                </div>
                <div className="min-w-0 flex-1">
                  <div
                    className={cn(
                      'text-base font-semibold',
                      isSelected
                        ? 'text-primary-700 dark:text-primary-200'
                        : 'text-surface-900 dark:text-surface-100',
                    )}
                  >
                    {label}
                  </div>
                  <div className="mt-0.5 text-xs leading-relaxed text-surface-500 dark:text-surface-400">
                    {description}
                  </div>
                </div>
                {/* Seed counts. Concrete numbers reduce wizard anxiety —
                    owner sees what they actually get day-1. Thin badge
                    flags categories whose service catalog is still small
                    (DPI-12 expands them in a later release). */}
                <div className="mt-1 flex items-center gap-2 border-t border-surface-100 pt-2 text-[11px] font-medium text-surface-400 dark:border-surface-700 dark:text-surface-500">
                  <span className="font-mono">{modelCount} models</span>
                  <span aria-hidden="true">·</span>
                  <span className="font-mono">{serviceCount} services</span>
                  {serviceCount < 10 ? (
                    <span
                      title="Service templates expand in a later release (DPI-12)"
                      className="ml-auto rounded-full bg-amber-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-amber-900 dark:bg-amber-900/40 dark:text-amber-200"
                    >
                      Thin
                    </span>
                  ) : null}
                </div>
              </button>
            );
          })}
        </div>

        <p className="text-xs text-surface-400 dark:text-surface-500">
          Rich starter content (full per-device pricing, expanded service catalog) ships
          incrementally per the DPI-* roadmap in TODO.md.
        </p>

        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              disabled={saving}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              Skip
            </button>
            <button
              type="button"
              onClick={handleContinue}
              disabled={saving}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              Continue
              {saving ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <ArrowRight className="h-4 w-4" />
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
