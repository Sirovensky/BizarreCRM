import { useState, useEffect, type JSX } from 'react';
import { Smartphone, Wrench, Sparkles, Info, Calculator, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { repairPricingApi } from '@/api/endpoints';
import type {
  RepairPricingAutoMarginPreview,
  RepairPricingAutoMarginSettings,
  RepairPricingMatrixResponse,
  RepairPricingSeedDefaultsResponse,
  RepairPricingSeedPricing,
} from '@/api/types';
import { formatApiError } from '@/utils/apiError';
import { formatCurrency } from '@/utils/format';
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
 * Per-device override and auto-margin modes are wired to the same runtime
 * repair-pricing APIs used by Settings, so choices made here immediately
 * become the pricing model the ticket/POS flows consume.
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
    headerClass: 'bg-primary-500 text-on-primary',
  },
  {
    letter: 'b',
    title: 'Tier B — Mainstream',
    subtitle: '3-5 yr models',
    examples: 'iPhone 11-13, S20-S21, Pixel 5-7',
    headerClass: 'bg-primary-200 text-primary-900',
  },
  {
    letter: 'c',
    title: 'Tier C — Legacy',
    subtitle: '6+ yr models',
    examples: 'iPhone X / earlier, S10 / earlier',
    headerClass:
      'bg-surface-200 text-surface-700 dark:bg-surface-700 dark:text-surface-200',
  },
];

const API_TIER_BY_LETTER: Record<TierLetter, ApiTier> = {
  a: 'tier_a',
  b: 'tier_b',
  c: 'tier_c',
};

const SETUP_PRICING_CATEGORY = 'phone';

