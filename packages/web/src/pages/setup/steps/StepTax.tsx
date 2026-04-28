import { useEffect, useState } from 'react';
import type { JSX } from 'react';
import { ArrowLeft, ArrowRight, Calculator, Info } from 'lucide-react';
import type { StepProps, PendingWrites } from '../wizardTypes';

/**
 * Step 8 — Tax defaults.
 *
 * Two tax categories — that's the canonical split for repair-shop sales tax
 * across US jurisdictions:
 *
 *   1. PARTS / PHYSICAL GOODS — taxable in nearly every sales-tax state as
 *      tangible personal property. Includes screens, batteries, charge
 *      ports, accessories (cases / cables / chargers), and any over-the-
 *      counter inventory the shop sells.
 *
 *   2. LABOR / SERVICES — taxability VARIES by state:
 *        • Most states (CA, ID, etc.): non-taxable when itemized separately
 *          on the invoice.
 *        • NY, HI, SD, NM, WV: labor on a repair sale IS taxable, often
 *          when bundled with parts.
 *      Owners default labor to 0% if their state doesn't tax labor.
 *
 * Accessories are NOT a separate tax category — they get the same physical-
 * goods treatment as parts. Older revisions of this step exposed a third
 * "Accessories" rate; collapsed into "Parts" here. Existing installs that
 * had a non-default `tax_default_accessories` value get a one-time merge
 * onto `tax_default_parts` via the helper below.
 *
 * Sources (researched 2026-04-28):
 *   - Avalara state-by-state services taxability whitepaper
 *   - NCDOR Repair / Maintenance / Installation guide
 *   - CDTFA Pub 108 (CA non-taxable labor)
 *   - NY Tax — Auto Repair (taxable bundle)
 *   - Idaho State Tax Commission — Repair Shops
 */

const DEFAULT_GOODS_RATE = '8.25';
// Most states don't tax labor — default 0% and the owner explicitly raises
// it if they're in NY/HI/SD/NM/WV. Wrong default would silently overcharge
// every customer until someone notices.
const DEFAULT_LABOR_RATE = '0.00';

interface CategoryRow {
  key: keyof Pick<PendingWrites, 'tax_default_parts' | 'tax_default_services'>;
  label: string;
  description: string;
  defaultRate: string;
  hint: string;
}

const CATEGORIES: ReadonlyArray<CategoryRow> = [
  {
    key: 'tax_default_parts',
    label: 'Parts & physical goods',
    description: 'Screens, batteries, charge ports, accessories, cases, cables — anything tangible the customer takes home.',
    defaultRate: DEFAULT_GOODS_RATE,
    hint: 'Taxable in nearly every US sales-tax state.',
  },
  {
    key: 'tax_default_services',
    label: 'Labor & services',
    description: 'Repair labor, diagnostics, software fixes — work performed, no tangible item changes hands.',
    defaultRate: DEFAULT_LABOR_RATE,
    hint: 'Default 0%. Set higher only if your state taxes labor (NY, HI, SD, NM, WV).',
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
  // Fold any legacy `tax_default_accessories` value into the goods/parts seed
  // — both buckets historically held the same rate, so we prefer the parts
  // value if present, otherwise the accessories value, otherwise the default.
  const initialParts =
    pending.tax_default_parts ??
    pending.tax_default_accessories ??
    DEFAULT_GOODS_RATE;
  const initialServices = pending.tax_default_services ?? DEFAULT_LABOR_RATE;

  const [parts, setParts] = useState<string>(initialParts);
  const [services, setServices] = useState<string>(initialServices);

  // Persist on every change so going Back/Next or hitting Skip carries the
  // current values into the wizard's bulk PUT at completion. Mirror to the
  // legacy accessories key so any other surface that still reads it sees
  // the same rate (= goods/parts).
  useEffect(() => {
    onUpdate({
      tax_default_parts: parts,
      tax_default_services: services,
      tax_default_accessories: parts,
    });
    // onUpdate identity may shift each render — value-driven sync only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [parts, services]);

  const allValid = isValidRate(parts) && isValidRate(services);

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const setterFor = (key: CategoryRow['key']): ((v: string) => void) =>
    key === 'tax_default_parts' ? setParts : setServices;

  const valueFor = (key: CategoryRow['key']): string =>
    key === 'tax_default_parts' ? parts : services;

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Calculator className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Sales tax
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Two categories cover every line a repair shop sells: physical goods (taxable
          almost everywhere) and labor (state-dependent). Override per-line on any
          invoice. Add more tax classes later in Settings &rarr; Tax.
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {CATEGORIES.map(({ key, label, description, defaultRate, hint }) => {
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
                  placeholder={defaultRate}
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
              <p className="mt-1 inline-flex items-start gap-1 text-[11px] text-surface-500 dark:text-surface-400">
                <Info className="mt-0.5 h-3 w-3 shrink-0" aria-hidden="true" />
                {hint}
              </p>
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
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50"
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
