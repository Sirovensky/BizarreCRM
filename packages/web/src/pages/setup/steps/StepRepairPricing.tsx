import { useState, type JSX } from 'react';
import { Smartphone, Wrench, Sparkles, Info, Calculator } from 'lucide-react';
import toast from 'react-hot-toast';
import { WizardBreadcrumb } from '../components/WizardBreadcrumb';
import type { StepProps, PendingWrites } from '../wizardTypes';

/**
 * Step 8 — Repair pricing (tier-based labor matrix).
 *
 * Three side-by-side tier cards (Flagship / Mainstream / Legacy) with five
 * labor inputs each (Screen / Battery / Charge port / Back glass / Camera).
 * Each value is persisted as a string into store_config under
 * `pricing_tier_<a|b|c>_<service>` — matches `PendingWrites` and the
 * server's ALLOWED_CONFIG_KEYS contract.
 *
 * Tier rationale (per `docs/setup-wizard-preview.html#screen-8`):
 *   Tier A (0-2 yr) — flagship profit drivers, premium labor.
 *   Tier B (3-5 yr) — bread-and-butter mainstream volume.
 *   Tier C (6+ yr) — get-in-door pricing, thin labor margin.
 *
 * Per-device override and the per-device matrix view live later in
 * Settings → Repair pricing once DPI-13 lands. Apply industry medians
 * is a stub — future hook into the catalog scraper for live medians.
 */

type ServiceKey = 'screen' | 'battery' | 'charge_port' | 'back_glass' | 'camera';
type TierLetter = 'a' | 'b' | 'c';

type PricingKey =
  | 'pricing_tier_a_screen' | 'pricing_tier_a_battery' | 'pricing_tier_a_charge_port'
  | 'pricing_tier_a_back_glass' | 'pricing_tier_a_camera'
  | 'pricing_tier_b_screen' | 'pricing_tier_b_battery' | 'pricing_tier_b_charge_port'
  | 'pricing_tier_b_back_glass' | 'pricing_tier_b_camera'
  | 'pricing_tier_c_screen' | 'pricing_tier_c_battery' | 'pricing_tier_c_charge_port'
  | 'pricing_tier_c_back_glass' | 'pricing_tier_c_camera';

interface ServiceDef {
  key: ServiceKey;
  label: string;
  defaults: Record<TierLetter, number>;
}

interface TierDef {
  letter: TierLetter;
  title: string;
  subtitle: string;
  examples: string;
  headerClass: string;
  partsCost: number;
}

const SERVICES: ServiceDef[] = [
  { key: 'screen',       label: 'Screen',       defaults: { a: 200, b: 120, c: 80 } },
  { key: 'battery',      label: 'Battery',      defaults: { a: 80,  b: 60,  c: 45 } },
  { key: 'charge_port',  label: 'Charge port',  defaults: { a: 120, b: 90,  c: 70 } },
  { key: 'back_glass',   label: 'Back glass',   defaults: { a: 180, b: 110, c: 70 } },
  { key: 'camera',       label: 'Camera',       defaults: { a: 140, b: 90,  c: 60 } },
];

const TIERS: TierDef[] = [
  {
    letter: 'a',
    title: 'Tier A — Flagship',
    subtitle: '0-2 yr models',
    examples: 'iPhone 14/15/16 series, S22-S24, Pixel 8/9',
    headerClass: 'bg-primary-500 text-primary-950',
    partsCost: 40,
  },
  {
    letter: 'b',
    title: 'Tier B — Mainstream',
    subtitle: '3-5 yr models',
    examples: 'iPhone 11-13, S20-S21, Pixel 5-7',
    headerClass: 'bg-primary-200 text-primary-900',
    partsCost: 30,
  },
  {
    letter: 'c',
    title: 'Tier C — Legacy',
    subtitle: '6+ yr models',
    examples: 'iPhone X / earlier, S10 / earlier',
    headerClass:
      'bg-surface-200 text-surface-700 dark:bg-surface-700 dark:text-surface-200',
    partsCost: 20,
  },
];

/** Build the PendingWrites key for `(tier, service)`. Typed as PricingKey so
 *  the patch object below stays narrowly typed without `as any`. */
function pricingKey(tier: TierLetter, service: ServiceKey): PricingKey {
  return `pricing_tier_${tier}_${service}` as PricingKey;
}

/** Clamp the raw input to a non-negative integer string. Empty stays empty
 *  so the user can clear-and-retype without the cursor jumping. */
function clampDollars(raw: string): string {
  if (raw === '') return '';
  const n = Number.parseInt(raw, 10);
  if (Number.isNaN(n) || n < 0) return '0';
  if (n > 9999) return '9999';
  return String(n);
}

