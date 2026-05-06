/**
 * StepShopType — Setup wizard step (audit section 42, idea 4)
 *
 * Asks the new shop owner what kind of shop they run so the backend can
 * apply a starter template covering starter SMS templates, repair services,
 * intake/QC defaults, device-library coverage, and pricing hints.
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
  Tablet,
  Laptop,
  Layers,
  Gamepad2,
  Tv,
  ArrowRight,
  ArrowLeft,
  Loader2,
  Check,
} from 'lucide-react';
import toast from 'react-hot-toast';
import type { StepProps } from '../wizardTypes';
import { onboardingApi, type OnboardingShopType } from '@/api/endpoints';
import { cn } from '@/utils/cn';

type SetupShopType = Exclude<OnboardingShopType, 'watch_repair'>;

interface ShopTypeOption {
  id: SetupShopType;
  label: string;
  description: string;
  modelCountLabel: string;
  serviceCountLabel: string;
  Icon: typeof Smartphone;
}

// Electronics-only presets. Auto, jewelry, appliance, and trade/field-service
// verticals are intentionally out of scope until the core electronics workflow
// is stronger.
const SHOP_TYPES: ReadonlyArray<ShopTypeOption> = [
  {
    id: 'phone_repair',
    label: 'Phone repair',
    description: 'iPhones and Androids with display, battery, charging, camera, liquid, and small-part workflows.',
    modelCountLabel: '174 models',
    serviceCountLabel: '21 service families',
    Icon: Smartphone,
  },
  {
    id: 'phone_tablet_repair',
    label: 'Phone + tablet',
    description: 'Phone shops that also take iPads, Galaxy Tabs, Surface tablets, school devices, and stylus cases.',
    modelCountLabel: '213 models',
    serviceCountLabel: '34 service families',
    Icon: Tablet,
  },
  {
    id: 'computer_repair',
    label: 'Computer / IT bench',
    description: 'Laptops, desktops, tune-ups, data work, malware, upgrades, displays, keyboards, and DC jacks.',
    modelCountLabel: '45 models',
    serviceCountLabel: '38 service families',
    Icon: Laptop,
  },
  {
    id: 'console_gaming',
    label: 'Console / gaming',
    description: 'PlayStation, Xbox, Switch, Steam Deck, controllers, ports, thermals, storage, and handheld screens.',
    modelCountLabel: '19 models',
    serviceCountLabel: '18 service families',
    Icon: Gamepad2,
  },
  {
    id: 'tv_consumer_electronics',
    label: 'TV / electronics',
    description: 'TVs, monitors, projectors, sound devices, power faults, backlights, boards, inputs, and remotes.',
    modelCountLabel: '31 models',
    serviceCountLabel: '17 service families',
    Icon: Tv,
  },
  {
    id: 'general_electronics',
    label: 'Multi-device',
    description: 'The full electronics counter: phones, tablets, computers, consoles, TVs, monitors, and odd devices.',
    modelCountLabel: '308 models',
    serviceCountLabel: '100+ service families',
    Icon: Layers,
  },
];

export function StepShopType({ onNext, onBack, onUpdate }: StepProps) {
  const [selected, setSelected] = useState<SetupShopType | null>(null);
  const [saving, setSaving] = useState(false);

  const handleContinue = useCallback(async () => {
    if (!selected) {
      onNext();
      return;
    }
    onUpdate({ shop_type: selected });
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
  }, [selected, onNext, onUpdate]);

  const handleSkip = useCallback(() => {
    onNext();
  }, [onNext]);

  return (
    <div className="mx-auto max-w-5xl">
      <div className="mb-6 mt-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Smartphone className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          What kind of shop do you run?
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Installs starter repair services, device library coverage, SMS templates,
          intake defaults, and dynamic-pricing seed hints. Pick the closest match.
          You can change this later in Settings.
        </p>
      </div>

      <div className="space-y-6 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
          {SHOP_TYPES.map(({ id, label, description, modelCountLabel, serviceCountLabel, Icon }) => {
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
                {/* Seed counts. Concrete numbers reduce wizard anxiety:
                    owners see what they actually get on day 1. */}
                <div className="mt-1 flex items-center gap-2 border-t border-surface-100 pt-2 text-[11px] font-medium text-surface-400 dark:border-surface-700 dark:text-surface-500">
                  <span className="font-mono">{modelCountLabel}</span>
                  <span aria-hidden="true">·</span>
                  <span className="font-mono">{serviceCountLabel}</span>
                </div>
              </button>
            );
          })}
        </div>

        <p className="text-xs text-surface-400 dark:text-surface-500">
          Pricing seeds are supplier-aware hints and labor fallbacks. They do not copy
          a static price sheet or overwrite owner-edited pricing.
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
