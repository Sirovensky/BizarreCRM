import { useEffect, useState } from 'react';
import type { JSX } from 'react';
import { ArrowLeft, ArrowRight, Calculator } from 'lucide-react';
import type { StepProps, PendingWrites } from '../wizardTypes';

/**
 * Step 11 — Tax defaults.
 *
 * Mirrors `#screen-11` in `docs/setup-wizard-preview.html`. The owner sets
 * three default tax rates — one per item category (parts, services,
 * accessories). These rates pre-fill the appropriate tax class when an
 * invoice line item is created. Owners can still override per-line in the
 * invoice editor and add additional tax classes later in Settings → Tax.
 *
 * H1 (linear-flow rewrite): replaces the old `SubStepProps` hub-card form
 * (single name + rate posting to /settings/tax-classes) with the unified
 * `StepProps` contract. Persistence is now deferred — values flow into
 * `pending` via `onUpdate` and the wizard shell flushes them in a single
 * PUT /settings/config at completion. Three percentage inputs default to
 * 8.25% across the board, matching the existing California base rate that
 * the previous single-rate form used.
 */

const DEFAULT_RATE = '8.25';

interface CategoryRow {
  key: keyof Pick<
    PendingWrites,
    'tax_default_parts' | 'tax_default_services' | 'tax_default_accessories'
  >;
  label: string;
  description: string;
}

const CATEGORIES: ReadonlyArray<CategoryRow> = [
  {
    key: 'tax_default_parts',
    label: 'Parts',
    description: 'Screens, batteries, charge ports — physical replacement parts.',
  },
  {
    key: 'tax_default_services',
    label: 'Services',
    description: 'Labor, diagnostics, software fixes — non-physical work.',
  },
  {
    key: 'tax_default_accessories',
    label: 'Accessories',
    description: 'Cases, cables, screen protectors — over-the-counter goods.',
  },
];

function isValidRate(raw: string): boolean {
  if (raw.trim() === '') return false;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 && n <= 100;
}

export function StepTax({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const [parts, setParts] = useState<string>(pending.tax_default_parts ?? DEFAULT_RATE);
  const [services, setServices] = useState<string>(
    pending.tax_default_services ?? DEFAULT_RATE,
  );
  const [accessories, setAccessories] = useState<string>(
    pending.tax_default_accessories ?? DEFAULT_RATE,
  );

  // Persist on every change so going Back/Next or hitting Skip carries the
  // current values into the wizard's bulk PUT at completion.
  useEffect(() => {
    onUpdate({
      tax_default_parts: parts,
      tax_default_services: services,
      tax_default_accessories: accessories,
    });
    // onUpdate identity may shift each render — value-driven sync only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [parts, services, accessories]);

  const allValid =
    isValidRate(parts) && isValidRate(services) && isValidRate(accessories);

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const setterFor = (key: CategoryRow['key']): ((v: string) => void) => {
    if (key === 'tax_default_parts') return setParts;
    if (key === 'tax_default_services') return setServices;
    return setAccessories;
  };

  const valueFor = (key: CategoryRow['key']): string => {
    if (key === 'tax_default_parts') return parts;
    if (key === 'tax_default_services') return services;
    return accessories;
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Calculator className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Sales tax
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Default rates per category. Override per-line on any invoice. Add more
          tax classes later in Settings &rarr; Tax.
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {CATEGORIES.map(({ key, label, description }) => {
          const value = valueFor(key);
          const setValue = setterFor(key);
          const invalid = value !== '' && !isValidRate(value);
          const inputId = `tax-${key}`;
          return (
            <div key={key}>
              <label
                htmlFor={inputId}
                className="block text-sm font-semibold text-surface-900 dark:text-surface-100"
              >
                {label}
              </label>
              <p className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">
                {description}
              </p>
              <div className="relative mt-2">
                <input
                  id={inputId}
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  inputMode="decimal"
                  value={value}
                  onChange={(e) => setValue(e.target.value)}
                  placeholder={DEFAULT_RATE}
                  aria-invalid={invalid}
                  className={
                    invalid
                      ? 'block w-full rounded-lg border border-red-400 bg-white px-4 py-3 pr-12 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-red-500 focus:outline-none focus:ring-2 focus:ring-red-500/20 dark:border-red-500 dark:bg-surface-900 dark:text-surface-100'
                      : 'block w-full rounded-lg border border-surface-300 bg-white px-4 py-3 pr-12 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500'
                  }
                />
                <span className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4 text-sm font-medium text-surface-400">
                  %
                </span>
              </div>
              {invalid ? (
                <p
                  className="mt-1 text-xs text-red-500"
                  role="alert"
                  aria-live="polite"
                >
                  Enter a number between 0 and 100.
                </p>
              ) : null}
            </div>
          );
        })}

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
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip
            </button>
            <button
              type="button"
              onClick={onNext}
              disabled={!allValid}
              className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <ArrowRight className="h-4 w-4" />
              Continue
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepTax;
