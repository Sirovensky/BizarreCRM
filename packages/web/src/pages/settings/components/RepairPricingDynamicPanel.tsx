import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  AlertTriangle,
  Bell,
  Calculator,
  Check,
  History,
  Loader2,
  RefreshCcw,
  RotateCcw,
  Save,
  Search,
  Settings2,
  SlidersHorizontal,
  Wrench,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { repairPricingApi, settingsApi } from '@/api/endpoints';
import type {
  RepairPricingAuditRow,
  RepairPricingAutoMarginPreview,
  RepairPricingAutoMarginSettings,
  RepairPricingMatrixDevice,
  RepairPricingMatrixPrice,
  RepairPricingMatrixResponse,
  RepairPricingMatrixService,
  RepairPricingRoundingMode,
  RepairPricingTier,
  RepairPricingTierApplyResult,
} from '@/api/types';
import { confirm } from '@/stores/confirmStore';
import { formatApiError } from '@/utils/apiError';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate, formatDateTime, formatNumber, timeAgo } from '@/utils/format';

type EditableTier = Exclude<RepairPricingTier, 'unknown'>;
type PresentableTier = EditableTier | 'unknown';

const CATEGORY_OPTIONS = ['phone', 'tablet', 'laptop', 'console', 'tv', 'it_service', 'other'];

function categoryLabel(category: string): string {
  if (category === 'it_service') return 'IT service';
  return category.charAt(0).toUpperCase() + category.slice(1);
}

const EDITABLE_TIERS: Array<{ key: EditableTier; label: string; description: string }> = [
  { key: 'tier_a', label: 'Flagship', description: 'Newest devices' },
  { key: 'tier_b', label: 'Mainstream', description: 'Middle-age devices' },
  { key: 'tier_c', label: 'Legacy', description: 'Older devices' },
];

const PRESENTABLE_TIERS: PresentableTier[] = ['tier_a', 'tier_b', 'tier_c', 'unknown'];

const DEFAULT_TIER_PRESENTATION: Record<PresentableTier, { label: string; color: string }> = {
  tier_a: { label: 'Flagship', color: '#22c55e' },
  tier_b: { label: 'Mainstream', color: '#0ea5e9' },
  tier_c: { label: 'Legacy', color: '#64748b' },
  unknown: { label: 'Unknown', color: '#94a3b8' },
};

function tierConfigSuffix(tier: PresentableTier): string {
  return tier.replace('tier_', '');
}

const ROUNDING_OPTIONS: Array<{ value: RepairPricingRoundingMode; label: string; helper: string }> = [
  { value: 'off', label: 'Off', helper: 'Use exact calculated labor' },
  { value: 'nearest_dollar', label: 'Nearest dollar', helper: 'Round to the nearest whole dollar' },
  { value: 'nearest_5', label: 'Next $5', helper: 'Round up to the next five-dollar step' },
  { value: 'nearest_10', label: 'Next $10', helper: 'Round up to the next ten-dollar step' },
  { value: 'psychological_99', label: '$x4.99 / $x9.99', helper: 'Round up to the next $5 step ending in .99' },
  { value: 'psychological_95', label: '$x4.95 / $x9.95', helper: 'Round up to the next $5 step ending in .95' },
  { value: 'ending_99', label: 'Next .99', helper: 'Legacy mode accepted by the backend' },
  { value: 'ending_98', label: 'Next .98', helper: 'Legacy mode accepted by the backend' },
  { value: 'whole_dollar', label: 'Ceiling dollar', helper: 'Legacy mode: round up to whole dollar' },
  { value: 'none', label: 'None', helper: 'Legacy alias for off' },
];

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

type TierProfitThresholds = Record<'tier_a' | 'tier_b' | 'tier_c' | 'unknown', { green: number; amber: number; red: number }>;

const DEFAULT_TIER_PROFIT_THRESHOLDS: TierProfitThresholds = {
  tier_a: { green: 100, amber: 60, red: 30 },
  tier_b: { green: 80, amber: 40, red: 20 },
  tier_c: { green: 60, amber: 30, red: 10 },
  unknown: { green: 80, amber: 40, red: 20 },
};

function parseTierProfitThresholds(raw: unknown): TierProfitThresholds {
  if (typeof raw !== 'string' || !raw.trim()) return DEFAULT_TIER_PROFIT_THRESHOLDS;
  try {
    const parsed = JSON.parse(raw) as Partial<TierProfitThresholds>;
    const next = { ...DEFAULT_TIER_PROFIT_THRESHOLDS };
    for (const tier of Object.keys(next) as Array<keyof TierProfitThresholds>) {
      const row = parsed[tier];
      if (!row) continue;
      const green = Number(row.green);
      const amber = Number(row.amber);
      const red = Number(row.red);
      next[tier] = {
        green: Number.isFinite(green) ? green : next[tier].green,
        amber: Number.isFinite(amber) ? amber : next[tier].amber,
        red: Number.isFinite(red) ? red : next[tier].red,
      };
    }
    return next;
  } catch {
    return DEFAULT_TIER_PROFIT_THRESHOLDS;
  }
}

function useDebouncedValue<T>(value: T, delay = 250): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const id = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(id);
  }, [value, delay]);

  return debounced;
}

function useWindowedRows<T>(rows: T[], rowHeight = 86, overscan = 8) {
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(560);

  useEffect(() => {
    const node = scrollRef.current;
    if (!node) return;

    const update = () => setViewportHeight(node.clientHeight || 560);
    update();

    if (typeof ResizeObserver !== 'undefined') {
      const observer = new ResizeObserver(update);
      observer.observe(node);
      return () => observer.disconnect();
    }

    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, []);

  const start = Math.max(0, Math.floor(scrollTop / rowHeight) - overscan);
  const visibleCount = Math.ceil(viewportHeight / rowHeight) + overscan * 2;
  const end = Math.min(rows.length, start + visibleCount);
  const visibleRows = rows.slice(start, end).map((row, offset) => ({
    row,
    index: start + offset,
  }));

  return {
    scrollRef,
    onScroll: () => setScrollTop(scrollRef.current?.scrollTop ?? 0),
    visibleRows,
    topPadding: start * rowHeight,
    bottomPadding: Math.max(0, (rows.length - end) * rowHeight),
  };
}

function moneyInput(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(Number(value))) return '';
  const rounded = Math.round(Number(value) * 100) / 100;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2);
}

function parseLaborPrice(value: string): number | null {
  if (value.trim() === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 100000) return null;
  return Math.round(parsed * 100) / 100;
}

function serviceName(service: RepairPricingMatrixService | undefined): string {
  return service?.name ?? 'Selected service';
}

function tierLabel(tier: RepairPricingTier | string | null | undefined): string {
  if (tier === 'tier_a') return 'Flagship';
  if (tier === 'tier_b') return 'Mainstream';
  if (tier === 'tier_c') return 'Legacy';
  return 'Unknown';
}

