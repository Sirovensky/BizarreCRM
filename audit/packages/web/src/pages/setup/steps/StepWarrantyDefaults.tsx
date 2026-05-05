import { useState, type JSX } from 'react';
import { ShieldCheck, FileText } from 'lucide-react';
import type { StepProps, PendingWrites } from '../wizardTypes';

/**
 * Step 22 — Warranty defaults.
 *
 * Five number inputs (months, 0–24) per repair category — Screen, Battery,
 * Charge port, Back glass, Camera — plus a free-text disclaimer that prints
 * on receipts and tickets. `0` = no warranty for that category. Each value
 * is persisted as a string into store_config (matches PendingWrites + the
 * server's ALLOWED_CONFIG_KEYS string contract).
 *
 * Visual layout follows `mockups/web-setup-wizard.html#screen-22`: a card
 * with a 2-column grid of (label + number input + "months" suffix) rows on
 * desktop, single-column on mobile, with a full-width font-mono textarea
 * for the disclaimer below.
 */

interface CategoryDef {
  key: keyof Pick<
    PendingWrites,
    | 'warranty_default_months_screen'
    | 'warranty_default_months_battery'
    | 'warranty_default_months_charge_port'
    | 'warranty_default_months_back_glass'
    | 'warranty_default_months_camera'
  >;
  label: string;
  defaultMonths: number;
}

const CATEGORIES: CategoryDef[] = [
  { key: 'warranty_default_months_screen', label: 'Screen', defaultMonths: 3 },
  { key: 'warranty_default_months_battery', label: 'Battery', defaultMonths: 1 },
  { key: 'warranty_default_months_charge_port', label: 'Charge port', defaultMonths: 1 },
  { key: 'warranty_default_months_back_glass', label: 'Back glass', defaultMonths: 1 },
  { key: 'warranty_default_months_camera', label: 'Camera', defaultMonths: 1 },
];

const DEFAULT_DISCLAIMER =
  'Warranty covers manufacturing defects only. Physical damage, water exposure, and unauthorized repairs void warranty.';

/** Clamp the raw input string to an integer in [0, 24] and stringify it back. */
function clampMonths(raw: string): string {
  if (raw === '') return '';
  const n = Number.parseInt(raw, 10);
  if (Number.isNaN(n)) return '0';
  if (n < 0) return '0';
  if (n > 24) return '24';
  return String(n);
}

export function StepWarrantyDefaults({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  // Initialise each row from pending → fall back to per-category default.
  const [months, setMonths] = useState<Record<CategoryDef['key'], string>>(() => {
    const seed = {} as Record<CategoryDef['key'], string>;
    for (const cat of CATEGORIES) {
      const stored = pending[cat.key];
      seed[cat.key] = stored ?? String(cat.defaultMonths);
    }
    return seed;
  });
  const [disclaimer, setDisclaimer] = useState<string>(
    pending.warranty_disclaimer ?? DEFAULT_DISCLAIMER,
  );

  const handleMonthsChange = (key: CategoryDef['key'], raw: string) => {
    const clamped = clampMonths(raw);
    setMonths((prev) => ({ ...prev, [key]: clamped }));
    onUpdate({ [key]: clamped } as Partial<PendingWrites>);
  };

  const handleDisclaimerChange = (value: string) => {
    setDisclaimer(value);
    onUpdate({ warranty_disclaimer: value });
  };

  const handleContinue = () => {
    // Final flush — guarantees pending matches the visible form before advancing.
    const patch: Partial<PendingWrites> = {
      warranty_disclaimer: disclaimer,
    };
    for (const cat of CATEGORIES) {
      patch[cat.key] = months[cat.key];
    }
    onUpdate(patch);
    onNext();
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <ShieldCheck className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Warranty defaults
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Default coverage by repair category. Set <code className="font-mono">0</code> to disable
          warranty for that category. Per-ticket overrides happen at intake.
        </p>
      </div>

      <div className="mx-auto max-w-2xl rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {CATEGORIES.map((cat) => (
            <div
              key={cat.key}
              className="flex items-center justify-between gap-3 rounded-xl border border-surface-200 bg-surface-50 px-4 py-3 dark:border-surface-700 dark:bg-surface-900/40"
            >
              <label
                htmlFor={`warranty-${cat.key}`}
                className="flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-200"
              >
                <ShieldCheck
                  className="h-4 w-4 text-primary-600 dark:text-primary-400"
                  aria-hidden="true"
                />
                {cat.label}
              </label>
              <div className="flex items-center gap-2">
                <input
                  id={`warranty-${cat.key}`}
                  type="number"
                  inputMode="numeric"
                  min={0}
                  max={24}
                  step={1}
                  value={months[cat.key]}
                  onChange={(e) => handleMonthsChange(cat.key, e.target.value)}
                  className="w-20 rounded-lg border border-surface-300 bg-white px-3 py-2 text-right text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
                <span className="text-xs font-medium text-surface-500 dark:text-surface-400">
                  months
                </span>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-6">
          <label
            htmlFor="warranty-disclaimer"
            className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300"
          >
            <FileText className="h-4 w-4 text-surface-500 dark:text-surface-400" aria-hidden="true" />
            Warranty disclaimer
          </label>
          <textarea
            id="warranty-disclaimer"
            rows={4}
            value={disclaimer}
            onChange={(e) => handleDisclaimerChange(e.target.value)}
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 font-mono text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
          <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
            Printed on every receipt and ticket. Per-service overrides available later in Settings.
          </p>
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
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400"
            >
              Continue
              <ShieldCheck className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepWarrantyDefaults;