export function StepRepairPricing({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  // Initialise the 15-cell grid from `pending` → fall back to per-tier defaults.
  const [values, setValues] = useState<Record<PricingKey, string>>(() => {
    const seed = {} as Record<PricingKey, string>;
    for (const tier of TIERS) {
      for (const svc of SERVICES) {
        const k = pricingKey(tier.letter, svc.key);
        seed[k] = pending[k] ?? String(svc.defaults[tier.letter]);
      }
    }
    return seed;
  });

  const handleChange = (tier: TierLetter, service: ServiceKey, raw: string) => {
    const k = pricingKey(tier, service);
    const clamped = clampDollars(raw);
    setValues((prev) => ({ ...prev, [k]: clamped }));
    onUpdate({ [k]: clamped } as Partial<PendingWrites>);
  };

  /** Average labor across the 5 services for this tier, minus a fixed parts-cost
   *  assumption — gives the user a back-of-envelope "profit per repair" hint. */
  const profitFor = (tier: TierDef): number => {
    const sum = SERVICES.reduce((acc, svc) => {
      const v = Number.parseInt(values[pricingKey(tier.letter, svc.key)] ?? '0', 10);
      return acc + (Number.isNaN(v) ? 0 : v);
    }, 0);
    const avg = sum / SERVICES.length;
    return Math.max(0, Math.round(avg - tier.partsCost));
  };

  const handleApplyMedians = () => {
    // eslint-disable-next-line no-console
    console.log('[StepRepairPricing] Apply industry medians clicked — DPI-13 not yet wired.');
    toast('Industry medians will load from the catalog scraper once DPI-13 lands.', {
      icon: 'ℹ️',
    });
  };

  const handleContinue = () => {
    // Final flush — guarantees pending matches the visible form before advancing.
    const patch: Partial<PendingWrites> = {};
    for (const tier of TIERS) {
      for (const svc of SERVICES) {
        const k = pricingKey(tier.letter, svc.key);
        patch[k] = values[k];
      }
    }
    onUpdate(patch);
    onNext();
  };

  return (
    <div className="mx-auto max-w-6xl">
      <div className="mb-6 flex justify-center">
        <WizardBreadcrumb
          prevLabel="Step 7 · Import"
          currentLabel="Step 8 · Repair pricing"
          nextLabel="Step 9 · Default statuses"
        />
      </div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Wrench className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Repair pricing
        </h1>
        <p className="mx-auto mt-2 max-w-2xl text-sm text-surface-500 dark:text-surface-400">
          Set labor by model age tier. Newer phones earn premium margins; legacy models stay
          affordable as door-openers. Tweak per-device later in Settings.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        {TIERS.map((tier) => (
          <div
            key={tier.letter}
            className="flex flex-col overflow-hidden rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800"
          >
            <div className={`flex items-start justify-between gap-3 px-5 py-4 ${tier.headerClass}`}>
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <Smartphone className="h-4 w-4 shrink-0" aria-hidden="true" />
                  <p className="truncate text-sm font-bold uppercase tracking-wide">
                    {tier.title}
                  </p>
                </div>
                <p className="mt-0.5 text-xs font-medium opacity-80">{tier.subtitle}</p>
              </div>
              <div className="shrink-0 text-right text-xs font-semibold">
                <span className="inline-flex items-center gap-1">
                  <Calculator className="h-3.5 w-3.5" aria-hidden="true" />≈ ${profitFor(tier)}
                </span>
                <p className="mt-0.5 text-[10px] font-normal uppercase tracking-wide opacity-75">
                  profit / repair
                </p>
              </div>
            </div>

            <div className="border-b border-surface-100 bg-surface-50/60 px-5 py-2 text-[11px] leading-relaxed text-surface-500 dark:border-surface-700 dark:bg-surface-900/40 dark:text-surface-400">
              {tier.examples}
            </div>

            <div className="flex flex-1 flex-col gap-3 px-5 py-4">
              {SERVICES.map((svc) => {
                const k = pricingKey(tier.letter, svc.key);
                const inputId = `pricing-${tier.letter}-${svc.key}`;
                return (
                  <div key={svc.key} className="flex items-center justify-between gap-3">
                    <label
                      htmlFor={inputId}
                      className="text-sm font-medium text-surface-700 dark:text-surface-200"
                    >
                      {svc.label}
                    </label>
                    <div className="relative w-28">
                      <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">
                        $
                      </span>
                      <input
                        id={inputId}
                        type="number"
                        inputMode="numeric"
                        min={0}
                        max={9999}
                        step={1}
                        value={values[k]}
                        onChange={(e) => handleChange(tier.letter, svc.key, e.target.value)}
                        className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 pl-6 text-right text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      <div className="mt-5 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-200">
        <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
        <p>
          <span className="font-semibold">💡 Per-device override available later in Settings →
          Repair pricing → Matrix.</span>{' '}
          These are starting defaults — every device's actual price can be tweaked individually.
        </p>
      </div>

      <div className="mt-4 flex justify-center">
        <button
          type="button"
          onClick={handleApplyMedians}
          className="inline-flex items-center gap-2 rounded-lg border border-surface-300 bg-white px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
        >
          <Sparkles className="h-4 w-4" aria-hidden="true" />
          Apply industry medians
        </button>
      </div>

      <div className="mt-8 flex flex-col items-start justify-between gap-3 border-t border-surface-200 pt-5 sm:flex-row sm:items-center dark:border-surface-700">
        <button
          type="button"
          onClick={onBack}
          className="text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
        >
          ← Back
        </button>
        <div className="flex items-center gap-3">
          {onSkip ? (
            <button
              type="button"
              onClick={onSkip}
              className="text-sm font-medium text-surface-500 hover:text-surface-800 hover:underline dark:text-surface-400 dark:hover:text-surface-200"
            >
              Skip
            </button>
          ) : null}
          <button
            type="button"
            onClick={handleContinue}
            className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
          >
            Continue
            <Wrench className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

export default StepRepairPricing;