function numberOrZero(value: number | null | undefined): number {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function Chip({
  children,
  tone = 'surface',
  title,
}: {
  children: ReactNode;
  tone?: 'surface' | 'green' | 'amber' | 'red' | 'blue' | 'purple';
  title?: string;
}) {
  const toneClass = {
    surface: 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300',
    green: 'bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-300',
    amber: 'bg-amber-50 text-amber-700 dark:bg-amber-900/20 dark:text-amber-300',
    red: 'bg-red-50 text-red-700 dark:bg-red-900/20 dark:text-red-300',
    blue: 'bg-blue-50 text-blue-700 dark:bg-blue-900/20 dark:text-blue-300',
    purple: 'bg-purple-50 text-purple-700 dark:bg-purple-900/20 dark:text-purple-300',
  }[tone];

  return (
    <span
      title={title}
      className={cn('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium', toneClass)}
    >
      {children}
    </span>
  );
}

function Panel({
  title,
  description,
  icon,
  action,
  children,
}: {
  title: string;
  description?: string;
  icon?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="rounded-lg border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-900">
      <div className="flex flex-col gap-3 border-b border-surface-100 px-4 py-3 sm:flex-row sm:items-start sm:justify-between dark:border-surface-800">
        <div className="flex min-w-0 items-start gap-3">
          {icon ? <div className="mt-0.5 text-surface-400">{icon}</div> : null}
          <div className="min-w-0">
            <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">{title}</h3>
            {description ? <p className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">{description}</p> : null}
          </div>
        </div>
        {action}
      </div>
      <div className="p-4">{children}</div>
    </section>
  );
}

function SelectField({
  label,
  value,
  onChange,
  children,
  className,
}: {
  label: string;
  value: string | number;
  onChange: (value: string) => void;
  children: ReactNode;
  className?: string;
}) {
  return (
    <label className={cn('block', className)}>
      <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">{label}</span>
      <select
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
      >
        {children}
      </select>
    </label>
  );
}

function CurrencyInput({
  value,
  onChange,
  ariaLabel,
  disabled,
}: {
  value: string;
  onChange: (value: string) => void;
  ariaLabel: string;
  disabled?: boolean;
}) {
  return (
    <div className="relative">
      <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-xs text-surface-400">$</span>
      <input
        type="number"
        min={0}
        max={100000}
        step="0.01"
        value={value}
        disabled={disabled}
        aria-label={ariaLabel}
        onChange={(event) => onChange(event.target.value)}
        className="h-8 w-full rounded-md border border-surface-300 bg-white pl-6 pr-2 text-right text-sm font-medium text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
      />
    </div>
  );
}

function profitChip(price: RepairPricingMatrixPrice | undefined): ReactNode {
  if (!price?.price_id) return <Chip>Missing</Chip>;
  if (price.profit_stale_at) {
    return <Chip tone="amber" title={`Stale since ${formatDateTime(price.profit_stale_at)}`}>Stale</Chip>;
  }
  if (price.profit_estimate == null) return <Chip>No profit</Chip>;
  if (price.profit_estimate < 0) return <Chip tone="red">Loss {formatCurrency(price.profit_estimate)}</Chip>;
  if (price.profit_estimate < 40) return <Chip tone="amber">Low {formatCurrency(price.profit_estimate)}</Chip>;
  return <Chip tone="green">{formatCurrency(price.profit_estimate)} profit</Chip>;
}

function matrixPriceFor(device: RepairPricingMatrixDevice, serviceId: number): RepairPricingMatrixPrice | undefined {
  return device.prices.find((price) => price.repair_service_id === serviceId);
}

function profitTone(price: RepairPricingMatrixPrice | undefined): 'surface' | 'green' | 'amber' | 'red' {
  if (!price?.price_id || price.profit_estimate == null) return 'surface';
  if (price.profit_estimate < 0) return 'red';
  if (price.profit_estimate < 40) return 'amber';
  return 'green';
}

function profitSymbol(price: RepairPricingMatrixPrice | undefined): string {
  const tone = profitTone(price);
  if (tone === 'red') return '▲';
  if (tone === 'amber') return '●';
  if (tone === 'green') return '◆';
  return '';
}

export function RepairPricingStatusStrip() {
  const queryClient = useQueryClient();

  const rebaseQuery = useQuery({
    queryKey: ['repair-pricing', 'rebase-summary'],
    queryFn: async () => {
      const res = await repairPricingApi.getRebaseSummary();
      return res.data.data;
    },
    staleTime: 60_000,
  });

  const marginSummaryQuery = useQuery({
    queryKey: ['repair-pricing', 'margin-alert-summary'],
    queryFn: async () => {
      const res = await repairPricingApi.getMarginAlertSummary();
      return res.data.data;
    },
    staleTime: 60_000,
  });

  const ackRebaseMutation = useMutation({
    mutationFn: () => repairPricingApi.ackRebaseSummary(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['repair-pricing', 'rebase-summary'] });
      toast.success('Rebase summary acknowledged');
    },
    onError: (err: unknown) => toast.error(`Could not acknowledge rebase summary: ${formatApiError(err)}`),
  });

  const summary = rebaseQuery.data;
  const margin = marginSummaryQuery.data;
  const hasUnackedRebase = !!summary && !summary.acked_at;

  return (
    <div className="mb-4 grid grid-cols-1 gap-2 xl:grid-cols-2">
      <div
        className={cn(
          'flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm',
          hasUnackedRebase
            ? 'border-amber-200 bg-amber-50 text-amber-900 dark:border-amber-800 dark:bg-amber-900/20 dark:text-amber-200'
            : 'border-surface-200 bg-white text-surface-600 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300',
        )}
      >
        <span className="inline-flex min-w-0 items-center gap-2">
          <RefreshCcw className="h-4 w-4 shrink-0" />
          {summary ? (
            <span className="truncate">
              Rebase {formatDate(summary.date)}: {formatNumber(summary.device_count)} devices, {formatNumber(summary.crossing_count)} crossings
            </span>
          ) : (
            <span>No tier rebase summary yet</span>
          )}
        </span>
        {hasUnackedRebase ? (
          <button
            type="button"
            onClick={() => ackRebaseMutation.mutate()}
            disabled={ackRebaseMutation.isPending}
            className="btn btn-xs rounded-md bg-white px-2 py-1 text-xs font-semibold text-amber-800 hover:bg-amber-100 disabled:opacity-50 dark:bg-amber-950/40 dark:text-amber-100"
          >
            {ackRebaseMutation.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Check className="h-3 w-3" />}
            Ack
          </button>
        ) : null}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-600 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300">
        <span className="inline-flex items-center gap-2">
          <Bell className="h-4 w-4" />
          Margin alerts
        </span>
        <div className="flex flex-wrap items-center gap-2">
          <Chip tone={margin?.total_active ? 'amber' : 'green'}>{formatNumber(margin?.total_active ?? 0)} active</Chip>
          <Chip tone={margin?.unacked ? 'red' : 'surface'}>{formatNumber(margin?.unacked ?? 0)} unacked</Chip>
          <Chip tone={margin?.critical ? 'red' : 'surface'}>{formatNumber(margin?.critical ?? 0)} critical</Chip>
        </div>
      </div>
    </div>
  );
}

interface MatrixDraft {
  value: string;
  priceId: number | null;
  serviceId: number;
  deviceId: number;
  updatedAt?: string | null;
  supplierCost?: number | null;
}

function MatrixCell({
  device,
  service,
  price,
  draft,
  onDraft,
  onRevert,
  reverting,
  heatmap,
  colorBlind,
}: {
  device: RepairPricingMatrixDevice;
  service: RepairPricingMatrixService;
  price: RepairPricingMatrixPrice | undefined;
  draft: MatrixDraft | undefined;
  onDraft: (draft: MatrixDraft) => void;
  onRevert: (priceId: number) => void;
  reverting: boolean;
  heatmap: boolean;
  colorBlind: boolean;
}) {
  const value = draft?.value ?? moneyInput(price?.labor_price);
  const suggested = price?.suggested_labor_price;
  const hasSuggestion = suggested != null && price?.labor_price != null && Math.abs(suggested - price.labor_price) >= 0.01;
  const tone = profitTone(price);

  return (
    <div
      className={cn(
        'h-[104px] overflow-hidden border-l border-surface-100 p-2 dark:border-surface-800',
        heatmap && tone === 'green' && 'bg-green-50/80 dark:bg-green-950/20',
        heatmap && tone === 'amber' && 'bg-amber-50/80 dark:bg-amber-950/20',
        heatmap && tone === 'red' && 'bg-red-50/80 dark:bg-red-950/20',
      )}
    >
      <div className="flex items-center gap-2">
        <CurrencyInput
          value={value}
          ariaLabel={`${device.manufacturer_name} ${device.device_model_name} ${service.name} labor`}
          onChange={(next) =>
            onDraft({
              value: next,
              priceId: price?.price_id ?? null,
              serviceId: service.id,
              deviceId: device.device_model_id,
              updatedAt: price?.updated_at ?? null,
              supplierCost: price?.last_supplier_cost ?? null,
            })
          }
        />
        {price?.price_id && price.is_custom ? (
          <button
            type="button"
            title="Revert this custom labor price to the tier default"
            onClick={() => onRevert(price.price_id!)}
            disabled={reverting}
            className="btn-icon btn-xs shrink-0 text-surface-400 hover:bg-surface-100 hover:text-primary-600 disabled:opacity-50 dark:hover:bg-surface-800"
          >
            {reverting ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RotateCcw className="h-3.5 w-3.5" />}
          </button>
        ) : null}
      </div>

      <div className="mt-1.5 flex flex-wrap justify-end gap-1">
        {heatmap && colorBlind ? <Chip tone={tone === 'surface' ? 'surface' : tone}>{profitSymbol(price)}</Chip> : null}
        {profitChip(price)}
        {price?.is_custom ? <Chip tone="purple">Custom</Chip> : price?.price_id ? <Chip tone="blue">{tierLabel(price.tier_label)}</Chip> : null}
        {price?.auto_margin_enabled ? <Chip tone="blue">Auto</Chip> : null}
        {hasSuggestion ? <Chip tone="amber">Suggest {formatCurrency(suggested)}</Chip> : null}
      </div>
      {price?.last_supplier_cost != null ? (
        <div className="mt-1 text-right text-[10px] text-surface-400">
          Cost {formatCurrency(price.last_supplier_cost)}
          {price.last_supplier_seen_at ? `, ${timeAgo(price.last_supplier_seen_at)}` : ''}
        </div>
      ) : null}
    </div>
  );
}