const DEFAULT_AUTO_MARGIN_SETTINGS: RepairPricingAutoMarginSettings = {
  preset: 'custom',
  target_type: 'percent',
  target_margin_pct: 60,
  target_profit_amount: 80,
  calculation_basis: 'gross_margin',
  rounding_mode: 'off',
  cap_pct: 25,
  rules: [],
};

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

  // Seed defaults into pending on mount so navigating Back preserves the
  // implicit defaults even if the user never touched a field. Only writes keys
  // that are absent from pending (user edits are left intact).
  useEffect(() => {
    const missingKeys = (Object.keys(values) as PricingKey[]).filter(
      (k) => pending[k] === undefined || pending[k] === null,
    );
    if (missingKeys.length > 0) {
      const patch: Partial<PendingWrites> = {};
      for (const k of missingKeys) {
        patch[k] = values[k];
      }
      onUpdate(patch);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Active pricing mode (segmented control at top of card). Only 'tier' is
  // wired through the same runtime APIs as Settings so the wizard can seed,
  // override, or configure automation before the first ticket is created.
  const [mode, setMode] = useState<PricingMode>('tier');
  const [matrixSearch, setMatrixSearch] = useState('');
  const [matrixDrafts, setMatrixDrafts] = useState<Record<string, { value: string; priceId: number | null; serviceId: number; deviceId: number }>>({});
  const [matrixSaving, setMatrixSaving] = useState(false);
  const [autoDraft, setAutoDraft] = useState<RepairPricingAutoMarginSettings | null>(null);
  const [autoPreview, setAutoPreview] = useState<RepairPricingAutoMarginPreview | null>(null);
  const [autoPreviewInput, setAutoPreviewInput] = useState({ supplierCost: '45', currentLabor: '120' });
  const [autoSaving, setAutoSaving] = useState(false);

  const matrixQuery = useQuery({
    queryKey: ['repair-pricing', 'setup-matrix', matrixSearch],
    queryFn: async () => {
      const res = await repairPricingApi.getMatrix({
        category: SETUP_PRICING_CATEGORY,
        q: matrixSearch.trim() || undefined,
        limit: 60,
      });
      return res.data.data as RepairPricingMatrixResponse;
    },
    enabled: mode === 'matrix',
    staleTime: 30_000,
  });

  const autoSettingsQuery = useQuery({
    queryKey: ['repair-pricing', 'auto-margin-settings'],
    queryFn: async () => {
      const res = await repairPricingApi.getAutoMarginSettings();
      return res.data.data;
    },
    enabled: mode === 'auto_margin',
    staleTime: 30_000,
  });

  const autoSettings = autoDraft ?? autoSettingsQuery.data ?? DEFAULT_AUTO_MARGIN_SETTINGS;

  const handleChange = (tier: TierLetter, service: ServiceKey, raw: string) => {
    const k = pricingKey(tier, service);
    const clamped = clampDollars(raw);
    setValues((prev) => ({ ...prev, [k]: clamped }));
    onUpdate({ [k]: clamped } as Partial<PendingWrites>);
  };

  const handleApplyMedians = () => {
    const next = medianValues();
    setValues(next);
    onUpdate(pricingPatch(next));
    toast.success('Industry medians loaded. Continue to seed them on the server.');
  };

  const handleMatrixDraft = (
    deviceId: number,
    serviceId: number,
    priceId: number | null,
    raw: string,
  ) => {
    const value = clampDollars(raw);
    setMatrixDrafts((prev) => ({
      ...prev,
      [`${deviceId}:${serviceId}`]: { value, priceId, serviceId, deviceId },
    }));
  };

  const handleSaveMatrix = async () => {
    const drafts = Object.values(matrixDrafts).filter((draft) => draft.value !== '');
    if (drafts.length === 0) {
      toast('No matrix edits to save.', { icon: 'i' });
      return;
    }
    setMatrixSaving(true);
    try {
      for (const draft of drafts) {
        const labor_price = Number.parseInt(draft.value, 10);
        if (!Number.isFinite(labor_price) || labor_price < 0) {
          throw new Error('Every matrix cell must be a non-negative number.');
        }
        if (draft.priceId) {
          await repairPricingApi.updatePrice(draft.priceId, {
            labor_price,
            is_custom: 1,
            is_active: 1,
          });
        } else {
          await repairPricingApi.createPrice({
            device_model_id: draft.deviceId,
            repair_service_id: draft.serviceId,
            labor_price,
            default_grade: 'A',
            is_active: 1,
            is_custom: 1,
          });
        }
      }
      setMatrixDrafts({});
      await matrixQuery.refetch();
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success(`Saved ${drafts.length} matrix edit${drafts.length === 1 ? '' : 's'}`);
    } catch (err: unknown) {
      toast.error(`Couldn't save matrix edits: ${formatApiError(err)}`);
    } finally {
      setMatrixSaving(false);
    }
  };

  const updateAutoDraft = (patch: Partial<RepairPricingAutoMarginSettings>) => {
    setAutoDraft({ ...autoSettings, ...patch });
    setAutoPreview(null);
  };

  const handlePreviewAutoMargin = async () => {
    try {
      const res = await repairPricingApi.previewAutoMargin({
        ...autoSettings,
        supplier_cost: Number(autoPreviewInput.supplierCost),
        current_labor_price: Number(autoPreviewInput.currentLabor),
      });
      setAutoPreview(res.data.data);
    } catch (err: unknown) {
      toast.error(`Couldn't preview auto-margin: ${formatApiError(err)}`);
    }
  };

  const handleSaveAutoMargin = async () => {
    setAutoSaving(true);
    try {
      const res = await repairPricingApi.setAutoMarginSettings(autoSettings);
      setAutoDraft(res.data.data);
      queryClient.invalidateQueries({ queryKey: ['repair-pricing', 'auto-margin-settings'] });
      toast.success('Auto-margin rules saved');
    } catch (err: unknown) {
      toast.error(`Couldn't save auto-margin rules: ${formatApiError(err)}`);
    } finally {
      setAutoSaving(false);
    }
  };

  const handleRunAutoMargin = async () => {
    setAutoSaving(true);
    try {
      await repairPricingApi.setAutoMarginSettings(autoSettings);
      const res = await repairPricingApi.recomputeProfits({ auto_margin: true });
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      const adjusted = (res.data?.data?.auto_margin?.adjusted ?? 0) as number;
      toast.success(`Auto-margin run complete: ${adjusted} price${adjusted === 1 ? '' : 's'} adjusted`);
    } catch (err: unknown) {
      toast.error(`Couldn't run auto-margin: ${formatApiError(err)}`);
    } finally {
      setAutoSaving(false);
    }
  };

  const handleContinue = async () => {
    // Final flush — guarantees pending matches the visible form before advancing.
    onUpdate(pricingPatch(values));
    setSaving(true);
    try {
      const res = await repairPricingApi.seedDefaults({
        shop_type: pending.shop_type,
        category: pending.shop_type ? 'all' : SETUP_PRICING_CATEGORY,
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

  const MODES: Array<{ id: PricingMode; label: string; badge?: string }> = [
    { id: 'tier', label: 'Tier by model age' },
    { id: 'matrix', label: 'Per-device matrix', badge: `${Object.keys(matrixDrafts).length} edits` },
    { id: 'auto_margin', label: 'Auto-margin rules', badge: autoDraft ? 'Unsaved' : undefined },
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
          per-device matrix edits and auto-margin rules save here too, using the same live pricing
          model available later in Settings.
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
                  'btn btn-sm inline-flex items-center gap-2 !rounded-full px-4 py-1.5 text-sm font-medium transition-colors',
                  active
                    ? 'bg-white text-surface-900 shadow-sm dark:bg-surface-700 dark:text-surface-50'
                    : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
                ].join(' ')}
              >
                {m.label}
                {m.badge && (
                  <span className="rounded-full bg-amber-200 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-amber-900 dark:bg-amber-700 dark:text-amber-100">
                    {m.badge}
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
                  <Calculator className="h-3.5 w-3.5" aria-hidden="true" />Profit varies
                </span>
                <p className="mt-0.5 text-[10px] font-normal uppercase tracking-wide opacity-75">
                  by parts cost
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

      {mode === 'matrix' && (() => {
        const matrix = matrixQuery.data;
        const services = (matrix?.services ?? []) as Array<{ id: number; name: string; slug: string }>;
        return (
          <div className="rounded-xl border border-surface-200 bg-white p-5 dark:border-surface-700 dark:bg-surface-800">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <h3 className="text-base font-semibold text-surface-900 dark:text-surface-50">
                  Per-device matrix
                </h3>
                <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
                  Edit individual model/service labor prices. Saved cells become custom runtime prices.
                </p>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <input
                  type="search"
                  value={matrixSearch}
                  onChange={(e) => setMatrixSearch(e.target.value)}
                  placeholder="Search device or maker"
                  className="w-56 rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
                />
                <button
                  type="button"
                  onClick={handleSaveMatrix}
                  disabled={matrixSaving || Object.keys(matrixDrafts).length === 0}
                  className="btn btn-md inline-flex items-center gap-2 rounded-lg bg-primary-500 px-4 py-2 text-sm font-semibold text-on-primary hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {matrixSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Wrench className="h-4 w-4" />}
                  Save matrix edits
                </button>
              </div>
            </div>

            {matrixQuery.isLoading ? (
              <div className="flex items-center justify-center py-12 text-sm text-surface-500">
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Loading matrix
              </div>
            ) : matrixQuery.isError ? (
              <div className="mt-4 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300">
                Could not load the pricing matrix.
              </div>
            ) : !matrix || matrix.devices.length === 0 || services.length === 0 ? (
              <div className="mt-4 rounded-lg border border-surface-200 bg-surface-50 p-4 text-sm text-surface-500 dark:border-surface-700 dark:bg-surface-900/40">
                No active phone devices or repair services found yet.
              </div>
            ) : (
              <div className="mt-4 max-h-[520px] overflow-auto rounded-lg border border-surface-200 dark:border-surface-700">
                <table className="min-w-full text-xs">
                  <thead className="sticky top-0 z-10 bg-surface-100 dark:bg-surface-900">
                    <tr>
                      <th className="sticky left-0 z-20 min-w-56 bg-surface-100 px-3 py-2 text-left font-semibold text-surface-700 dark:bg-surface-900 dark:text-surface-200">
                        Device
                      </th>
                      {services.map((service) => (
                        <th key={service.id} className="min-w-28 px-3 py-2 text-right font-semibold text-surface-700 dark:text-surface-200">
                          {service.name}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
                    {matrix.devices.map((device) => (
                      <tr key={device.device_model_id} className="hover:bg-surface-50 dark:hover:bg-surface-900/50">
                        <td className="sticky left-0 z-10 bg-white px-3 py-2 dark:bg-surface-800">
                          <div className="font-medium text-surface-800 dark:text-surface-100">{device.device_model_name}</div>
                          <div className="mt-0.5 flex items-center gap-2 text-[10px] text-surface-500">
                            <span>{device.manufacturer_name}</span>
                            <span className="rounded-full bg-surface-100 px-1.5 py-0.5 dark:bg-surface-700">{device.tier_label}</span>
                          </div>
                        </td>
                        {services.map((service) => {
                          const price = device.prices.find((p) => p.repair_service_id === service.id);
                          const draft = matrixDrafts[`${device.device_model_id}:${service.id}`];
                          const value = draft?.value ?? (price?.labor_price == null ? '' : String(Math.round(price.labor_price)));
                          const profit = price?.profit_estimate;
                          return (
                            <td key={service.id} className="px-2 py-2 text-right">
                              <div className="flex flex-col items-end gap-1">
                                <input
                                  type="number"
                                  min={0}
                                  max={9999}
                                  value={value}
                                  onChange={(e) => handleMatrixDraft(device.device_model_id, service.id, price?.price_id ?? null, e.target.value)}
                                  aria-label={`${device.device_model_name} ${service.name} labor price`}
                                  className="h-8 w-24 rounded-md border border-surface-200 bg-white px-2 text-right text-xs text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-500/30 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
                                />
                                <span className="text-[10px] text-surface-400">
                                  {price?.is_custom ? 'Custom' : 'Tier'}{profit != null ? ` · ${formatCurrency(profit)} profit` : ''}
                                </span>
                              </div>
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        );
      })()}

      {mode === 'auto_margin' && (
      <div className="rounded-xl border border-surface-200 bg-white p-5 dark:border-surface-700 dark:bg-surface-800">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h3 className="text-base font-semibold text-surface-900 dark:text-surface-50">
              Auto-margin rules
            </h3>
            <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
              Save the target margin and rounding rules used by the server auto-margin job.
            </p>
          </div>
          {autoSettingsQuery.isLoading ? (
            <span className="inline-flex items-center gap-2 text-xs text-surface-500">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              Loading rules
            </span>
          ) : null}
        </div>

        <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-3">
          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Preset</span>
            <select
              value={autoSettings.preset}
              onChange={(e) => updateAutoDraft({ preset: e.target.value as RepairPricingAutoMarginSettings['preset'] })}
              className="mt-1.5 w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
            >
              <option value="custom">Custom</option>
              <option value="high_traffic">High traffic</option>
              <option value="mid_traffic">Mid traffic</option>
              <option value="low_traffic">Low traffic</option>
            </select>
          </label>

          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Target type</span>
            <select
              value={autoSettings.target_type}
              onChange={(e) => updateAutoDraft({ target_type: e.target.value as RepairPricingAutoMarginSettings['target_type'] })}
              className="mt-1.5 w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
            >
              <option value="percent">Percent margin</option>
              <option value="fixed_amount">Fixed profit</option>
            </select>
          </label>

          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
              {autoSettings.target_type === 'fixed_amount' ? 'Target profit' : 'Target margin'}
            </span>
            <div className="mt-1.5 flex items-center gap-2">
              <input
                type="number"
                min={0}
                max={autoSettings.target_type === 'fixed_amount' ? 10000 : 95}
                value={autoSettings.target_type === 'fixed_amount' ? autoSettings.target_profit_amount : autoSettings.target_margin_pct}
                onChange={(e) => {
                  const value = Number(e.target.value);
                  if (autoSettings.target_type === 'fixed_amount') updateAutoDraft({ target_profit_amount: value });
                  else updateAutoDraft({ target_margin_pct: value });
                }}
                className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-right text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
              />
              <span className="w-8 text-sm text-surface-500">
                {autoSettings.target_type === 'fixed_amount' ? '$' : '%'}
              </span>
            </div>
          </label>

          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Basis</span>
            <select
              value={autoSettings.calculation_basis}
              onChange={(e) => updateAutoDraft({ calculation_basis: e.target.value as RepairPricingAutoMarginSettings['calculation_basis'] })}
              className="mt-1.5 w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
            >
              <option value="gross_margin">Gross margin</option>
              <option value="markup">Markup</option>
            </select>
          </label>

          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Rounding</span>
            <select
              value={autoSettings.rounding_mode}
              onChange={(e) => updateAutoDraft({ rounding_mode: e.target.value as RepairPricingAutoMarginSettings['rounding_mode'] })}
              className="mt-1.5 w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
            >
              <option value="off">No rounding</option>
              <option value="nearest_dollar">Nearest dollar</option>
              <option value="nearest_5">Round up to nearest $5</option>
              <option value="nearest_10">Round up to nearest $10</option>
              <option value="psychological_99">Round up to nearest $5 minus $0.01</option>
              <option value="psychological_95">Round up to nearest $5 minus $0.05</option>
            </select>
          </label>

          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Nightly cap</span>
            <div className="mt-1.5 flex items-center gap-2">
              <input
                type="number"
                min={0}
                max={100}
                value={autoSettings.cap_pct}
                onChange={(e) => updateAutoDraft({ cap_pct: Number(e.target.value) })}
                className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-right text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
              />
              <span className="w-8 text-sm text-surface-500">%</span>
            </div>
          </label>
        </div>

        <div className="mt-5 rounded-lg border border-surface-200 bg-surface-50 p-4 dark:border-surface-700 dark:bg-surface-900/40">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
            <label className="block">
              <span className="text-xs font-medium text-surface-500">Supplier cost</span>
              <input
                type="number"
                min={0}
                value={autoPreviewInput.supplierCost}
                onChange={(e) => setAutoPreviewInput((prev) => ({ ...prev, supplierCost: e.target.value }))}
                className="mt-1 w-full rounded-md border border-surface-300 bg-white px-2 py-1.5 text-right text-sm dark:border-surface-600 dark:bg-surface-800"
              />
            </label>
            <label className="block">
              <span className="text-xs font-medium text-surface-500">Current labor</span>
              <input
                type="number"
                min={0}
                value={autoPreviewInput.currentLabor}
                onChange={(e) => setAutoPreviewInput((prev) => ({ ...prev, currentLabor: e.target.value }))}
                className="mt-1 w-full rounded-md border border-surface-300 bg-white px-2 py-1.5 text-right text-sm dark:border-surface-600 dark:bg-surface-800"
              />
            </label>
            <button
              type="button"
              onClick={handlePreviewAutoMargin}
              className="btn btn-sm self-end rounded-md border border-surface-300 bg-white px-3 py-1.5 text-sm font-medium text-surface-700 hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200"
            >
              Preview
            </button>
            <div className="self-end text-sm text-surface-600 dark:text-surface-300">
              {autoPreview ? (
                <span>
                  Suggested {formatCurrency(autoPreview.rounded_labor_price)} · profit {formatCurrency(autoPreview.profit_estimate)}
                </span>
              ) : (
                <span>Preview a sample part cost</span>
              )}
            </div>
          </div>
        </div>

        <div className="mt-5 flex flex-wrap items-center justify-end gap-2">
          <button
            type="button"
            onClick={handleSaveAutoMargin}
            disabled={autoSaving}
            className="btn btn-md inline-flex items-center gap-2 rounded-lg border border-surface-300 bg-white px-4 py-2 text-sm font-semibold text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200"
          >
            {autoSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Wrench className="h-4 w-4" />}
            Save rules
          </button>
          <button
            type="button"
            onClick={handleRunAutoMargin}
            disabled={autoSaving}
            className="btn btn-md inline-flex items-center gap-2 rounded-lg bg-primary-500 px-4 py-2 text-sm font-semibold text-on-primary hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {autoSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Calculator className="h-4 w-4" />}
            Save and run now
          </button>
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
            className="btn btn-md inline-flex items-center gap-2 rounded-lg border border-surface-300 bg-white px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <Sparkles className="h-4 w-4" aria-hidden="true" />
            Apply industry medians
          </button>
        </div>
      )}

      <p className="mt-3 text-center text-xs text-surface-400 dark:text-surface-500">
        All three modes write to the same repair-pricing model used by tickets, POS, and Settings.
      </p>

      <div className="mt-8 flex flex-col items-start justify-between gap-3 border-t border-surface-200 pt-5 sm:flex-row sm:items-center dark:border-surface-700">
        <button
          type="button"
          onClick={onBack}
          disabled={saving}
          className="btn btn-lg text-sm font-medium text-surface-600 hover:text-surface-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-100"
        >
          ← Back
        </button>
        <div className="flex items-center gap-3">
          {onSkip ? (
            <button
              type="button"
              onClick={onSkip}
              disabled={saving}
              className="btn btn-lg text-sm font-medium text-surface-500 hover:text-surface-800 hover:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-200"
            >
              Skip this step
            </button>
          ) : null}
          <button
            type="button"
            onClick={handleContinue}
            disabled={saving}
            className="btn btn-lg flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-on-primary shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50"
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
