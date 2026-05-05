import { useState, type JSX } from 'react';
import { Smartphone, Wrench, Sparkles, Info, Calculator, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import { repairPricingApi } from '@/api/endpoints';
import type {
  RepairPricingSeedDefaultsResponse,
  RepairPricingSeedPricing,
} from '@/api/types';
import { formatApiError } from '@/utils/apiError';
import type { StepProps, PendingWrites } from '../wizardTypes';

type PricingMode = 'tier' | 'matrix' | 'auto_margin';

/**
 * Step 8 — Repair pricing (tier-based labor matrix).
 *
 * Three side-by-side tier cards (Flagship / Mainstream / Legacy) with five
 * labor inputs each (Screen / Battery / Charge port / Back glass / Camera).
 * Each value is kept in wizard session state under
 * `pricing_tier_<a|b|c>_<service>` so Back/refresh do not lose edits. On
 * Continue, the step calls `POST /repair-pricing/seed-defaults`, which fans
 * these values into the server-owned `repair_prices` matrix.
 *
 * Tier rationale (per `mockups/web-setup-wizard.html#screen-8`):
 *   Tier A (0-2 yr) — flagship profit drivers, premium labor.
 *   Tier B (3-5 yr) — bread-and-butter mainstream volume.
 *   Tier C (6+ yr) — get-in-door pricing, thin labor margin.
 *
 * Per-device override and the full virtualized matrix still live in Settings
 * → Repair pricing. This setup step only seeds day-1 tier defaults.
 */

type ServiceKey = 'screen' | 'battery' | 'charge_port' | 'back_glass' | 'camera';
type TierLetter = 'a' | 'b' | 'c';
type ApiTier = 'tier_a' | 'tier_b' | 'tier_c';

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

const API_TIER_BY_LETTER: Record<TierLetter, ApiTier> = {
  a: 'tier_a',
  b: 'tier_b',
  c: 'tier_c',
};

const SETUP_PRICING_CATEGORY = 'phone';

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

function pricingValuesFromPending(pending: PendingWrites): Record<PricingKey, string> {
  const seed = {} as Record<PricingKey, string>;
  for (const tier of TIERS) {
    for (const svc of SERVICES) {
      const k = pricingKey(tier.letter, svc.key);
      seed[k] = pending[k] ?? String(svc.defaults[tier.letter]);
    }
  }
  return seed;
}

function pricingPatch(values: Record<PricingKey, string>): Partial<PendingWrites> {
  const patch: Partial<PendingWrites> = {};
  for (const tier of TIERS) {
    for (const svc of SERVICES) {
      const k = pricingKey(tier.letter, svc.key);
      patch[k] = values[k];
    }
  }
  return patch;
}

function medianValues(): Record<PricingKey, string> {
  const values = {} as Record<PricingKey, string>;
  for (const tier of TIERS) {
    for (const svc of SERVICES) {
      values[pricingKey(tier.letter, svc.key)] = String(svc.defaults[tier.letter]);
    }
  }
  return values;
}

function seedPricingPayload(values: Record<PricingKey, string>): RepairPricingSeedPricing {
  const pricing: RepairPricingSeedPricing = {};
  for (const svc of SERVICES) {
    pricing[svc.key] = {};
    for (const tier of TIERS) {
      const parsed = Number.parseInt(values[pricingKey(tier.letter, svc.key)] ?? '0', 10);
      pricing[svc.key]![API_TIER_BY_LETTER[tier.letter]] = Number.isFinite(parsed) ? parsed : 0;
    }
  }
  return pricing;
}

function seedSummaryMessage(result: RepairPricingSeedDefaultsResponse): string {
  const changed = result.summary.inserted + result.summary.updated;
  if (result.summary.services_missing > 0) {
    return `Seeded ${changed} repair price rows; ${result.summary.services_missing} service defaults were missing.`;
  }
  return `Seeded ${changed} repair price rows.`;
}

export function StepRepairPricing({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const queryClient = useQueryClient();
  // Initialise the 15-cell grid from `pending` → fall back to per-tier defaults.
  const [values, setValues] = useState<Record<PricingKey, string>>(() => pricingValuesFromPending(pending));
  const [saving, setSaving] = useState(false);

  // Active pricing mode (segmented control at top of card). Only 'tier' is
  // wired; the other two render PLACEHOLDER content explaining the future
  // surface. User can flip between them to preview what's coming.
  const [mode, setMode] = useState<PricingMode>('tier');

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
    const next = medianValues();
    setValues(next);
    onUpdate(pricingPatch(next));
    toast.success('Industry medians loaded. Continue to seed them on the server.');
  };

  const handleContinue = async () => {
    // Final flush — guarantees pending matches the visible form before advancing.
    onUpdate(pricingPatch(values));
    setSaving(true);
    try {
      const res = await repairPricingApi.seedDefaults({
        category: SETUP_PRICING_CATEGORY,
        pricing: seedPricingPayload(values),
        overwrite_custom: false,
      });
      const seeded = res.data.data as RepairPricingSeedDefaultsResponse;
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success(seedSummaryMessage(seeded));
      onNext();
    } catch (err: unknown) {
      toast.error(`Couldn't seed repair pricing: ${formatApiError(err)}`);
    } finally {
      setSaving(false);
    }
  };

  const MODES: Array<{ id: PricingMode; label: string; placeholder: boolean; ticket?: string }> = [
    { id: 'tier', label: 'Tier by model age', placeholder: false },
    { id: 'matrix', label: 'Per-device matrix', placeholder: true, ticket: 'DPI-11' },
    { id: 'auto_margin', label: 'Auto-margin rules', placeholder: true, ticket: 'DPI-7/8/9' },
  ];

  return (
    <div className="mx-auto max-w-6xl">
      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Wrench className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Repair pricing
        </h1>
        <p className="mx-auto mt-2 max-w-2xl text-sm text-surface-500 dark:text-surface-400">
          Pick how you want to price labor. Tier-by-age seeds the server pricing matrix now;
          the per-device matrix and auto-margin controls are preview surfaces for Settings.
        </p>
      </div>

      {/* Segmented mode picker (matches mockups/web-setup-wizard.html#screen-8 mockup) */}
      <div className="mb-6 flex justify-center">
        <div className="inline-flex flex-wrap gap-1 rounded-full border border-surface-200 bg-surface-100 p-1 dark:border-surface-700 dark:bg-surface-800">
          {MODES.map((m) => {
            const active = mode === m.id;
            return (
              <button
                key={m.id}
                type="button"
                onClick={() => setMode(m.id)}
                className={[
                  'inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-sm font-medium transition-colors',
                  active
                    ? 'bg-white text-surface-900 shadow-sm dark:bg-surface-700 dark:text-surface-50'
                    : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
                ].join(' ')}
              >
                {m.label}
                {m.placeholder && (
                  <span className="rounded-full bg-amber-200 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-amber-900 dark:bg-amber-700 dark:text-amber-100">
                    Preview
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* ─── Tier mode (the wired one) ─────────────────────────────── */}
      {mode === 'tier' && (
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
      )}

      {/* ─── Tier-mode footer: skip-or-continue helper text ────────── */}
      {mode === 'tier' && (
        <div className="mt-5 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-200">
          <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <p>
            <span className="font-semibold">These are starting defaults.</span>{' '}
            Continue writes them to the server-owned repair pricing matrix for phone devices.
            Existing custom cells stay untouched.
          </p>
        </div>
      )}

      {/* ─── Per-device matrix (PLACEHOLDER) ─────────────────────────
          DPI-11. Real implementation will render a virtualized table of
          ~200 device models × 5 services with bulk-edit + CSV roundtrip. */}
      {mode === 'matrix' && (
      <div className="rounded-xl border-2 border-dashed border-surface-300 bg-surface-50/60 p-5 dark:border-surface-600 dark:bg-surface-900/40">
        <div className="mb-3 flex items-center gap-2">
          <span className="rounded-full bg-amber-200 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-amber-900 dark:bg-amber-700 dark:text-amber-100">
            Placeholder
          </span>
          <span className="text-xs font-medium text-surface-500 dark:text-surface-400">DPI-11</span>
        </div>
        <h3 className="text-base font-semibold text-surface-900 dark:text-surface-50">
          Full per-device matrix
        </h3>
        <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
          Spreadsheet of every model × service. Override the iPhone 15 Pro screen without touching anything else. Bulk-edit, CSV roundtrip, profit heatmap.
        </p>
        <div className="mt-4 overflow-hidden rounded-lg border border-surface-200 bg-white opacity-70 dark:border-surface-700 dark:bg-surface-800">
          <table className="w-full text-xs">
            <thead className="bg-surface-100 dark:bg-surface-900">
              <tr>
                <th className="px-3 py-2 text-left font-semibold text-surface-700 dark:text-surface-200">Device</th>
                <th className="px-3 py-2 text-right font-semibold text-surface-700 dark:text-surface-200">Screen</th>
                <th className="px-3 py-2 text-right font-semibold text-surface-700 dark:text-surface-200">Battery</th>
                <th className="px-3 py-2 text-right font-semibold text-surface-700 dark:text-surface-200">Charge port</th>
                <th className="px-3 py-2 text-right font-semibold text-surface-700 dark:text-surface-200">Back glass</th>
                <th className="px-3 py-2 text-right font-semibold text-surface-700 dark:text-surface-200">Camera</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
              {[
                { d: 'iPhone 15 Pro', vals: [240, 95, 145, 220, 165] },
                { d: 'iPhone 14', vals: [200, 80, 120, 180, 140] },
                { d: 'iPhone 12', vals: [140, 70, 100, 130, 100] },
                { d: 'Galaxy S24', vals: [220, 90, 130, 200, 150] },
                { d: 'Galaxy S20', vals: [125, 65, 90, 110, 90] },
              ].map((row) => (
                <tr key={row.d}>
                  <td className="px-3 py-2 font-medium text-surface-800 dark:text-surface-200">{row.d}</td>
                  {row.vals.map((v, i) => (
                    <td key={i} className="px-3 py-2 text-right text-surface-600 dark:text-surface-400">${v}</td>
                  ))}
                </tr>
              ))}
              <tr>
                <td colSpan={6} className="px-3 py-2 text-center text-[11px] italic text-surface-400">
                  …and ~195 more rows
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <button
          type="button"
          disabled
          aria-disabled="true"
          className="mt-4 cursor-not-allowed rounded-lg border border-surface-300 bg-white px-4 py-2 text-xs font-medium text-surface-400 dark:border-surface-600 dark:bg-surface-800"
        >
          Open full matrix (coming soon)
        </button>
      </div>
      )}

      {/* ─── Auto-margin rules (PLACEHOLDER) ─────────────────────────
          DPI-7..DPI-9. Real implementation will let the shop pick a
          target margin (% or $-over-parts-cost) and recompute labor
          whenever the catalog scraper updates parts pricing. */}
      {mode === 'auto_margin' && (
      <div className="rounded-xl border-2 border-dashed border-surface-300 bg-surface-50/60 p-5 dark:border-surface-600 dark:bg-surface-900/40">
        <div className="mb-3 flex items-center gap-2">
          <span className="rounded-full bg-amber-200 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-amber-900 dark:bg-amber-700 dark:text-amber-100">
            Placeholder
          </span>
          <span className="text-xs font-medium text-surface-500 dark:text-surface-400">DPI-7 / 8 / 9</span>
        </div>
        <h3 className="text-base font-semibold text-surface-900 dark:text-surface-50">
          Auto-margin rules
        </h3>
        <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
          Set a target margin %, choose rounding to .99, whole dollar, or .98, and the server recalculates pricing whenever supplier costs change.
        </p>
        <div className="mt-4 grid grid-cols-1 gap-3 opacity-70 sm:grid-cols-2">
          <div className="rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-800">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Rounding</p>
            <select disabled aria-disabled="true" className="mt-1.5 w-full cursor-not-allowed rounded-md border border-surface-200 bg-surface-50 px-2 py-1.5 text-sm text-surface-500 dark:border-surface-600 dark:bg-surface-900">
              <option>Round up to .99</option>
              <option>Round up to $1</option>
              <option>Round up to .98</option>
            </select>
          </div>
          <div className="rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-800">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Target</p>
            <div className="mt-1.5 flex items-center gap-2">
              <input
                type="text"
                value="60"
                disabled
                aria-disabled="true"
                className="w-20 cursor-not-allowed rounded-md border border-surface-200 bg-surface-50 px-2 py-1.5 text-right text-sm text-surface-500 dark:border-surface-600 dark:bg-surface-900"
              />
              <span className="text-sm text-surface-500">%</span>
            </div>
          </div>
        </div>
        <div className="mt-3 flex items-center justify-between gap-3">
          <p className="text-[11px] text-surface-500 dark:text-surface-400">
            Re-runs whenever the daily catalog scraper finds a parts-cost change.
          </p>
          <label className="flex items-center gap-2 text-xs font-medium text-surface-400">
            <input type="checkbox" disabled aria-disabled="true" className="cursor-not-allowed" />
            Enable auto-margin (coming soon)
          </label>
        </div>
      </div>
      )}

      {/* Tier-mode bonus action: reset the editable grid to server day-1 medians. */}
      {mode === 'tier' && (
        <div className="mt-4 flex justify-center">
          <button
            type="button"
            onClick={handleApplyMedians}
            disabled={saving}
            className="inline-flex items-center gap-2 rounded-lg border border-surface-300 bg-white px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <Sparkles className="h-4 w-4" aria-hidden="true" />
            Apply industry medians
          </button>
        </div>
      )}

      <p className="mt-3 text-center text-xs text-surface-400 dark:text-surface-500">
        Per-device matrix + Auto-margin are backed by server routes; the full wizard editor remains tracked in TODO.md.
      </p>

      <div className="mt-8 flex flex-col items-start justify-between gap-3 border-t border-surface-200 pt-5 sm:flex-row sm:items-center dark:border-surface-700">
        <button
          type="button"
          onClick={onBack}
          disabled={saving}
          className="text-sm font-medium text-surface-600 hover:text-surface-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-100"
        >
          ← Back
        </button>
        <div className="flex items-center gap-3">
          {onSkip ? (
            <button
              type="button"
              onClick={onSkip}
              disabled={saving}
              className="text-sm font-medium text-surface-500 hover:text-surface-800 hover:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-200"
            >
              Skip
            </button>
          ) : null}
          <button
            type="button"
            onClick={handleContinue}
            disabled={saving}
            className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {saving ? 'Seeding pricing' : 'Continue'}
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Wrench className="h-4 w-4" />}
          </button>
        </div>
      </div>
    </div>
  );
}

export default StepRepairPricing;