export function RepairPricingMatrixSubTab() {
  const queryClient = useQueryClient();
  const [category, setCategory] = useState('phone');
  const [serviceId, setServiceId] = useState<number | ''>('');
  const [search, setSearch] = useState('');
  const [limit, setLimit] = useState(500);
  const [tierFilter, setTierFilter] = useState<RepairPricingTier | 'all'>('all');
  const [showOnlyCustom, setShowOnlyCustom] = useState(false);
  const [showOnlyStale, setShowOnlyStale] = useState(false);
  const [showOnlyMissing, setShowOnlyMissing] = useState(false);
  const [hotOnly, setHotOnly] = useState(false);
  const [heatmap, setHeatmap] = useState(false);
  const [colorBlind, setColorBlind] = useState(false);
  const [sortMode, setSortMode] = useState<'device' | 'avg_profit_asc' | 'avg_profit_desc' | 'labor_asc' | 'labor_desc'>('device');
  const [bulkLabor, setBulkLabor] = useState('');
  const [bulkMultiplier, setBulkMultiplier] = useState('');
  const [drafts, setDrafts] = useState<Record<string, MatrixDraft>>({});
  const [revertingPriceId, setRevertingPriceId] = useState<number | null>(null);
  const importInputRef = useRef<HTMLInputElement | null>(null);

  const debouncedSearch = useDebouncedValue(search.trim(), 250);

  const servicesQuery = useQuery({
    queryKey: ['repair-pricing', 'settings-services', category],
    queryFn: async () => {
      const res = await repairPricingApi.getServices({ category });
      return res.data.data as RepairPricingMatrixService[];
    },
    staleTime: 60_000,
  });

  const matrixQuery = useQuery({
    queryKey: ['repair-pricing', 'settings-matrix', category, serviceId || 'all', debouncedSearch, limit, hotOnly],
    queryFn: async () => {
      const res = await repairPricingApi.getMatrix({
        category,
        repair_service_id: serviceId || undefined,
        q: debouncedSearch || undefined,
        limit,
        hot: hotOnly || undefined,
      });
      return res.data.data;
    },
    staleTime: 20_000,
  });

  const saveDraftMutation = useMutation({
    mutationFn: async (allDrafts: MatrixDraft[]) => {
      const updates = allDrafts.map((draft) => {
        const laborPrice = parseLaborPrice(draft.value);
        if (laborPrice == null) {
          throw new Error('Every edited matrix cell needs a non-negative labor price.');
        }
        return {
          device_model_id: draft.deviceId,
          repair_service_id: draft.serviceId,
          labor_price: laborPrice,
          updated_at: draft.updatedAt,
          supplier_cost: draft.supplierCost,
        };
      });
      const res = await repairPricingApi.updateMatrix({ updates });
      return res.data.data;
    },
    onSuccess: (result) => {
      setDrafts({});
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      const count = result.inserted + result.updated;
      toast.success(`Saved ${count} matrix edit${count === 1 ? '' : 's'}`);
    },
    onError: (err: unknown) => toast.error(`Could not save matrix edits: ${formatApiError(err)}`),
  });

  const importMutation = useMutation({
    mutationFn: async ({ csv, filename }: { csv: string; filename: string }) => {
      const preview = await repairPricingApi.previewMatrixImport({ csv });
      const summary = preview.data.data.summary;
      const ok = await confirm(
        `Import ${filename}? ${summary.insert} new cells, ${summary.update} updates, ${summary.unchanged} unchanged.`,
      );
      if (!ok) return null;
      const commit = await repairPricingApi.commitMatrixImport({ csv, filename });
      return commit.data.data;
    },
    onSuccess: (result) => {
      if (!result) return;
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success(`Imported ${result.inserted + result.updated} matrix cell${result.inserted + result.updated === 1 ? '' : 's'}`);
    },
    onError: (err: unknown) => toast.error(`Could not import matrix CSV: ${formatApiError(err)}`),
  });

  const revertMutation = useMutation({
    mutationFn: (priceId: number) => repairPricingApi.revertToTier(priceId),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success(`Reverted to ${res.data.data.tier_label} via ${res.data.data.default_source.replace('_', ' ')}`);
    },
    onError: (err: unknown) => toast.error(`Could not revert price: ${formatApiError(err)}`),
    onSettled: () => setRevertingPriceId(null),
  });

  const recomputeMutation = useMutation({
    mutationFn: (priceIds: number[]) => repairPricingApi.recomputeProfits({ price_ids: priceIds }),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      const recompute = res.data.data.recompute;
      toast.success(`Profit refresh complete: ${recompute.updated} updated, ${recompute.stale} stale`);
    },
    onError: (err: unknown) => toast.error(`Could not refresh profit estimates: ${formatApiError(err)}`),
  });

  const matrix = matrixQuery.data;
  const services = matrix?.services ?? [];
  const selectedServiceOptions = servicesQuery.data ?? [];

  const filteredDevices = useMemo(() => {
    const devices = matrix?.devices ?? [];
    const serviceIds = services.map((service) => service.id);

    return devices.filter((device) => {
      if (tierFilter !== 'all' && device.tier !== tierFilter) return false;
      const prices = serviceIds.map((id) => matrixPriceFor(device, id)).filter(Boolean) as RepairPricingMatrixPrice[];
      if (showOnlyCustom && !prices.some((price) => price.is_custom)) return false;
      if (showOnlyStale && !prices.some((price) => price.profit_stale_at)) return false;
      if (showOnlyMissing && !serviceIds.some((id) => !matrixPriceFor(device, id)?.price_id)) return false;
      return true;
    }).sort((a, b) => {
      const avgProfit = (device: RepairPricingMatrixDevice) => {
        const values = serviceIds
          .map((id) => matrixPriceFor(device, id)?.profit_estimate)
          .filter((value): value is number => value != null && Number.isFinite(value));
        if (values.length === 0) return Number.POSITIVE_INFINITY;
        return values.reduce((sum, value) => sum + value, 0) / values.length;
      };
      const avgLabor = (device: RepairPricingMatrixDevice) => {
        const values = serviceIds
          .map((id) => matrixPriceFor(device, id)?.labor_price)
          .filter((value): value is number => value != null && Number.isFinite(value));
        if (values.length === 0) return Number.POSITIVE_INFINITY;
        return values.reduce((sum, value) => sum + value, 0) / values.length;
      };
      if (sortMode === 'avg_profit_asc') return avgProfit(a) - avgProfit(b);
      if (sortMode === 'avg_profit_desc') return avgProfit(b) - avgProfit(a);
      if (sortMode === 'labor_asc') return avgLabor(a) - avgLabor(b);
      if (sortMode === 'labor_desc') return avgLabor(b) - avgLabor(a);
      return `${a.manufacturer_name} ${a.device_model_name}`.localeCompare(`${b.manufacturer_name} ${b.device_model_name}`);
    });
  }, [matrix?.devices, services, showOnlyCustom, showOnlyMissing, showOnlyStale, sortMode, tierFilter]);

  const allVisiblePriceIds = useMemo(() => {
    const ids = new Set<number>();
    for (const device of filteredDevices) {
      for (const service of services) {
        const id = matrixPriceFor(device, service.id)?.price_id;
        if (id) ids.add(id);
      }
    }
    return Array.from(ids);
  }, [filteredDevices, services]);

  const metrics = useMemo(() => {
    let custom = 0;
    let stale = 0;
    let missing = 0;
    let lowProfit = 0;

    for (const device of filteredDevices) {
      for (const service of services) {
        const price = matrixPriceFor(device, service.id);
        if (!price?.price_id) {
          missing += 1;
          continue;
        }
        if (price.is_custom) custom += 1;
        if (price.profit_stale_at) stale += 1;
        if (price.profit_estimate != null && price.profit_estimate < 40) lowProfit += 1;
      }
    }

    return { custom, stale, missing, lowProfit };
  }, [filteredDevices, services]);

  const gridTemplateColumns = `240px repeat(${Math.max(services.length, 1)}, minmax(156px, 1fr))`;
  const gridMinWidth = 240 + Math.max(services.length, 1) * 156;
  const windowedRows = useWindowedRows(filteredDevices, 104);
  const hasDrafts = Object.keys(drafts).length > 0;

  const setDraft = (draft: MatrixDraft) => {
    setDrafts((prev) => ({
      ...prev,
      [`${draft.deviceId}:${draft.serviceId}`]: draft,
    }));
  };

  const handleSaveDrafts = async () => {
    const allDrafts = Object.values(drafts);
    if (allDrafts.length === 0) {
      toast('No matrix edits to save.');
      return;
    }

    const ok = await confirm(`Save ${allDrafts.length} custom labor price edit${allDrafts.length === 1 ? '' : 's'}?`);
    if (!ok) return;
    saveDraftMutation.mutate(allDrafts);
  };

  const handleRevert = async (priceId: number) => {
    const ok = await confirm('Revert this custom price back to the current tier default?');
    if (!ok) return;
    setRevertingPriceId(priceId);
    revertMutation.mutate(priceId);
  };

  const handleRefreshProfits = async () => {
    if (allVisiblePriceIds.length === 0) {
      toast('No visible price rows to refresh.');
      return;
    }
    const ok = await confirm(`Refresh supplier-cost profit metadata for ${allVisiblePriceIds.length} visible price row${allVisiblePriceIds.length === 1 ? '' : 's'}?`);
    if (!ok) return;
    recomputeMutation.mutate(allVisiblePriceIds);
  };

  const handleExportCsv = async () => {
    try {
      const res = await repairPricingApi.exportMatrixCsv({ category });
      const blob = new Blob([res.data], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `repair-prices-${category}-${new Date().toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err: unknown) {
      toast.error(`Could not export matrix CSV: ${formatApiError(err)}`);
    }
  };

  const handleImportFile = async (file: File | undefined) => {
    if (!file) return;
    const csv = await file.text();
    importMutation.mutate({ csv, filename: file.name });
    if (importInputRef.current) importInputRef.current.value = '';
  };

  const visibleServiceIds = useMemo(() => services.map((service) => service.id), [services]);

  const handleBulkSetLabor = async () => {
    if (!serviceId) {
      toast.error('Pick a single service before bulk-editing labor.');
      return;
    }
    const laborPrice = parseLaborPrice(bulkLabor);
    if (laborPrice == null) {
      toast.error('Enter a non-negative labor price.');
      return;
    }
    const ok = await confirm(`Set ${formatCurrency(laborPrice)} labor for ${formatNumber(filteredDevices.length)} visible ${categoryLabel(category)} device${filteredDevices.length === 1 ? '' : 's'}?`);
    if (!ok) return;
    const next: Record<string, MatrixDraft> = {};
    for (const device of filteredDevices) {
      const price = matrixPriceFor(device, serviceId);
      next[`${device.device_model_id}:${serviceId}`] = {
        value: moneyInput(laborPrice),
        priceId: price?.price_id ?? null,
        serviceId,
        deviceId: device.device_model_id,
        updatedAt: price?.updated_at ?? null,
        supplierCost: price?.last_supplier_cost ?? null,
      };
    }
    setDrafts((prev) => ({ ...prev, ...next }));
    toast.success(`Prepared ${Object.keys(next).length} bulk edits. Review, then Save.`);
  };

  const handleBulkMultiply = async () => {
    const multiplier = Number(bulkMultiplier);
    if (!Number.isFinite(multiplier) || multiplier <= 0 || multiplier > 10) {
      toast.error('Multiplier must be between 0 and 10.');
      return;
    }
    const targets = filteredDevices.flatMap((device) =>
      visibleServiceIds.map((id) => ({ device, serviceId: id, price: matrixPriceFor(device, id) })),
    ).filter((item) => item.price?.labor_price != null);
    const ok = await confirm(`Multiply ${formatNumber(targets.length)} visible priced cell${targets.length === 1 ? '' : 's'} by ${multiplier}?`);
    if (!ok) return;
    const next: Record<string, MatrixDraft> = {};
    for (const item of targets) {
      const price = item.price!;
      const value = Math.round(Number(price.labor_price) * multiplier * 100) / 100;
      next[`${item.device.device_model_id}:${item.serviceId}`] = {
        value: moneyInput(value),
        priceId: price.price_id ?? null,
        serviceId: item.serviceId,
        deviceId: item.device.device_model_id,
        updatedAt: price.updated_at ?? null,
        supplierCost: price.last_supplier_cost ?? null,
      };
    }
    setDrafts((prev) => ({ ...prev, ...next }));
    toast.success(`Prepared ${Object.keys(next).length} multiplied edits. Review, then Save.`);
  };

  return (
    <div className="space-y-4">
      <Panel
        title="Per-device pricing matrix"
        description="Edit runtime labor by model and service. Saved cells become custom overrides until reverted to tier defaults."
        icon={<Wrench className="h-4 w-4" />}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={handleRefreshProfits}
              disabled={recomputeMutation.isPending || allVisiblePriceIds.length === 0}
              className="btn btn-secondary btn-sm"
            >
              {recomputeMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCcw className="h-3.5 w-3.5" />}
              Refresh profits
            </button>
            <button
              type="button"
              onClick={handleExportCsv}
              className="btn btn-secondary btn-sm"
            >
              Export CSV
            </button>
            <input
              ref={importInputRef}
              type="file"
              accept=".csv,text/csv"
              className="hidden"
              onChange={(event) => handleImportFile(event.target.files?.[0])}
            />
            <button
              type="button"
              onClick={() => importInputRef.current?.click()}
              disabled={importMutation.isPending}
              className="btn btn-secondary btn-sm"
            >
              {importMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
              Import CSV
            </button>
            <button
              type="button"
              onClick={handleSaveDrafts}
              disabled={!hasDrafts || saveDraftMutation.isPending}
              className="btn btn-primary btn-sm"
            >
              {saveDraftMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
              Save {Object.keys(drafts).length || ''} edits
            </button>
          </div>
        }
      >
        <div className="grid grid-cols-1 gap-3 xl:grid-cols-[1fr_auto]">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
            <label className="block md:col-span-2">
              <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Search devices</span>
              <div className="relative mt-1">
                <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                <input
                  type="search"
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Model or manufacturer"
                  className="w-full rounded-md border border-surface-300 bg-white py-2 pl-8 pr-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
                />
              </div>
            </label>
            <SelectField label="Category" value={category} onChange={(value) => { setCategory(value); setServiceId(''); }}>
              {CATEGORY_OPTIONS.map((option) => (
                <option key={option} value={option}>{categoryLabel(option)}</option>
              ))}
            </SelectField>
            <SelectField label="Service" value={serviceId} onChange={(value) => setServiceId(value ? Number(value) : '')}>
              <option value="">All services</option>
              {selectedServiceOptions.map((service) => (
                <option key={service.id} value={service.id}>{service.name}</option>
              ))}
            </SelectField>
            <SelectField label="Tier" value={tierFilter} onChange={(value) => setTierFilter(value as RepairPricingTier | 'all')}>
              <option value="all">All tiers</option>
              <option value="tier_a">Flagship</option>
              <option value="tier_b">Mainstream</option>
              <option value="tier_c">Legacy</option>
              <option value="unknown">Unknown</option>
            </SelectField>
            <SelectField label="Sort" value={sortMode} onChange={(value) => setSortMode(value as typeof sortMode)}>
              <option value="device">Device name</option>
              <option value="avg_profit_asc">Lowest average profit</option>
              <option value="avg_profit_desc">Highest average profit</option>
              <option value="labor_asc">Lowest average labor</option>
              <option value="labor_desc">Highest average labor</option>
            </SelectField>
          </div>

          <div className="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4 xl:w-[640px]">
            <button
              type="button"
              onClick={() => setShowOnlyCustom((value) => !value)}
              className={cn('rounded-md border px-3 py-2 text-left font-medium', showOnlyCustom ? 'border-purple-200 bg-purple-50 text-purple-700 dark:border-purple-900 dark:bg-purple-900/20 dark:text-purple-300' : 'border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300')}
            >
              Custom <span className="block text-sm">{formatNumber(metrics.custom)}</span>
            </button>
            <button
              type="button"
              onClick={() => setShowOnlyStale((value) => !value)}
              className={cn('rounded-md border px-3 py-2 text-left font-medium', showOnlyStale ? 'border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-900 dark:bg-amber-900/20 dark:text-amber-300' : 'border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300')}
            >
              Stale <span className="block text-sm">{formatNumber(metrics.stale)}</span>
            </button>
            <button
              type="button"
              onClick={() => setShowOnlyMissing((value) => !value)}
              className={cn('rounded-md border px-3 py-2 text-left font-medium', showOnlyMissing ? 'border-surface-400 bg-surface-100 text-surface-900 dark:border-surface-500 dark:bg-surface-700 dark:text-surface-100' : 'border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300')}
            >
              Missing <span className="block text-sm">{formatNumber(metrics.missing)}</span>
            </button>
            <div className="rounded-md border border-surface-200 bg-surface-50 px-3 py-2 text-left font-medium text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300">
              Low profit <span className="block text-sm">{formatNumber(metrics.lowProfit)}</span>
            </div>
            <button
              type="button"
              onClick={() => setHotOnly((value) => !value)}
              className={cn('rounded-md border px-3 py-2 text-left font-medium', hotOnly ? 'border-green-200 bg-green-50 text-green-700 dark:border-green-900 dark:bg-green-900/20 dark:text-green-300' : 'border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300')}
            >
              Hot models <span className="block text-sm">{hotOnly ? 'On' : 'Off'}</span>
            </button>
            <button
              type="button"
              onClick={() => setHeatmap((value) => !value)}
              className={cn('rounded-md border px-3 py-2 text-left font-medium', heatmap ? 'border-primary-200 bg-primary-50 text-primary-800 dark:border-primary-500/30 dark:bg-primary-500/10 dark:text-primary-200' : 'border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300')}
            >
              Heatmap <span className="block text-sm">{heatmap ? 'On' : 'Off'}</span>
            </button>
            <button
              type="button"
              onClick={() => setColorBlind((value) => !value)}
              disabled={!heatmap}
              className={cn('rounded-md border px-3 py-2 text-left font-medium disabled:opacity-50', colorBlind && heatmap ? 'border-surface-400 bg-surface-100 text-surface-900 dark:border-surface-500 dark:bg-surface-700 dark:text-surface-100' : 'border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300')}
            >
              Symbols <span className="block text-sm">{colorBlind && heatmap ? 'On' : 'Off'}</span>
            </button>
          </div>
        </div>

        <div className="mt-3 grid grid-cols-1 gap-2 rounded-lg border border-surface-200 bg-surface-50 p-3 text-sm dark:border-surface-700 dark:bg-surface-800 lg:grid-cols-[1fr_1fr_auto]">
          <div className="flex flex-wrap items-end gap-2">
            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Bulk set selected service</span>
              <CurrencyInput value={bulkLabor} ariaLabel="Bulk labor price" onChange={setBulkLabor} />
            </label>
            <button
              type="button"
              onClick={handleBulkSetLabor}
              disabled={!serviceId || filteredDevices.length === 0}
              className="btn btn-secondary btn-sm"
            >
              Apply to visible
            </button>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Bulk multiply visible cells</span>
              <input
                type="text"
                inputMode="decimal"
                value={bulkMultiplier}
                onChange={(event) => setBulkMultiplier(event.target.value.replace(/[^0-9.]/g, ''))}
                placeholder="1.10"
                className="mt-1 w-28 rounded-md border border-surface-300 bg-white px-3 py-2 text-right text-sm dark:border-surface-700 dark:bg-surface-900"
              />
            </label>
            <button
              type="button"
              onClick={handleBulkMultiply}
              disabled={filteredDevices.length === 0 || services.length === 0}
              className="btn btn-secondary btn-sm"
            >
              Multiply
            </button>
          </div>
          <div className="self-end text-xs text-surface-500 dark:text-surface-400">
            Bulk changes are staged as drafts and audited when saved.
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-surface-500 dark:text-surface-400">
          <span>
            Showing {formatNumber(filteredDevices.length)} of {formatNumber(matrix?.devices.length ?? 0)} loaded devices. Limit
          </span>
          <select
            value={limit}
            onChange={(event) => setLimit(Number(event.target.value))}
            className="rounded-md border border-surface-300 bg-white px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-800"
          >
            <option value={250}>250 devices</option>
            <option value={500}>500 devices</option>
            <option value={900}>900 devices</option>
          </select>
        </div>

        {matrixQuery.isLoading ? (
          <div className="flex items-center justify-center py-16 text-sm text-surface-500">
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Loading repair-pricing matrix
          </div>
        ) : matrixQuery.isError ? (
          <div className="mt-4 rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-900/20 dark:text-red-300">
            Could not load the repair-pricing matrix.
          </div>
        ) : !matrix || services.length === 0 || filteredDevices.length === 0 ? (
          <div className="mt-4 rounded-md border border-surface-200 bg-surface-50 p-4 text-sm text-surface-500 dark:border-surface-700 dark:bg-surface-800">
            No matching devices or active services found.
          </div>
        ) : (
          <div
            ref={windowedRows.scrollRef}
            onScroll={windowedRows.onScroll}
            className="mt-4 max-h-[640px] overflow-auto rounded-lg border border-surface-200 dark:border-surface-700"
          >
            <div style={{ minWidth: gridMinWidth }}>
              <div
                className="sticky top-0 z-30 grid border-b border-surface-200 bg-surface-100 text-xs font-semibold text-surface-600 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300"
                style={{ gridTemplateColumns }}
              >
                <div className="sticky left-0 z-40 bg-surface-100 px-3 py-2 dark:bg-surface-900">Device</div>
                {services.map((service) => (
                  <div key={service.id} className="border-l border-surface-200 px-3 py-2 text-right dark:border-surface-700">
                    {service.name}
                  </div>
                ))}
              </div>

              {windowedRows.topPadding > 0 ? <div style={{ height: windowedRows.topPadding }} /> : null}

              {windowedRows.visibleRows.map(({ row: device, index }) => (
                <div
                  key={device.device_model_id}
                  className={cn(
                    'grid border-b border-surface-100 text-sm dark:border-surface-800',
                    index % 2 === 0 ? 'bg-white dark:bg-surface-950' : 'bg-surface-50/50 dark:bg-surface-900/70',
                  )}
                  style={{ gridTemplateColumns }}
                >
                  <div className="sticky left-0 z-20 h-[104px] overflow-hidden bg-inherit px-3 py-2 shadow-[1px_0_0_rgba(148,163,184,0.25)]">
                    <div className="font-medium text-surface-900 dark:text-surface-100">{device.device_model_name}</div>
                    <div className="mt-1 flex flex-wrap items-center gap-1 text-[11px] text-surface-500">
                      <span>{device.manufacturer_name}</span>
                      {device.release_year ? <span>{device.release_year}</span> : null}
                      <Chip tone={device.tier === 'unknown' ? 'surface' : 'blue'}>{device.tier_label}</Chip>
                      {device.is_popular ? <Chip tone="green">Popular</Chip> : null}
                    </div>
                  </div>
                  {services.map((service) => {
                    const price = matrixPriceFor(device, service.id);
                    const key = `${device.device_model_id}:${service.id}`;
                    return (
                      <MatrixCell
                        key={service.id}
                        device={device}
                        service={service}
                        price={price}
                        draft={drafts[key]}
                        onDraft={setDraft}
                        onRevert={handleRevert}
                        reverting={revertingPriceId === price?.price_id}
                        heatmap={heatmap}
                        colorBlind={colorBlind}
                      />
                    );
                  })}
                </div>
              ))}

              {windowedRows.bottomPadding > 0 ? <div style={{ height: windowedRows.bottomPadding }} /> : null}
            </div>
          </div>
        )}
      </Panel>
    </div>
  );
}

interface TierStats {
  devices: number;
  missing: number;
  custom: number;
  stale: number;
  lowProfit: number;
  avgLabor: number | null;
}

function emptyTierStats(): Record<EditableTier, TierStats> {
  return {
    tier_a: { devices: 0, missing: 0, custom: 0, stale: 0, lowProfit: 0, avgLabor: null },
    tier_b: { devices: 0, missing: 0, custom: 0, stale: 0, lowProfit: 0, avgLabor: null },
    tier_c: { devices: 0, missing: 0, custom: 0, stale: 0, lowProfit: 0, avgLabor: null },
  };
}

export function RepairPricingTierSubTab() {
  const queryClient = useQueryClient();
  const [category, setCategory] = useState('phone');
  const [serviceId, setServiceId] = useState<number | ''>('');
  const [thresholdsDraft, setThresholdsDraft] = useState({ tierAYears: 2, tierBYears: 5 });
  const [thresholdsDirty, setThresholdsDirty] = useState(false);
  const [presentationDraft, setPresentationDraft] = useState<Record<PresentableTier, { label: string; color: string }> | null>(null);
  const [presentationDirty, setPresentationDirty] = useState(false);
  const [overwriteCustom, setOverwriteCustom] = useState(false);
  const [tierDrafts, setTierDrafts] = useState<Record<EditableTier, string>>({
    tier_a: '',
    tier_b: '',
    tier_c: '',
  });
  const [lastApplyResult, setLastApplyResult] = useState<RepairPricingTierApplyResult | null>(null);

  const tiersQuery = useQuery({
    queryKey: ['repair-pricing', 'tiers'],
    queryFn: async () => {
      const res = await repairPricingApi.getTiers();
      return res.data.data;
    },
    staleTime: 60_000,
  });

  const servicesQuery = useQuery({
    queryKey: ['repair-pricing', 'tier-services', category],
    queryFn: async () => {
      const res = await repairPricingApi.getServices({ category });
      return res.data.data as RepairPricingMatrixService[];
    },
    staleTime: 60_000,
  });

  const services = servicesQuery.data ?? [];

  useEffect(() => {
    if (!serviceId && services[0]) setServiceId(services[0].id);
  }, [serviceId, services]);

  useEffect(() => {
    if (!tiersQuery.data || thresholdsDirty) return;
    setThresholdsDraft({
      tierAYears: tiersQuery.data.thresholds.tierAYears,
      tierBYears: tiersQuery.data.thresholds.tierBYears,
    });
  }, [thresholdsDirty, tiersQuery.data]);

  useEffect(() => {
    if (!tiersQuery.data || presentationDirty) return;
    const next = { ...DEFAULT_TIER_PRESENTATION };
    for (const tier of tiersQuery.data.tiers) {
      const key = tier.key as PresentableTier;
      if (!PRESENTABLE_TIERS.includes(key)) continue;
      next[key] = {
        label: tier.label || DEFAULT_TIER_PRESENTATION[key].label,
        color: tier.color || DEFAULT_TIER_PRESENTATION[key].color,
      };
    }
    setPresentationDraft(next);
  }, [presentationDirty, tiersQuery.data]);

  const tierMatrixQuery = useQuery({
    queryKey: ['repair-pricing', 'tier-impact-matrix', category, serviceId || 'none'],
    queryFn: async () => {
      const res = await repairPricingApi.getMatrix({
        category,
        repair_service_id: serviceId || undefined,
        limit: 900,
      });
      return res.data.data;
    },
    enabled: !!serviceId,
    staleTime: 30_000,
  });

  const saveThresholdsMutation = useMutation({
    mutationFn: () => repairPricingApi.setTiers({
      tier_a_years: thresholdsDraft.tierAYears,
      tier_b_years: thresholdsDraft.tierBYears,
      confirmation: 'CONFIRM',
    }),
    onSuccess: () => {
      setThresholdsDirty(false);
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success('Tier windows saved');
    },
    onError: (err: unknown) => toast.error(`Could not save tier windows: ${formatApiError(err)}`),
  });

  const savePresentationMutation = useMutation({
    mutationFn: () => {
      const presentation = presentationDraft ?? DEFAULT_TIER_PRESENTATION;
      const payload: Record<string, string> = {};
      for (const tier of PRESENTABLE_TIERS) {
        const suffix = tierConfigSuffix(tier);
        payload[`repair_pricing_${suffix}_label`] = presentation[tier].label.trim() || DEFAULT_TIER_PRESENTATION[tier].label;
        payload[`repair_pricing_${suffix}_color`] = presentation[tier].color.trim() || DEFAULT_TIER_PRESENTATION[tier].color;
      }
      return settingsApi.updateConfig(payload);
    },
    onSuccess: () => {
      setPresentationDirty(false);
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success('Tier labels saved');
    },
    onError: (err: unknown) => toast.error(`Could not save tier labels: ${formatApiError(err)}`),
  });

  const applyTierMutation = useMutation({
    mutationFn: (data: { tier: EditableTier; laborPrice: number }) =>
      repairPricingApi.applyTier({
        repair_service_id: Number(serviceId),
        tier: data.tier,
        labor_price: data.laborPrice,
        category,
        overwrite_custom: overwriteCustom,
      }),
    onSuccess: (res) => {
      const result = res.data.data;
      setLastApplyResult(result);
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success(`Applied ${result.tier_label}: ${result.inserted} inserted, ${result.updated} updated, ${result.skipped_custom} skipped`);
    },
    onError: (err: unknown) => toast.error(`Could not apply tier default: ${formatApiError(err)}`),
  });

  const selectedService = services.find((service) => service.id === Number(serviceId));
  const tierStats = useMemo(() => {
    const stats = emptyTierStats();
    const laborTotals: Record<EditableTier, { total: number; count: number }> = {
      tier_a: { total: 0, count: 0 },
      tier_b: { total: 0, count: 0 },
      tier_c: { total: 0, count: 0 },
    };

    const matrix = tierMatrixQuery.data;
    if (!matrix || !serviceId) return stats;

    for (const device of matrix.devices) {
      if (device.tier === 'unknown') continue;
      const tier = device.tier as EditableTier;
      const price = matrixPriceFor(device, Number(serviceId));
      stats[tier].devices += 1;

      if (!price?.price_id) {
        stats[tier].missing += 1;
        continue;
      }

      if (price.is_custom) stats[tier].custom += 1;
      if (price.profit_stale_at) stats[tier].stale += 1;
      if (price.profit_estimate != null && price.profit_estimate < 40) stats[tier].lowProfit += 1;
      if (price.labor_price != null && !price.is_custom) {
        laborTotals[tier].total += numberOrZero(price.labor_price);
        laborTotals[tier].count += 1;
      }
    }

    for (const tier of EDITABLE_TIERS) {
      const total = laborTotals[tier.key];
      stats[tier.key].avgLabor = total.count > 0 ? Math.round((total.total / total.count) * 100) / 100 : null;
    }

    return stats;
  }, [serviceId, tierMatrixQuery.data]);

  const saveThresholds = async () => {
    if (thresholdsDraft.tierBYears < thresholdsDraft.tierAYears) {
      toast.error('Tier B years must be greater than or equal to Tier A years.');
      return;
    }

    let impactText = '';
    try {
      const preview = await repairPricingApi.previewTierImpact({
        tier_a_years: thresholdsDraft.tierAYears,
        tier_b_years: thresholdsDraft.tierBYears,
      });
      const impact = preview.data.data;
      impactText = `${formatNumber(impact.devices_crossing)} devices cross tiers, ${formatNumber(impact.price_rows_repriceable)} price rows can reprice, estimated labor delta ${formatCurrency(impact.estimated_labor_delta)}.`;
    } catch (err: unknown) {
      toast.error(`Could not preview tier impact: ${formatApiError(err)}`);
      return;
    }
    const ok = await confirm(
      `Save tier windows as Flagship 0-${thresholdsDraft.tierAYears} years and Mainstream through ${thresholdsDraft.tierBYears} years? ${impactText} Type CONFIRM is sent to the server after this approval.`,
    );
    if (!ok) return;
    saveThresholdsMutation.mutate();
  };

  const applyTier = async (tier: EditableTier) => {
    if (!serviceId) {
      toast.error('Choose a repair service first.');
      return;
    }
    const fallback = tierStats[tier].avgLabor;
    const laborPrice = parseLaborPrice(tierDrafts[tier] || (fallback == null ? '' : moneyInput(fallback)));
    if (laborPrice == null) {
      toast.error('Enter a valid labor price before applying this tier.');
      return;
    }

    const stats = tierStats[tier];
    const label = tierLabel(tier);
    const ok = await confirm(
      `Apply ${formatCurrency(laborPrice)} ${label} labor for ${serviceName(selectedService)} across ${formatNumber(stats.devices)} ${category} device${stats.devices === 1 ? '' : 's'}? ${overwriteCustom ? 'Custom overrides will be overwritten.' : `${formatNumber(stats.custom)} custom override${stats.custom === 1 ? '' : 's'} will be preserved.`}`,
    );
    if (!ok) return;
    applyTierMutation.mutate({ tier, laborPrice });
  };

  const presentation = presentationDraft ?? DEFAULT_TIER_PRESENTATION;

  return (
    <div className="grid grid-cols-1 gap-4 xl:grid-cols-[360px_1fr]">
      <Panel
        title="Tier windows"
        description="These windows decide how model release years map to Flagship, Mainstream, and Legacy tiers."
        icon={<SlidersHorizontal className="h-4 w-4" />}
        action={
          <button
            type="button"
            onClick={saveThresholds}
            disabled={!thresholdsDirty || saveThresholdsMutation.isPending}
            className="btn btn-primary btn-sm"
          >
            {saveThresholdsMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
            Save windows
          </button>
        }
      >
        <div className="space-y-3">
          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500">Flagship through</span>
            <div className="mt-1 flex items-center gap-2">
              <input
                type="number"
                min={0}
                max={50}
                value={thresholdsDraft.tierAYears}
                onChange={(event) => {
                  setThresholdsDirty(true);
                  setThresholdsDraft((prev) => ({ ...prev, tierAYears: Math.max(0, Number(event.target.value) || 0) }));
                }}
                className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-right text-sm dark:border-surface-700 dark:bg-surface-800"
              />
              <span className="w-12 text-xs text-surface-500">years</span>
            </div>
          </label>
          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-wide text-surface-500">Mainstream through</span>
            <div className="mt-1 flex items-center gap-2">
              <input
                type="number"
                min={0}
                max={50}
                value={thresholdsDraft.tierBYears}
                onChange={(event) => {
                  setThresholdsDirty(true);
                  setThresholdsDraft((prev) => ({ ...prev, tierBYears: Math.max(0, Number(event.target.value) || 0) }));
                }}
                className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-right text-sm dark:border-surface-700 dark:bg-surface-800"
              />
              <span className="w-12 text-xs text-surface-500">years</span>
            </div>
          </label>

          <div className="grid grid-cols-2 gap-2 pt-2">
            {tiersQuery.data?.tiers.map((tier) => (
              <div key={tier.key} className="rounded-md border border-surface-200 bg-surface-50 px-3 py-2 dark:border-surface-700 dark:bg-surface-800">
                <div className="flex items-center gap-2 text-xs font-medium text-surface-500">
                  <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: tier.color ?? '#94a3b8' }} />
                  {tier.label}
                </div>
                <div className="text-lg font-semibold text-surface-900 dark:text-surface-100">{formatNumber(tier.device_count ?? 0)}</div>
              </div>
            ))}
          </div>

          <div className="border-t border-surface-200 pt-3 dark:border-surface-700">
            <div className="mb-2 flex items-center justify-between gap-2">
              <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Labels and colors</h4>
              <button
                type="button"
                onClick={() => savePresentationMutation.mutate()}
                disabled={!presentationDirty || savePresentationMutation.isPending}
                className="btn btn-secondary btn-xs"
              >
                {savePresentationMutation.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
                Save
              </button>
            </div>
            <div className="space-y-2">
              {PRESENTABLE_TIERS.map((tier) => (
                <div key={tier} className="grid grid-cols-[32px_1fr] items-center gap-2">
                  <input
                    type="color"
                    value={presentation[tier].color}
                    onChange={(event) => {
                      setPresentationDirty(true);
                      setPresentationDraft((prev) => ({
                        ...(prev ?? presentation),
                        [tier]: { ...(prev ?? presentation)[tier], color: event.target.value },
                      }));
                    }}
                    className="h-8 w-8 rounded border border-surface-300 bg-transparent p-0 dark:border-surface-700"
                    aria-label={`${tierLabel(tier)} color`}
                  />
                  <input
                    type="text"
                    value={presentation[tier].label}
                    onChange={(event) => {
                      setPresentationDirty(true);
                      setPresentationDraft((prev) => ({
                        ...(prev ?? presentation),
                        [tier]: { ...(prev ?? presentation)[tier], label: event.target.value.slice(0, 32) },
                      }));
                    }}
                    className="rounded-md border border-surface-300 bg-white px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800"
                    aria-label={`${tierLabel(tier)} label`}
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </Panel>

      <Panel
        title="Bulk tier defaults"
        description="Apply labor defaults to one repair service by tier, with impact shown before confirmation."
        icon={<Calculator className="h-4 w-4" />}
      >
        <div className="mb-4 grid grid-cols-1 gap-3 md:grid-cols-[180px_1fr_auto]">
          <SelectField label="Category" value={category} onChange={(value) => { setCategory(value); setServiceId(''); }}>
            {CATEGORY_OPTIONS.map((option) => (
              <option key={option} value={option}>{categoryLabel(option)}</option>
            ))}
          </SelectField>
          <SelectField label="Service" value={serviceId} onChange={(value) => setServiceId(value ? Number(value) : '')}>
            {services.map((service) => (
              <option key={service.id} value={service.id}>{service.name}</option>
            ))}
          </SelectField>
          <label className="mt-6 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
            <input
              type="checkbox"
              checked={overwriteCustom}
              onChange={(event) => setOverwriteCustom(event.target.checked)}
              className="rounded border-surface-300"
            />
            Overwrite custom rows
          </label>
        </div>

        {tierMatrixQuery.isLoading ? (
          <div className="flex items-center justify-center py-12 text-sm text-surface-500">
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Loading tier impact
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
            {EDITABLE_TIERS.map((tier) => {
              const stats = tierStats[tier.key];
              const defaultValue = tierDrafts[tier.key] || (stats.avgLabor == null ? '' : moneyInput(stats.avgLabor));
              return (
                <div key={tier.key} className="rounded-lg border border-surface-200 bg-surface-50 p-3 dark:border-surface-700 dark:bg-surface-800">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">{tier.label}</h4>
                      <p className="text-xs text-surface-500">{tier.description}</p>
                    </div>
                    <Chip tone="blue">{formatNumber(stats.devices)} devices</Chip>
                  </div>

                  <div className="mt-3">
                    <CurrencyInput
                      value={defaultValue}
                      ariaLabel={`${tier.label} default labor`}
                      onChange={(value) => setTierDrafts((prev) => ({ ...prev, [tier.key]: value }))}
                    />
                    <div className="mt-1 text-right text-[11px] text-surface-400">
                      {stats.avgLabor == null ? 'No current tier average' : `Current non-custom avg ${formatCurrency(stats.avgLabor)}`}
                    </div>
                  </div>

                  <div className="mt-3 grid grid-cols-2 gap-2 text-xs">
                    <Chip tone={stats.missing ? 'amber' : 'surface'}>{formatNumber(stats.missing)} missing</Chip>
                    <Chip tone={stats.custom ? 'purple' : 'surface'}>{formatNumber(stats.custom)} custom</Chip>
                    <Chip tone={stats.stale ? 'amber' : 'surface'}>{formatNumber(stats.stale)} stale</Chip>
                    <Chip tone={stats.lowProfit ? 'red' : 'surface'}>{formatNumber(stats.lowProfit)} low profit</Chip>
                  </div>

                  <button
                    type="button"
                    onClick={() => applyTier(tier.key)}
                    disabled={!serviceId || applyTierMutation.isPending}
                    className="btn btn-primary btn-sm mt-3 w-full"
                  >
                    {applyTierMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
                    Apply {tier.label}
                  </button>
                </div>
              );
            })}
          </div>
        )}

        {lastApplyResult ? (
          <div className="mt-4 rounded-md border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-900 dark:bg-green-900/20 dark:text-green-200">
            Last apply: {lastApplyResult.tier_label} {serviceName(selectedService)} set to {formatCurrency(lastApplyResult.labor_price)}.
            {' '}
            {lastApplyResult.inserted} inserted, {lastApplyResult.updated} updated, {lastApplyResult.skipped_custom} custom skipped.
          </div>
        ) : null}
      </Panel>
    </div>
  );
}

export function RepairPricingAutomationSubTab() {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<RepairPricingAutoMarginSettings | null>(null);
  const [preview, setPreview] = useState<RepairPricingAutoMarginPreview | null>(null);
  const [previewInput, setPreviewInput] = useState({ supplierCost: '45', currentLabor: '120' });
  const [thresholdDraft, setThresholdDraft] = useState<TierProfitThresholds | null>(null);

  const settingsQuery = useQuery({
    queryKey: ['repair-pricing', 'auto-margin-settings'],
    queryFn: async () => {
      const res = await repairPricingApi.getAutoMarginSettings();
      return res.data.data;
    },
    staleTime: 60_000,
  });

  const thresholdConfigQuery = useQuery({
    queryKey: ['settings-config', 'repair-pricing-thresholds'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return (res.data?.data ?? {}) as Record<string, string>;
    },
    staleTime: 60_000,
  });

  const alertsQuery = useQuery({
    queryKey: ['repair-pricing', 'margin-alerts'],
    queryFn: async () => {
      const res = await repairPricingApi.getMarginAlerts({ limit: 25 });
      return res.data.data;
    },
    staleTime: 30_000,
  });

  const settings = draft ?? settingsQuery.data ?? DEFAULT_AUTO_MARGIN_SETTINGS;
  const persistedThresholds = useMemo(
    () => parseTierProfitThresholds(thresholdConfigQuery.data?.repair_pricing_tier_profit_thresholds),
    [thresholdConfigQuery.data],
  );
  const thresholds = thresholdDraft ?? persistedThresholds;
  const thresholdsDirty = !!thresholdDraft;
  const thresholdsValid = (Object.keys(thresholds) as Array<keyof TierProfitThresholds>).every((tier) => {
    const row = thresholds[tier];
    return row.green >= row.amber && row.amber >= row.red && row.red >= 0;
  });

  const updateDraft = (patch: Partial<RepairPricingAutoMarginSettings>) => {
    setDraft((prev) => ({ ...(prev ?? settings), ...patch }));
    setPreview(null);
  };

  const updateThreshold = (tier: keyof TierProfitThresholds, key: keyof TierProfitThresholds['tier_a'], value: number) => {
    setThresholdDraft((prev) => ({
      ...(prev ?? thresholds),
      [tier]: {
        ...(prev ?? thresholds)[tier],
        [key]: Number.isFinite(value) ? value : 0,
      },
    }));
  };

  const previewMutation = useMutation({
    mutationFn: () => repairPricingApi.previewAutoMargin({
      ...settings,
      supplier_cost: Number(previewInput.supplierCost),
      current_labor_price: Number(previewInput.currentLabor),
    }),
    onSuccess: (res) => setPreview(res.data.data),
    onError: (err: unknown) => toast.error(`Could not preview auto-margin: ${formatApiError(err)}`),
  });

  const saveMutation = useMutation({
    mutationFn: () => repairPricingApi.setAutoMarginSettings(settings),
    onSuccess: () => {
      setDraft(null);
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success('Auto-margin settings saved');
    },
    onError: (err: unknown) => toast.error(`Could not save auto-margin settings: ${formatApiError(err)}`),
  });

  const thresholdSaveMutation = useMutation({
    mutationFn: () => settingsApi.updateConfig({
      repair_pricing_tier_profit_thresholds: JSON.stringify(thresholds),
      repair_pricing_target_profit_green: String(thresholds.tier_b.green),
      repair_pricing_target_profit_amber: String(thresholds.tier_b.amber),
    }),
    onSuccess: () => {
      setThresholdDraft(null);
      queryClient.invalidateQueries({ queryKey: ['settings-config', 'repair-pricing-thresholds'] });
      queryClient.invalidateQueries({ queryKey: ['repair-pricing', 'margin-alert-summary'] });
      queryClient.invalidateQueries({ queryKey: ['repair-pricing', 'margin-alerts'] });
      toast.success('Profit alert floors saved');
    },
    onError: (err: unknown) => toast.error(`Could not save profit floors: ${formatApiError(err)}`),
  });

  const runMutation = useMutation({
    mutationFn: async () => {
      await repairPricingApi.setAutoMarginSettings(settings);
      return repairPricingApi.recomputeProfits({ auto_margin: true });
    },
    onSuccess: (res) => {
      setDraft(null);
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      const data = res.data.data;
      toast.success(`Auto-margin complete: ${data.auto_margin?.adjusted ?? 0} adjusted, ${data.auto_margin?.skipped ?? 0} skipped`);
    },
    onError: (err: unknown) => toast.error(`Could not run auto-margin: ${formatApiError(err)}`),
  });

  const recomputeMutation = useMutation({
    mutationFn: () => repairPricingApi.recomputeProfits({}),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['repair-pricing'] });
      toast.success(`Profit recompute: ${res.data.data.recompute.updated} updated, ${res.data.data.recompute.stale} stale`);
    },
    onError: (err: unknown) => toast.error(`Could not recompute profits: ${formatApiError(err)}`),
  });

  const ackAlertMutation = useMutation({
    mutationFn: (id: number) => repairPricingApi.ackMarginAlert(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['repair-pricing', 'margin-alerts'] });
      queryClient.invalidateQueries({ queryKey: ['repair-pricing', 'margin-alert-summary'] });
      toast.success('Margin alert acknowledged');
    },
    onError: (err: unknown) => toast.error(`Could not acknowledge alert: ${formatApiError(err)}`),
  });

  return (
    <div className="grid grid-cols-1 gap-4 xl:grid-cols-[1fr_420px]">
      <Panel
        title="Auto-margin and rounding"
        description="Configure the server-side calculator used by profit recompute and nightly catalog sync."
        icon={<Settings2 className="h-4 w-4" />}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => recomputeMutation.mutate()}
              disabled={recomputeMutation.isPending}
              className="btn btn-secondary btn-sm"
            >
              {recomputeMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCcw className="h-3.5 w-3.5" />}
              Recompute only
            </button>
            <button
              type="button"
              onClick={() => saveMutation.mutate()}
              disabled={saveMutation.isPending || !draft}
              className="btn btn-secondary btn-sm"
            >
              {saveMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
              Save
            </button>
            <button
              type="button"
              onClick={() => runMutation.mutate()}
              disabled={runMutation.isPending}
              className="btn btn-primary btn-sm"
            >
              {runMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Calculator className="h-3.5 w-3.5" />}
              Save and run
            </button>
          </div>
        }
      >
        {settingsQuery.isLoading ? (
          <div className="flex items-center justify-center py-12 text-sm text-surface-500">
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Loading auto-margin settings
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
              <SelectField label="Preset" value={settings.preset} onChange={(value) => updateDraft({ preset: value as RepairPricingAutoMarginSettings['preset'] })}>
                <option value="custom">Custom</option>
                <option value="high_traffic">High traffic</option>
                <option value="mid_traffic">Mid traffic</option>
                <option value="low_traffic">Low traffic</option>
                <option value="value">Value</option>
                <option value="balanced">Balanced</option>
                <option value="premium">Premium</option>
              </SelectField>

              <SelectField label="Target type" value={settings.target_type} onChange={(value) => updateDraft({ target_type: value as RepairPricingAutoMarginSettings['target_type'] })}>
                <option value="percent">Percent target</option>
                <option value="fixed_amount">Fixed profit</option>
              </SelectField>

              <label className="block">
                <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
                  {settings.target_type === 'fixed_amount' ? 'Target profit' : 'Target margin'}
                </span>
                <div className="mt-1 flex items-center gap-2">
                  <input
                    type="number"
                    min={0}
                    max={settings.target_type === 'fixed_amount' ? 10000 : 95}
                    value={settings.target_type === 'fixed_amount' ? settings.target_profit_amount : settings.target_margin_pct}
                    onChange={(event) => {
                      const value = Number(event.target.value);
                      if (settings.target_type === 'fixed_amount') updateDraft({ target_profit_amount: value });
                      else updateDraft({ target_margin_pct: value });
                    }}
                    className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-right text-sm dark:border-surface-700 dark:bg-surface-800"
                  />
                  <span className="w-8 text-sm text-surface-500">{settings.target_type === 'fixed_amount' ? '$' : '%'}</span>
                </div>
              </label>

              <SelectField label="Basis" value={settings.calculation_basis} onChange={(value) => updateDraft({ calculation_basis: value as RepairPricingAutoMarginSettings['calculation_basis'] })}>
                <option value="gross_margin">Gross margin</option>
                <option value="markup">Markup</option>
              </SelectField>

              <SelectField label="Backend rounding mode" value={settings.rounding_mode} onChange={(value) => updateDraft({ rounding_mode: value as RepairPricingRoundingMode })}>
                {ROUNDING_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>{option.label}</option>
                ))}
              </SelectField>

              <label className="block">
                <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Per-run cap</span>
                <div className="mt-1 flex items-center gap-2">
                  <input
                    type="number"
                    min={0}
                    max={100}
                    value={settings.cap_pct}
                    onChange={(event) => updateDraft({ cap_pct: Number(event.target.value) })}
                    className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-right text-sm dark:border-surface-700 dark:bg-surface-800"
                  />
                  <span className="w-8 text-sm text-surface-500">%</span>
                </div>
              </label>
            </div>

            <div className="mt-4 rounded-lg border border-surface-200 bg-surface-50 p-3 dark:border-surface-700 dark:bg-surface-800">
              <div className="grid grid-cols-1 gap-3 md:grid-cols-[160px_160px_auto_1fr]">
                <label className="block">
                  <span className="text-xs font-medium text-surface-500">Supplier cost</span>
                  <CurrencyInput
                    value={previewInput.supplierCost}
                    ariaLabel="Supplier cost preview"
                    onChange={(value) => setPreviewInput((prev) => ({ ...prev, supplierCost: value }))}
                  />
                </label>
                <label className="block">
                  <span className="text-xs font-medium text-surface-500">Current labor</span>
                  <CurrencyInput
                    value={previewInput.currentLabor}
                    ariaLabel="Current labor preview"
                    onChange={(value) => setPreviewInput((prev) => ({ ...prev, currentLabor: value }))}
                  />
                </label>
                <button
                  type="button"
                  onClick={() => previewMutation.mutate()}
                  disabled={previewMutation.isPending}
                  className="btn btn-secondary btn-sm self-end"
                >
                  {previewMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Calculator className="h-3.5 w-3.5" />}
                  Preview
                </button>
                <div className="self-end text-sm text-surface-600 dark:text-surface-300">
                  {preview ? (
                    <div className="flex flex-wrap gap-2">
                      <Chip tone="blue">Raw {formatCurrency(preview.uncapped_labor_price)}</Chip>
                      <Chip tone="purple">Rounded {formatCurrency(preview.rounded_labor_price)}</Chip>
                      {preview.capped_labor_price != null ? <Chip tone="amber">Capped {formatCurrency(preview.capped_labor_price)}</Chip> : null}
                      <Chip tone={preview.profit_estimate < 40 ? 'amber' : 'green'}>
                        Profit {formatCurrency(preview.profit_estimate)} ({Math.round(preview.margin_pct)}%)
                      </Chip>
                    </div>
                  ) : (
                    <span>{ROUNDING_OPTIONS.find((option) => option.value === settings.rounding_mode)?.helper ?? 'Preview the current rule'}</span>
                  )}
                </div>
              </div>
            </div>

            <div className="mt-4 rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-900">
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Profit alert floors</h3>
                  <p className="text-xs text-surface-500 dark:text-surface-400">Margin alerts use each row's current tier instead of a single global floor.</p>
                </div>
                <button
                  type="button"
                  onClick={() => thresholdSaveMutation.mutate()}
                  disabled={!thresholdsDirty || !thresholdsValid || thresholdSaveMutation.isPending}
                  className="btn btn-secondary btn-sm"
                >
                  {thresholdSaveMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
                  Save floors
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                  <thead>
                    <tr className="border-b border-surface-100 text-left text-xs uppercase tracking-wide text-surface-500 dark:border-surface-800">
                      <th className="py-2 pr-3 font-semibold">Tier</th>
                      <th className="py-2 pr-3 text-right font-semibold">Green</th>
                      <th className="py-2 pr-3 text-right font-semibold">Amber</th>
                      <th className="py-2 text-right font-semibold">Red</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                    {(Object.keys(thresholds) as Array<keyof TierProfitThresholds>).map((tier) => (
                      <tr key={tier}>
                        <td className="py-2 pr-3 font-medium text-surface-800 dark:text-surface-100">{tierLabel(tier)}</td>
                        {(['green', 'amber', 'red'] as const).map((field) => (
                          <td key={field} className="py-2 pr-3 text-right last:pr-0">
                            <input
                              type="number"
                              min={0}
                              max={100000}
                              value={thresholds[tier][field]}
                              onChange={(event) => updateThreshold(tier, field, Number(event.target.value))}
                              className="w-24 rounded-md border border-surface-300 bg-white px-2 py-1 text-right text-sm dark:border-surface-700 dark:bg-surface-800"
                            />
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {!thresholdsValid ? (
                <p className="mt-2 text-xs font-medium text-red-600 dark:text-red-300">Each tier must be ordered {'green >= amber >= red'}.</p>
              ) : null}
            </div>
          </>
        )}
      </Panel>

      <Panel
        title="Margin alerts"
        description="Active low-profit rows surfaced by the server alert job."
        icon={<AlertTriangle className="h-4 w-4" />}
      >
        {alertsQuery.isLoading ? (
          <div className="flex items-center justify-center py-10 text-sm text-surface-500">
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Loading alerts
          </div>
        ) : !alertsQuery.data || alertsQuery.data.length === 0 ? (
          <div className="rounded-md border border-green-200 bg-green-50 p-3 text-sm text-green-700 dark:border-green-900 dark:bg-green-900/20 dark:text-green-300">
            No active margin alerts.
          </div>
        ) : (
          <div className="space-y-2">
            {alertsQuery.data.map((alert) => (
              <div key={alert.id} className="rounded-md border border-surface-200 bg-surface-50 p-3 dark:border-surface-700 dark:bg-surface-800">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-semibold text-surface-900 dark:text-surface-100">
                      {alert.device_model_name ?? `Device #${alert.device_model_id}`}
                    </div>
                    <div className="mt-0.5 text-xs text-surface-500">{alert.repair_service_name ?? `Service #${alert.repair_service_id}`}</div>
                  </div>
                  <Chip tone={alert.acked_at ? 'surface' : 'red'}>{alert.acked_at ? 'Acked' : 'Open'}</Chip>
                </div>
                <div className="mt-2 flex flex-wrap gap-1">
                  <Chip tone={numberOrZero(alert.profit_estimate) < 0 ? 'red' : 'amber'}>{formatCurrency(alert.profit_estimate)} profit</Chip>
                  <Chip>Labor {formatCurrency(alert.labor_price)}</Chip>
                  <Chip>Cost {formatCurrency(alert.supplier_cost)}</Chip>
                  <Chip>{formatNumber(alert.days_active ?? 0)} days</Chip>
                </div>
                {!alert.acked_at ? (
                  <button
                    type="button"
                    onClick={() => ackAlertMutation.mutate(alert.id)}
                    disabled={ackAlertMutation.isPending}
                    className="btn btn-ghost btn-xs mt-2 text-surface-600 hover:text-surface-900 dark:text-surface-300"
                  >
                    {ackAlertMutation.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Check className="h-3 w-3" />}
                    Acknowledge
                  </button>
                ) : null}
              </div>
            ))}
          </div>
        )}
      </Panel>
    </div>
  );
}

export function RepairPricingAuditSubTab() {
  const [serviceId, setServiceId] = useState<number | ''>('');
  const [search, setSearch] = useState('');
  const [source, setSource] = useState('');
  const [limit, setLimit] = useState(100);

  const servicesQuery = useQuery({
    queryKey: ['repair-pricing', 'audit-services'],
    queryFn: async () => {
      const res = await repairPricingApi.getServices();
      return res.data.data as RepairPricingMatrixService[];
    },
    staleTime: 60_000,
  });

  const auditQuery = useQuery({
    queryKey: ['repair-pricing', 'audit', serviceId || 'all', limit],
    queryFn: async () => {
      const res = await repairPricingApi.getAudit({
        repair_service_id: serviceId || undefined,
        limit,
      });
      return res.data.data;
    },
    staleTime: 20_000,
  });

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (auditQuery.data ?? []).filter((row) => {
      if (source && row.source !== source) return false;
      if (!q) return true;
      return [
        row.device_model_name,
        row.repair_service_name,
        row.changed_by_username,
        row.source,
        row.note,
      ].some((value) => String(value ?? '').toLowerCase().includes(q));
    });
  }, [auditQuery.data, search, source]);

  return (
    <Panel
      title="Pricing audit log"
      description="Recent manual edits, tier applies, auto-margin runs, rebases, and reverts."
      icon={<History className="h-4 w-4" />}
      action={
        <button
          type="button"
          onClick={() => auditQuery.refetch()}
          disabled={auditQuery.isFetching}
          className="btn btn-secondary btn-sm"
        >
          {auditQuery.isFetching ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCcw className="h-3.5 w-3.5" />}
          Refresh
        </button>
      }
    >
      <div className="mb-4 grid grid-cols-1 gap-3 lg:grid-cols-[1fr_220px_160px_120px]">
        <label className="block">
          <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">Search audit</span>
          <div className="relative mt-1">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Device, service, user, or note"
              className="w-full rounded-md border border-surface-300 bg-white py-2 pl-8 pr-3 text-sm dark:border-surface-700 dark:bg-surface-800"
            />
          </div>
        </label>
        <SelectField label="Service" value={serviceId} onChange={(value) => setServiceId(value ? Number(value) : '')}>
          <option value="">All services</option>
          {(servicesQuery.data ?? []).map((service) => (
            <option key={service.id} value={service.id}>{service.name}</option>
          ))}
        </SelectField>
        <SelectField label="Source" value={source} onChange={setSource}>
          <option value="">All sources</option>
          <option value="manual">Manual</option>
          <option value="tier">Tier</option>
          <option value="auto-margin">Auto-margin</option>
          <option value="revert">Revert</option>
          <option value="csv">CSV</option>
        </SelectField>
        <SelectField label="Limit" value={limit} onChange={(value) => setLimit(Number(value))}>
          <option value={50}>50</option>
          <option value={100}>100</option>
          <option value={250}>250</option>
          <option value={500}>500</option>
        </SelectField>
      </div>

      {auditQuery.isLoading ? (
        <div className="flex items-center justify-center py-16 text-sm text-surface-500">
          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          Loading audit log
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-md border border-surface-200 bg-surface-50 p-4 text-sm text-surface-500 dark:border-surface-700 dark:bg-surface-800">
          No audit rows match the current filters.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-surface-200 dark:border-surface-700">
          <table className="min-w-full divide-y divide-surface-200 text-sm dark:divide-surface-700">
            <thead className="bg-surface-50 text-xs uppercase tracking-wide text-surface-500 dark:bg-surface-800">
              <tr>
                <th className="px-3 py-2 text-left">When</th>
                <th className="px-3 py-2 text-left">Source</th>
                <th className="px-3 py-2 text-left">Device</th>
                <th className="px-3 py-2 text-left">Service</th>
                <th className="px-3 py-2 text-right">Labor</th>
                <th className="px-3 py-2 text-right">Tier</th>
                <th className="px-3 py-2 text-left">Note</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {rows.map((row: RepairPricingAuditRow) => (
                <tr key={row.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50">
                  <td className="whitespace-nowrap px-3 py-2 text-xs text-surface-500" title={formatDateTime(row.created_at)}>
                    {timeAgo(row.created_at)}
                    <div>{row.changed_by_username ?? 'system'}</div>
                  </td>
                  <td className="px-3 py-2">
                    <Chip tone={row.source === 'auto-margin' ? 'purple' : row.source === 'tier' ? 'blue' : row.source === 'revert' ? 'amber' : 'surface'}>
                      {row.source}
                    </Chip>
                  </td>
                  <td className="max-w-[220px] truncate px-3 py-2 text-surface-900 dark:text-surface-100">
                    {row.device_model_name ?? (row.device_model_id ? `Device #${row.device_model_id}` : '-')}
                  </td>
                  <td className="max-w-[200px] truncate px-3 py-2 text-surface-600 dark:text-surface-300">
                    {row.repair_service_name ?? (row.repair_service_id ? `Service #${row.repair_service_id}` : '-')}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 text-right">
                    {row.old_labor_price == null ? '-' : formatCurrency(row.old_labor_price)}
                    <span className="mx-1 text-surface-400">to</span>
                    {row.new_labor_price == null ? '-' : formatCurrency(row.new_labor_price)}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 text-right text-xs text-surface-500">
                    {tierLabel(row.old_tier_label)}
                    <span className="mx-1">to</span>
                    {tierLabel(row.new_tier_label)}
                  </td>
                  <td className="max-w-[320px] truncate px-3 py-2 text-xs text-surface-500" title={row.note ?? undefined}>
                    {row.note ?? '-'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}
