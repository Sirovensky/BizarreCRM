import { useState, useMemo, useCallback, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  LayoutDashboard, Ticket, DollarSign, CheckCircle2, Clock,
  Activity, ShoppingCart, AlertTriangle, ExternalLink, Package,
  Plus, ArrowRight, Loader2, Info, Download, TrendingUp,
  Receipt, BadgeDollarSign, CreditCard, Wallet, FileText,
  Calendar, PackageX, FileWarning, BoxSelect,
  Settings2, ChevronUp, ChevronDown, RotateCcw, X, Eye, EyeOff, CalendarClock, Lightbulb,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { reportApi, missingPartsApi, catalogApi, settingsApi, ticketApi, preferencesApi, smsApi, leadApi, onboardingApi, type OnboardingState } from '@/api/endpoints';
import { GettingStartedWidget } from '@/components/onboarding/GettingStartedWidget';
import { SampleDataCard } from '@/components/onboarding/SampleDataCard';
import { SuccessCelebration } from '@/components/onboarding/SuccessCelebration';
import { DailyNudge } from '@/components/onboarding/DailyNudge';
import { useMilestoneToasts } from '@/components/onboarding/useMilestoneToasts';
import { useAuthStore } from '@/stores/authStore';
import { useHasRole } from '@/hooks/useHasRole';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';
// Business Intelligence layer (audit 47)
import { ProfitHeroCard } from '@/components/reports/ProfitHeroCard';
import { BusyHoursHeatmap } from '@/components/reports/BusyHoursHeatmap';
import { TechLeaderboard } from '@/components/reports/TechLeaderboard';
import { RepeatCustomersCard } from '@/components/reports/RepeatCustomersCard';
import { CashTrappedCard } from '@/components/reports/CashTrappedCard';
import { ChurnAlert } from '@/components/reports/ChurnAlert';
import { ForecastChart } from '@/components/reports/ForecastChart';

// ─── Types ────────────────────────────────────────────────────────────────────

interface DashboardKpis {
  total_sales: number;
  tax: number;
  discounts: number;
  cogs: number;
  net_profit: number;
  refunds: number;
  expenses: number;
  receivables: number;
  sales_by_type: { type: string; quantity: number; sales: number; discounts: number; cogs: number; net_profit: number; tax: number }[];
  daily_sales: { date: string; sale: number; cogs: number; net_profit: number; margin: number; tax: number }[];
  open_tickets: { id: number; order_id: string; task: string; due_at: string | null; assigned_to: string; customer_name: string; status_name: string; status_color: string }[];
}

interface MissingPart {
  part_id: number;
  ticket_id: number;
  order_id: string;
  part_name: string;
  part_sku: string | null;
  quantity: number;
  in_stock: number;
  catalog_url: string | null;
  catalog_source: string | null;
  catalog_price: number | null;
  catalog_external_id: string | null;
  supplier_url: string | null;
  device_name: string;
  customer_name: string;
  ticket_status: string;
  ticket_status_color: string;
  image_url: string | null;
}

// WEB-FA-021: shape of `GET /catalog/order-queue/summary` response.body.data.
// Server returns aggregate counts + cost across pending order-queue rows.
interface OrderQueueSummary {
  total_items: number;
  estimated_cost: number;
}

// Minimal row shape consumed by MissingPartsCard from the order-queue list
// endpoint. Only fields the card actually reads are typed; extra fields
// are tolerated at runtime.
interface OrderQueueItem {
  supplier_url?: string | null;
  source?: string | null;
}

// ─── Date Range Helpers ──────────────────────────────────────────────────────

type DatePreset = 'today' | 'yesterday' | 'last7' | 'thisMonth' | 'lastMonth' | 'thisYear' | 'all';

// SCAN-1162: `toISOString().slice(0, 10)` returns the UTC calendar date,
// which rolls over at midnight UTC — in non-UTC timezones (e.g. America/
// Denver UTC-6), "today" from 17:00 local onward resolved to the NEXT
// calendar day for the dashboard queries, so the "Today's Sales" KPIs
// disappeared at 5pm local. Use the browser's local getFullYear/Month/
// Date so the range matches the shop's wall clock.
function localYmd(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function getDateRange(preset: DatePreset): { from: string; to: string } {
  const today = new Date();
  const fmt = (d: Date) => localYmd(d);

  switch (preset) {
    case 'today':
      return { from: fmt(today), to: fmt(today) };
    case 'yesterday': {
      const y = new Date(today);
      y.setDate(y.getDate() - 1);
      return { from: fmt(y), to: fmt(y) };
    }
    case 'last7': {
      const d = new Date(today);
      d.setDate(d.getDate() - 6);
      return { from: fmt(d), to: fmt(today) };
    }
    case 'thisMonth':
      return { from: `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`, to: fmt(today) };
    case 'lastMonth': {
      const first = new Date(today.getFullYear(), today.getMonth() - 1, 1);
      const last = new Date(today.getFullYear(), today.getMonth(), 0);
      return { from: fmt(first), to: fmt(last) };
    }
    case 'thisYear':
      return { from: `${today.getFullYear()}-01-01`, to: fmt(today) };
    case 'all':
      return { from: '2020-01-01', to: fmt(today) };
  }
}

const DATE_PRESETS: { key: DatePreset; label: string }[] = [
  { key: 'today', label: 'Today' },
  { key: 'yesterday', label: 'Yesterday' },
  { key: 'last7', label: 'Last 7 Days' },
  { key: 'thisMonth', label: 'This Month' },
  { key: 'lastMonth', label: 'Last Month' },
  { key: 'thisYear', label: 'This Year' },
  { key: 'all', label: 'All' },
];

// ─── Helpers ─────────────────────────────────────────────────────────────────


function formatTicketId(orderId: string | number) {
  const str = String(orderId);
  if (str.startsWith('T-')) return str;
  return `T-${str.padStart(4, '0')}`;
}

// ─── KPI Card ─────────────────────────────────────────────────────────────────

function KpiCard({ label, value, tooltip, loading, href }: {
  label: string; value: string; tooltip?: string; loading?: boolean; href?: string;
}) {
  const navigate = useNavigate();
  return (
    <div
      onClick={href ? () => navigate(href) : undefined}
      className={cn('card p-4 flex flex-col gap-1', href && 'cursor-pointer hover:ring-2 hover:ring-primary-500/30 transition-shadow')}
    >
      <div className="flex items-center gap-1.5">
        <span className="text-xs font-semibold text-teal-600 dark:text-teal-400 uppercase tracking-wider">{label}</span>
        {tooltip && (
          // WEB-FQ-018 (Fixer-C4 2026-04-25): bumped to h-3.5 (14px) so the
          // tooltip glyph is hit-target-legible next to a 12px caption without
          // visually dwarfing the kpi label. h-3 was unreadable at retina/144dpi.
          <span title={tooltip} className="text-surface-400 cursor-help">
            <Info className="h-3.5 w-3.5" />
          </span>
        )}
      </div>
      {loading ? (
        <div className="h-7 w-20 bg-surface-200 dark:bg-surface-700 animate-pulse rounded mt-1" />
      ) : (
        <p className="text-xl font-bold text-surface-900 dark:text-surface-100">{value}</p>
      )}
    </div>
  );
}

// ─── Missing Parts Card ───────────────────────────────────────────────────────

/** WEB-FA-013 (Fixer-B14 2026-04-25): supplier base URLs centralised in a
 *  single map so the keys can be reviewed in one place and a future Settings
 *  → Suppliers page can pre-populate from this list. Still hard-coded — true
 *  per-tenant configurability requires a server-side `store_config` key (out
 *  of scope for this loop) — but adding a new supplier no longer requires
 *  hunting through the dashboard render path. */
const SUPPLIER_BASE_URLS: Record<string, string> = {
  mobilesentrix: 'https://www.mobilesentrix.com',
  phonelcdparts: 'https://www.phonelcdparts.com',
};

/** Build the best URL for ordering a part from its supplier.
 *  If we have a numeric Magento product ID (external_id), construct a direct add-to-cart URL.
 *  Otherwise fall back to the product page URL. */
function getSupplierOrderUrl(part: MissingPart): string | null {
  const source = part.catalog_source;
  const extId = part.catalog_external_id;
  const pageUrl = part.supplier_url || part.catalog_url;

  // If we have a numeric external_id, we can build an add-to-cart URL
  if (extId && /^\d+$/.test(extId) && source) {
    const base = SUPPLIER_BASE_URLS[source];
    if (base) {
      return `${base}/checkout/cart/add/product/${extId}/qty/${part.quantity}/`;
    }
  }

  return pageUrl || null;
}

/** Group parts by supplier source and collect their order URLs */
function groupPartsBySupplier(parts: MissingPart[]): Record<string, { parts: MissingPart[]; urls: string[] }> {
  const groups: Record<string, { parts: MissingPart[]; urls: string[] }> = {};
  for (const p of parts) {
    const source = p.catalog_source || 'unknown';
    if (!groups[source]) groups[source] = { parts: [], urls: [] };
    groups[source].parts.push(p);
    const url = getSupplierOrderUrl(p);
    if (url) groups[source].urls.push(url);
  }
  return groups;
}

const SUPPLIER_LABELS: Record<string, string> = {
  mobilesentrix: 'MobileSentrix',
  phonelcdparts: 'PhoneLcdParts',
  unknown: 'Supplier',
};

function MissingPartsCard({ parts, queueSummary, queueItems = [] }: { parts: MissingPart[]; queueSummary: OrderQueueSummary | null; queueItems?: OrderQueueItem[] }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // Build order URLs from both missing parts AND queue items
  const supplierGroups = useMemo(() => {
    const groups = groupPartsBySupplier(parts);
    // Also add URLs from queue items that have supplier_url
    for (const qi of queueItems) {
      if (qi.supplier_url) {
        const source = qi.source || 'unknown';
        if (!groups[source]) groups[source] = { parts: [], urls: [] };
        if (!groups[source].urls.includes(qi.supplier_url)) {
          groups[source].urls.push(qi.supplier_url);
        }
      }
    }
    return groups;
  }, [parts, queueItems]);

  const handleOpenAllForSupplier = (source: string) => {
    const group = supplierGroups[source];
    if (!group || group.urls.length === 0) return;

    // Open each product URL in a new tab — user adds to cart from there
    // First URL opens normally, rest open with slight delays
    // This is the most reliable approach since Magento blocks iframes
    for (let i = 0; i < group.urls.length; i++) {
      setTimeout(() => {
        window.open(group.urls[i], '_blank', 'noopener');
      }, i * 300);
    }

    toast.success(`Opening ${group.urls.length} product${group.urls.length !== 1 ? 's' : ''} from ${SUPPLIER_LABELS[source] || source}`);
  };

  const addToQueueMut = useMutation({
    mutationFn: (part: MissingPart) => catalogApi.addToOrderQueue({
      name: part.part_name,
      sku: part.part_sku ?? undefined,
      supplier_url: part.supplier_url ?? part.catalog_url ?? undefined,
      image_url: part.image_url ?? undefined,
      unit_price: part.catalog_price ?? undefined,
      quantity_needed: part.quantity,
      ticket_device_part_id: part.part_id,
      ticket_id: part.ticket_id,
    }),
    onSuccess: () => {
      toast.success('Added to order queue');
      queryClient.invalidateQueries({ queryKey: ['order-queue-summary'] });
      queryClient.invalidateQueries({ queryKey: ['missing-parts'] });
    },
    onError: () => toast.error('Failed to add to queue'),
  });

  if (parts.length === 0 && (!queueSummary || queueSummary.total_items === 0)) return null;

  const pendingCount = queueSummary?.total_items ?? 0;
  const needsOrderCount = parts.length;
  const estimatedCost = parts.reduce((sum, p) => sum + (p.catalog_price ?? 0) * p.quantity, 0);
  const queueCost = queueSummary?.estimated_cost ?? 0;
  const totalEstCost = estimatedCost + queueCost;

  return (
    <div className="card border-l-4 border-l-amber-400 mb-4">
      {needsOrderCount > 0 && (
        <div className="bg-amber-50 dark:bg-amber-900/20 border-b border-amber-200 dark:border-amber-800 px-4 py-3 flex items-center gap-3">
          <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400 flex-shrink-0" />
          <div className="flex-1">
            <p className="text-sm font-semibold text-amber-800 dark:text-amber-200">
              {needsOrderCount} part{needsOrderCount !== 1 ? 's' : ''} missing across open tickets
            </p>
            {totalEstCost > 0 && (
              <p className="text-xs text-amber-700 dark:text-amber-300 mt-0.5">
                Estimated cost to order: <strong>${totalEstCost.toFixed(2)}</strong>
              </p>
            )}
          </div>
          <div className="flex items-center gap-2">
            {Object.entries(supplierGroups).map(([source, group]) => (
              group.urls.length > 0 && (
                <button
                  key={`banner-${source}`}
                  onClick={() => handleOpenAllForSupplier(source)}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-teal-600 hover:bg-teal-700 text-white px-3 py-1.5 text-sm font-medium transition-colors"
                >
                  <ShoppingCart className="h-3.5 w-3.5" />
                  Order All — {SUPPLIER_LABELS[source] || source} ({group.urls.length})
                </button>
              )
            ))}
          </div>
        </div>
      )}

      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <ShoppingCart className="h-5 w-5 text-amber-500" />
          <h2 className="font-semibold text-surface-900 dark:text-surface-100">Parts to Order</h2>
          {needsOrderCount > 0 && (
            <span className="ml-1 inline-flex items-center justify-center h-5 min-w-5 px-1.5 rounded-full bg-amber-100 dark:bg-amber-900 text-amber-800 dark:text-amber-200 text-xs font-bold">
              {needsOrderCount}
            </span>
          )}
          {pendingCount > 0 && (
            <span className="ml-1 inline-flex items-center justify-center h-5 min-w-5 px-1.5 rounded-full bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 text-xs font-bold">
              {pendingCount} in queue
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {/* Order All buttons per supplier */}
          {Object.entries(supplierGroups).map(([source, group]) => (
            group.urls.length > 0 && (
              <button
                key={`header-${source}`}
                onClick={() => handleOpenAllForSupplier(source)}
                title={`Open all ${group.urls.length} parts from ${SUPPLIER_LABELS[source] || source} in new tabs to order`}
                className="inline-flex items-center gap-1.5 rounded-lg bg-teal-600 hover:bg-teal-700 text-white px-3 py-1.5 text-xs font-medium transition-colors"
              >
                <ShoppingCart className="h-3.5 w-3.5" />
                Order All — {SUPPLIER_LABELS[source] || source} ({group.urls.length})
              </button>
            )
          ))}
        </div>
      </div>

      {needsOrderCount > 0 && (
        <div className="divide-y divide-surface-100 dark:divide-surface-800 max-h-72 overflow-y-auto">
          {parts.slice(0, 10).map((p) => (
            <div key={p.part_id} className="flex items-center gap-3 px-4 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800/50">
              {p.image_url ? (
                <img src={p.image_url} alt="" loading="lazy" decoding="async" className="h-9 w-9 rounded object-cover flex-shrink-0 bg-surface-100" />
              ) : (
                <div className="h-9 w-9 rounded bg-amber-50 dark:bg-amber-900/30 flex items-center justify-center flex-shrink-0">
                  <Package className="h-4 w-4 text-amber-500" />
                </div>
              )}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{p.part_name}</p>
                <p className="text-xs text-surface-500 truncate">
                  {p.order_id} · {p.device_name} · {p.customer_name}
                </p>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                {p.catalog_price != null && (
                  <span className="text-sm font-semibold text-surface-700 dark:text-surface-300">
                    ${p.catalog_price.toFixed(2)}
                  </span>
                )}
                <span className="text-xs text-amber-600 dark:text-amber-400 font-medium bg-amber-50 dark:bg-amber-900/30 px-2 py-0.5 rounded">
                  Need {p.quantity}
                </span>
                {(() => {
                  const orderUrl = getSupplierOrderUrl(p);
                  if (!orderUrl) return null;
                  const isAddToCart = p.catalog_external_id && /^\d+$/.test(p.catalog_external_id);
                  return (
                    <a
                      href={orderUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      title={isAddToCart ? `Add to cart on ${p.catalog_source || 'supplier'}` : `View on ${p.catalog_source || 'supplier'}`}
                      className="p-1 rounded hover:bg-surface-200 dark:hover:bg-surface-700 text-blue-500"
                    >
                      {isAddToCart ? <ShoppingCart className="h-3.5 w-3.5" /> : <ExternalLink className="h-3.5 w-3.5" />}
                    </a>
                  );
                })()}
                <button
                  onClick={() => addToQueueMut.mutate(p)}
                  disabled={addToQueueMut.isPending}
                  title="Add to order queue"
                  className="inline-flex items-center gap-1 rounded-md bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 hover:bg-blue-100 dark:hover:bg-blue-900/50 px-2 py-1 text-xs font-medium transition-colors disabled:opacity-50"
                >
                  {addToQueueMut.isPending ? (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  ) : (
                    <Plus className="h-3 w-3" />
                  )}
                  Queue
                </button>
              </div>
            </div>
          ))}
          {parts.length > 10 && (
            <div className="px-4 py-2 text-xs text-surface-500 text-center">
              +{parts.length - 10} more parts needed
            </div>
          )}
        </div>
      )}

      <div className="px-4 py-3 bg-amber-50/50 dark:bg-amber-900/10 flex items-center justify-between gap-3">
        <p className="text-xs text-amber-700 dark:text-amber-400">
          {needsOrderCount > 0
            ? `${needsOrderCount} part${needsOrderCount !== 1 ? 's' : ''} needed across open tickets`
            : `${pendingCount} part${pendingCount !== 1 ? 's' : ''} in order queue`}
          {(queueSummary?.estimated_cost ?? 0) > 0 && (
            <> · Queue cost: <strong>${(queueSummary!.estimated_cost).toFixed(2)}</strong></>
          )}
        </p>
        <div className="flex items-center gap-2 flex-shrink-0">
          {Object.entries(supplierGroups).map(([source, group]) => (
            group.urls.length > 0 && (
              <button
                key={source}
                onClick={() => handleOpenAllForSupplier(source)}
                title={`Open all ${group.urls.length} part${group.urls.length !== 1 ? 's' : ''} from ${SUPPLIER_LABELS[source] || source} in new tabs`}
                className="inline-flex items-center gap-1.5 rounded-md bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 hover:bg-blue-100 dark:hover:bg-blue-900/50 px-2.5 py-1.5 text-xs font-medium transition-colors"
              >
                <ShoppingCart className="h-3 w-3" />
                Order All from {SUPPLIER_LABELS[source] || source} ({group.urls.length})
              </button>
            )
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

function QuickActions() {
  const navigate = useNavigate();

  // Fetch SMS unread count
  const { data: smsData } = useQuery({
    queryKey: ['sms-conversations-unread'],
    queryFn: () => smsApi.conversations(),
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });
  const smsUnread = useMemo(() => {
    const raw = smsData?.data?.data;
    const convos: any[] = Array.isArray(raw) ? raw : (raw?.conversations ?? []);
    return convos.reduce((sum: number, c: any) => sum + (c.unread_count ?? 0), 0);
  }, [smsData]);

  // Fetch parts to order count
  const { data: queueData } = useQuery({
    queryKey: ['order-queue-summary'],
    queryFn: () => catalogApi.getOrderQueueSummary(),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });
  const partsCount = queueData?.data?.data?.total_items ?? 0;

  const actions: { label: string; path: string; icon: typeof Plus; bg: string; hover: string; count: number }[] = [
    { label: 'New Check-in', path: '/pos', icon: Plus, bg: '#22c55e', hover: '#16a34a', count: 0 },
    { label: 'New Customer', path: '/customers/new', icon: Activity, bg: '#3b82f6', hover: '#2563eb', count: 0 },
    { label: 'Unread Messages', path: '/communications', icon: CheckCircle2, bg: '#a855f7', hover: '#9333ea', count: smsUnread },
    { label: 'Parts to Order', path: '/catalog', icon: DollarSign, bg: '#f59e0b', hover: '#d97706', count: partsCount },
  ];
  return (
    <div className="card p-4 mb-4">
      <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-3">Quick Actions</h2>
      <div className="grid grid-cols-2 gap-2">
        {actions.map((a) => {
          const Icon = a.icon;
          return (
            <button
              key={a.label}
              type="button"
              onClick={() => navigate(a.path)}
              style={{ backgroundColor: a.bg }}
              onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = a.hover; }}
              onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = a.bg; }}
              className="text-white rounded-lg px-3 py-2.5 text-sm font-medium flex items-center gap-2 transition-colors cursor-pointer relative z-10"
            >
              <Icon className="h-4 w-4 pointer-events-none" />
              <span className="pointer-events-none">{a.label}</span>
              {a.count > 0 && (
                <span className="ml-auto inline-flex items-center justify-center h-5 min-w-[20px] px-1.5 rounded-full bg-white/25 text-white text-xs font-bold pointer-events-none">
                  {a.count > 99 ? '99+' : a.count}
                </span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Today's Summary ─────────────────────────────────────────────────────────

interface DashboardSummary {
  open_tickets: number;
  revenue_today: number;
  closed_today: number;
  tickets_created_today: number;
  appointments_today: number;
  avg_repair_hours: number | null;
  status_groups?: {
    total: number;
    open: number;
    on_hold: number;
    closed: number;
    cancelled: number;
  };
  status_counts?: { id: number; name: string; color: string; count: number; is_closed: number; is_cancelled: number }[];
  // ENR-D enrichment fields
  revenue_trend?: { month: string; revenue: number }[];
  top_services?: { name: string; count: number; revenue: number }[];
  customer_trend?: { month: string; new_customers: number }[];
  inventory_value?: number;
  staff_leaderboard?: { name: string; tickets_closed: number; revenue: number }[];
}

function TodaySummary({ data, loading }: { data: DashboardSummary | null; loading: boolean }) {
  if (loading) {
    return (
      <div className="flex items-center gap-4 mb-4 px-1">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="h-5 w-24 bg-surface-200 dark:bg-surface-700 animate-pulse rounded" />
        ))}
      </div>
    );
  }
  if (!data) return null;

  // Compact inline stats — no card wrapper, just a quick status line
  const stats = [
    { label: 'Today', parts: [
      { text: `${data.tickets_created_today} created`, color: 'text-blue-500' },
      { text: `${data.closed_today} closed`, color: 'text-green-500' },
      { text: `${data.open_tickets} open`, color: 'text-amber-500' },
      ...(data.revenue_today > 0 ? [{ text: formatCurrency(data.revenue_today), color: 'text-emerald-500' }] : []),
      ...(data.appointments_today > 0 ? [{ text: `${data.appointments_today} appt${data.appointments_today > 1 ? 's' : ''}`, color: 'text-indigo-500' }] : []),
      ...(data.avg_repair_hours != null ? [{ text: `~${data.avg_repair_hours}h avg repair`, color: 'text-purple-500' }] : []),
    ]},
  ];

  return (
    <div className="flex items-center gap-2 mb-3 px-1 text-sm flex-wrap">
      <span className="font-medium text-surface-500 dark:text-surface-400">Today:</span>
      {stats[0].parts.map((p, i) => (
        <span key={i} className="flex items-center gap-1">
          {i > 0 && <span className="text-surface-300 dark:text-surface-600">·</span>}
          <span className={cn('font-medium', p.color)}>{p.text}</span>
        </span>
      ))}
    </div>
  );
}

// ─── Needs Attention ─────────────────────────────────────────────────────────

interface NeedsAttentionData {
  stale_tickets: { id: number; order_id: string; customer_name: string; days_stale: number; status: string }[];
  missing_parts_count: number;
  overdue_invoices: { id: number; order_id: string; customer_name: string; amount_due: number; days_overdue: number }[];
  low_stock_count: number;
}

function AttentionSection({ title, icon: Icon, iconBg, iconColor, count, children, defaultExpanded = true }: {
  title: string; icon: any; iconBg: string; iconColor: string; count: number;
  children: React.ReactNode; defaultExpanded?: boolean;
}) {
  const [expanded, setExpanded] = useState(defaultExpanded);
  if (count === 0) return null;
  return (
    <div>
      <button
        onClick={() => setExpanded(v => !v)}
        className="w-full flex items-center gap-2 px-4 py-2 bg-surface-50 dark:bg-surface-800/40 hover:bg-surface-100 dark:hover:bg-surface-800/60 transition-colors"
      >
        <div className={cn('h-5 w-5 rounded flex items-center justify-center flex-shrink-0', iconBg)}>
          <Icon className={cn('h-3 w-3', iconColor)} />
        </div>
        <span className="text-xs font-semibold text-surface-700 dark:text-surface-300 uppercase tracking-wider">{title}</span>
        <span className="ml-1 inline-flex items-center justify-center h-4 min-w-[16px] px-1 rounded-full bg-surface-200 dark:bg-surface-700 text-surface-600 dark:text-surface-400 text-[10px] font-bold">
          {count}
        </span>
        <svg
          className={cn('ml-auto h-3.5 w-3.5 text-surface-400 transition-transform', !expanded && '-rotate-90')}
          fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      {expanded && children}
    </div>
  );
}

function NeedsAttentionCard({ data, loading }: { data: NeedsAttentionData | null; loading: boolean }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [showAllStale, setShowAllStale] = useState(false);
  const [showAllInvoices, setShowAllInvoices] = useState(false);
  const SECTION_LIMIT = 5;

  // Load snooze state from server
  const { data: snoozedData } = useQuery({
    queryKey: ['prefs', 'attention_snoozed'],
    queryFn: () => preferencesApi.get('attention_snoozed'),
    staleTime: 30_000,
  });
  const snoozedMap: Record<string, number> = snoozedData?.data?.data ?? {};

  const { data: collapsedData } = useQuery({
    queryKey: ['prefs', 'attention_collapsed'],
    queryFn: () => preferencesApi.get('attention_collapsed'),
    staleTime: 30_000,
  });
  const collapsed = collapsedData?.data?.data === true;

  const isSnoozed = (key: string): boolean => {
    const until = snoozedMap[key];
    return !!until && Date.now() < until;
  };

  const toggleCollapsed = async () => {
    const next = !collapsed;
    try {
      await preferencesApi.set('attention_collapsed', next);
      queryClient.invalidateQueries({ queryKey: ['prefs', 'attention_collapsed'] });
    } catch (err) {
      // Server write failed — refetch so the UI reflects the unchanged value
      // instead of silently diverging from the server.
      console.error('[NeedsAttention] toggle-collapsed failed', err);
      toast.error('Could not save preference');
      queryClient.invalidateQueries({ queryKey: ['prefs', 'attention_collapsed'] });
    }
  };

  const handleSnooze = async (key: string, days: number, e: React.MouseEvent) => {
    e.stopPropagation();
    const updated = { ...snoozedMap, [key]: Date.now() + days * 86400_000 };
    try {
      await preferencesApi.set('attention_snoozed', updated);
      queryClient.invalidateQueries({ queryKey: ['prefs', 'attention_snoozed'] });
    } catch (err) {
      console.error('[NeedsAttention] snooze failed', err);
      toast.error('Could not snooze item');
      queryClient.invalidateQueries({ queryKey: ['prefs', 'attention_snoozed'] });
    }
  };

  if (loading) {
    return (
      <div className="card mb-4 p-6">
        <div className="flex items-center gap-2 mb-3">
          <div className="h-5 w-5 bg-surface-200 dark:bg-surface-700 animate-pulse rounded" />
          <div className="h-5 w-32 bg-surface-200 dark:bg-surface-700 animate-pulse rounded" />
        </div>
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-10 bg-surface-100 dark:bg-surface-800 animate-pulse rounded" />
          ))}
        </div>
      </div>
    );
  }

  if (!data) return null;

  // Filter out snoozed items
  const staleTickets = data.stale_tickets.filter(t => !isSnoozed(`stale-${t.id}`));
  const overdueInvoices = data.overdue_invoices.filter(inv => !isSnoozed(`inv-${inv.id}`));
  const showMissingParts = data.missing_parts_count > 0 && !isSnoozed('missing-parts');
  const showLowStock = data.low_stock_count > 0 && !isSnoozed('low-stock');

  const totalIssues = staleTickets.length + (showMissingParts ? 1 : 0) + overdueInvoices.length + (showLowStock ? 1 : 0);
  if (totalIssues === 0) return null;

  const visibleStale = showAllStale ? staleTickets : staleTickets.slice(0, SECTION_LIMIT);
  const visibleInvoices = showAllInvoices ? overdueInvoices : overdueInvoices.slice(0, SECTION_LIMIT);

  // Snooze button group (shows on hover)
  const SnoozeButtons = ({ itemKey }: { itemKey: string }) => (
    <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0" onClick={e => e.stopPropagation()}>
      {[3, 5, 10].map(d => (
        <button
          key={d}
          onClick={(e) => handleSnooze(itemKey, d, e)}
          className="px-1.5 py-0.5 text-[10px] font-medium rounded bg-surface-200 dark:bg-surface-700 text-surface-500 dark:text-surface-400 hover:bg-surface-300 dark:hover:bg-surface-600 transition-colors"
          title={`Snooze for ${d} days`}
        >
          +{d}d
        </button>
      ))}
    </div>
  );

  return (
    <div className="card border-l-4 border-l-red-400 mb-4">
      {/* Clickable header to collapse/expand */}
      <button
        onClick={toggleCollapsed}
        className="w-full p-4 border-b border-surface-100 dark:border-surface-800 flex items-center gap-2 hover:bg-surface-50 dark:hover:bg-surface-800/30 transition-colors"
      >
        <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0" />
        <h2 className="font-semibold text-surface-900 dark:text-surface-100">Needs Attention</h2>
        <span className="ml-1 inline-flex items-center justify-center h-5 min-w-[20px] px-1.5 rounded-full bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200 text-xs font-bold">
          {totalIssues}
        </span>
        <svg
          className={cn('ml-auto h-4 w-4 text-surface-400 transition-transform', collapsed && '-rotate-90')}
          fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {!collapsed && (
        <div className="divide-y divide-surface-100 dark:divide-surface-800">
          {/* Stale Tickets section */}
          <AttentionSection title={`Stale Tickets`} icon={Clock} iconBg="bg-amber-50 dark:bg-amber-900/30" iconColor="text-amber-500" count={staleTickets.length}>
            <div className="divide-y divide-surface-50 dark:divide-surface-800/50">
              {visibleStale.map((t) => (
                <div
                  key={`stale-${t.id}`}
                  onClick={() => navigate(`/tickets/${t.id}`)}
                  className="group flex items-center gap-3 px-4 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer"
                >
                  <div className="h-8 w-8 rounded-lg bg-amber-50 dark:bg-amber-900/30 flex items-center justify-center flex-shrink-0">
                    <Clock className="h-4 w-4 text-amber-500" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">
                      {t.order_id || `T-${String(t.id).padStart(4, '0')}`} — {t.customer_name}
                    </p>
                    <p className="text-xs text-surface-500">Stale for {t.days_stale} days · {t.status}</p>
                  </div>
                  <SnoozeButtons itemKey={`stale-${t.id}`} />
                  <span className={cn(
                    'text-xs font-medium px-2 py-0.5 rounded flex-shrink-0',
                    t.days_stale >= 7 ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300' : 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300'
                  )}>
                    {t.days_stale}d
                  </span>
                </div>
              ))}
              {staleTickets.length > SECTION_LIMIT && (
                <button
                  onClick={() => setShowAllStale(v => !v)}
                  className="w-full px-4 py-2 text-xs text-primary-600 dark:text-primary-400 hover:bg-surface-50 dark:hover:bg-surface-800/50 font-medium text-center"
                >
                  {showAllStale ? 'Show less' : `Show all (${staleTickets.length})`}
                </button>
              )}
            </div>
          </AttentionSection>

          {/* Overdue Invoices section */}
          <AttentionSection title={`Overdue Invoices`} icon={FileWarning} iconBg="bg-red-50 dark:bg-red-900/30" iconColor="text-red-500" count={overdueInvoices.length}>
            <div className="divide-y divide-surface-50 dark:divide-surface-800/50">
              {visibleInvoices.map((inv) => (
                <div
                  key={`inv-${inv.id}`}
                  onClick={() => navigate(`/invoices/${inv.id}`)}
                  className="group flex items-center gap-3 px-4 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer"
                >
                  <div className="h-8 w-8 rounded-lg bg-red-50 dark:bg-red-900/30 flex items-center justify-center flex-shrink-0">
                    <FileWarning className="h-4 w-4 text-red-500" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">
                      {inv.order_id || `INV-${String(inv.id).padStart(3, '0')}`} — {inv.customer_name}
                    </p>
                    <p className="text-xs text-surface-500">Overdue {inv.days_overdue} days · {formatCurrency(inv.amount_due)} due</p>
                  </div>
                  <SnoozeButtons itemKey={`inv-${inv.id}`} />
                  <span className="text-xs font-medium px-2 py-0.5 rounded bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 flex-shrink-0">
                    {formatCurrency(inv.amount_due)}
                  </span>
                </div>
              ))}
              {overdueInvoices.length > SECTION_LIMIT && (
                <button
                  onClick={() => setShowAllInvoices(v => !v)}
                  className="w-full px-4 py-2 text-xs text-primary-600 dark:text-primary-400 hover:bg-surface-50 dark:hover:bg-surface-800/50 font-medium text-center"
                >
                  {showAllInvoices ? 'Show less' : `Show all (${overdueInvoices.length})`}
                </button>
              )}
            </div>
          </AttentionSection>

          {/* Low Stock section */}
          <AttentionSection title={`Low Stock`} icon={BoxSelect} iconBg="bg-yellow-50 dark:bg-yellow-900/30" iconColor="text-yellow-600" count={showLowStock ? data.low_stock_count : 0}>
            <div
              onClick={() => navigate('/inventory?low_stock=true')}
              className="group flex items-center gap-3 px-4 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer"
            >
              <div className="h-8 w-8 rounded-lg bg-yellow-50 dark:bg-yellow-900/30 flex items-center justify-center flex-shrink-0">
                <BoxSelect className="h-4 w-4 text-yellow-600" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100">
                  {data.low_stock_count} item{data.low_stock_count !== 1 ? 's' : ''} at or below reorder level
                </p>
                <p className="text-xs text-surface-500">Inventory needs restocking</p>
              </div>
              <SnoozeButtons itemKey="low-stock" />
              <span className="text-xs font-medium px-2 py-0.5 rounded bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300 flex-shrink-0">
                {data.low_stock_count}
              </span>
            </div>
          </AttentionSection>

          {/* Missing parts */}
          {showMissingParts && (
            <AttentionSection title="Missing Parts" icon={PackageX} iconBg="bg-orange-50 dark:bg-orange-900/30" iconColor="text-orange-500" count={data.missing_parts_count}>
              <div
                onClick={() => navigate('/catalog')}
                className="group flex items-center gap-3 px-4 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer"
              >
                <div className="h-8 w-8 rounded-lg bg-orange-50 dark:bg-orange-900/30 flex items-center justify-center flex-shrink-0">
                  <PackageX className="h-4 w-4 text-orange-500" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-surface-900 dark:text-surface-100">
                    {data.missing_parts_count} missing part{data.missing_parts_count !== 1 ? 's' : ''} across open tickets
                  </p>
                  <p className="text-xs text-surface-500">Parts need ordering</p>
                </div>
                <SnoozeButtons itemKey="missing-parts" />
                <span className="text-xs font-medium px-2 py-0.5 rounded bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-300 flex-shrink-0">
                  {data.missing_parts_count}
                </span>
              </div>
            </AttentionSection>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────

// ─── Technician Dashboard ────────────────────────────────────────────────────

function TechDashboard({ userId }: { userId: number }) {
  const navigate = useNavigate();

  // Fetch only tickets assigned to this user
  const { data: queueData, isLoading: queueLoading } = useQuery({
    queryKey: ['my-queue', userId],
    queryFn: () => ticketApi.myQueue(),
    refetchInterval: 30_000,
    refetchIntervalInBackground: false,
  });
  const queue = queueData?.data?.data ?? { total: 0, open: 0, waiting_parts: 0, in_progress: 0 };

  // Fetch the actual assigned tickets
  const { data: ticketsData, isLoading: ticketsLoading } = useQuery({
    queryKey: ['my-tickets', userId],
    queryFn: () => ticketApi.list({ assigned_to: userId, pagesize: 20 }),
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });
  const myTickets = ticketsData?.data?.data?.tickets ?? ticketsData?.data?.data ?? [];

  // Today's summary
  const { data: summaryData, isLoading: summaryLoading } = useQuery({
    queryKey: ['dashboard-summary'],
    queryFn: () => reportApi.dashboard(),
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });
  const summary: DashboardSummary | null = summaryData?.data?.data ?? null;

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">My Dashboard</h1>
        <p className="text-surface-500 dark:text-surface-400">Your assigned tickets and workload</p>
      </div>

      {/* Queue stats */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <KpiCard label="My Tickets" value={String(queue.total)} loading={queueLoading} href="/tickets?assigned_to=me" />
        <KpiCard label="Open" value={String(queue.open)} loading={queueLoading} />
        <KpiCard label="In Progress" value={String(queue.in_progress)} loading={queueLoading} />
        <KpiCard label="Waiting Parts" value={String(queue.waiting_parts)} loading={queueLoading} />
      </div>

      {/* Today's Summary (non-financial items only) */}
      {summary && (
        <div className="card mb-4 px-3 md:px-4 py-3">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-2">
            <span className="text-sm font-medium text-surface-700 dark:text-surface-300">Tickets</span>
            <div className="flex items-center gap-2 md:gap-4 flex-wrap">
              {[
                { label: 'Total Created', count: summary.status_groups?.total ?? 0, color: '#9ca3af', statusGroup: '' },
                { label: 'Open', count: summary.status_groups?.open ?? summary.open_tickets, color: '#60a5fa', statusGroup: 'open' },
                { label: 'On Hold', count: summary.status_groups?.on_hold ?? 0, color: '#fb923c', statusGroup: 'on_hold' },
                { label: 'Closed', count: summary.status_groups?.closed ?? 0, color: '#4ade80', statusGroup: 'closed' },
                { label: 'Cancelled', count: summary.status_groups?.cancelled ?? 0, color: '#f87171', statusGroup: 'cancelled' },
              ].map((g) => (
                <button
                  key={g.label}
                  onClick={() => navigate(`/tickets${g.statusGroup ? `?status_group=${g.statusGroup}` : ''}`)}
                  className="inline-flex items-center gap-1.5 text-xs font-medium cursor-pointer rounded-lg px-2.5 py-1.5 hover:bg-surface-50 dark:hover:bg-surface-800 transition-all"
                >
                  <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: g.color }} />
                  <span className="text-surface-700 dark:text-surface-300">{g.label}</span>
                  <span className="font-bold text-sm" style={{ color: g.color }}>{g.count}</span>
                </button>
              ))}
            </div>
          </div>
          {/* Progress bar */}
          {(() => {
            const sg = summary.status_groups;
            if (!sg) return null;
            const barTotal = (sg.open + sg.on_hold + sg.closed) || 1;
            return (
              <div className="flex h-2 rounded-full overflow-hidden bg-surface-100 dark:bg-surface-800">
                {sg.open > 0 && <div style={{ width: `${(sg.open / barTotal) * 100}%`, backgroundColor: '#60a5fa' }} />}
                {sg.on_hold > 0 && <div style={{ width: `${(sg.on_hold / barTotal) * 100}%`, backgroundColor: '#fb923c' }} />}
                {sg.closed > 0 && <div style={{ width: `${(sg.closed / barTotal) * 100}%`, backgroundColor: '#4ade80' }} />}
              </div>
            );
          })()}
          {/* Per-status breakdown */}
          {(() => {
            const active = (summary.status_counts ?? []).filter(s => s.count > 0 && !s.is_closed && !s.is_cancelled);
            if (active.length === 0) return null;
            return (
              <div className="flex items-center gap-1 mt-2 flex-wrap text-xs text-surface-600 dark:text-surface-400">
                {active.map((s, i) => (
                  <span key={s.id} className="inline-flex items-center gap-1">
                    {i > 0 && <span className="text-surface-300 dark:text-surface-600 mx-0.5">&middot;</span>}
                    <span className="inline-block h-2 w-2 rounded-full flex-shrink-0" style={{ backgroundColor: s.color || '#9ca3af' }} />
                    <span>{s.name}: <strong className="text-surface-800 dark:text-surface-200">{s.count}</strong></span>
                  </span>
                ))}
              </div>
            );
          })()}
          {/* Today's activity row */}
          <div className="flex items-center gap-4 mt-2 text-xs text-surface-500 dark:text-surface-400">
            <span>Today: <strong className="text-surface-700 dark:text-surface-300">{summary.tickets_created_today}</strong> created</span>
            <span><strong className="text-green-600">{summary.closed_today}</strong> closed</span>
            {summary.avg_repair_hours != null && (
              <span>Avg repair: <strong className="text-surface-700 dark:text-surface-300">{summary.avg_repair_hours}h</strong></span>
            )}
            {summary.appointments_today > 0 && (
              <span><strong className="text-surface-700 dark:text-surface-300">{summary.appointments_today}</strong> appointments</span>
            )}
          </div>
        </div>
      )}

      {/* My Tickets list */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">My Assigned Tickets</h3>
          <button
            onClick={() => navigate('/tickets?assigned_to=me')}
            className="text-xs text-primary-600 hover:text-primary-700 font-medium"
          >
            View All
          </button>
        </div>
        <div className="overflow-x-auto max-h-96 overflow-y-auto">
          {ticketsLoading ? (
            <div className="flex items-center justify-center py-10">
              <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
            </div>
          ) : !myTickets.length ? (
            <div className="flex flex-col items-center justify-center py-10">
              <Ticket className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-2" />
              <p className="text-sm text-surface-400">No tickets assigned to you</p>
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">ID</th>
                  <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Customer</th>
                  <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Status</th>
                  <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Created</th>
                </tr>
              </thead>
              <tbody>
                {myTickets.map((t: any) => (
                  <tr
                    key={t.id}
                    onClick={() => navigate(`/tickets/${t.id}`)}
                    className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30 cursor-pointer"
                  >
                    <td className="px-4 py-2 font-medium text-primary-600 dark:text-primary-400 text-xs">
                      {formatTicketId(t.order_id || t.id)}
                    </td>
                    <td className="px-4 py-2 text-surface-700 dark:text-surface-300 text-xs truncate max-w-[150px]">
                      {t.customer_name || '--'}
                    </td>
                    <td className="px-4 py-2">
                      <span
                        className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium"
                        style={{ backgroundColor: `${t.status_color || '#888'}18`, color: t.status_color || '#888' }}
                      >
                        <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: t.status_color || '#888' }} />
                        {t.status_name || t.status || '--'}
                      </span>
                    </td>
                    <td className="px-4 py-2 text-surface-500 text-xs">
                      {t.created_at ? formatDate(t.created_at.slice(0, 10)) : '--'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Quick Actions */}
      <div className="mt-4">
        <QuickActions />
      </div>
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────

// ─── Widget Customization ────────────────────────────────────────────────────

interface WidgetConfig {
  id: string;
  label: string;
  visible: boolean;
  order: number;
}

const DEFAULT_WIDGETS: WidgetConfig[] = [
  { id: 'today-summary', label: "Today's Summary", visible: true, order: 0 },
  { id: 'team-workload', label: 'Team Workload', visible: true, order: 1 },
  { id: 'needs-attention', label: 'Needs Attention', visible: true, order: 2 },
  { id: 'kpi-cards', label: 'KPI Summary Cards', visible: true, order: 3 },
  { id: 'quick-actions', label: 'Quick Actions', visible: true, order: 4 },
  { id: 'sales-by-type', label: 'Sales By Item Type', visible: true, order: 5 },
  { id: 'tickets-and-sales', label: 'Recent Tickets & Daily Sales', visible: true, order: 6 },
  { id: 'missing-parts', label: 'Missing Parts', visible: true, order: 7 },
  { id: 'appointments', label: "Today's Appointments", visible: true, order: 8 },
  { id: 'revenue-trend', label: 'Revenue Trend', visible: true, order: 9 },
  { id: 'top-services', label: 'Top Services by Revenue', visible: true, order: 10 },
  { id: 'customer-trend', label: 'New Customer Trend', visible: true, order: 11 },
  { id: 'inventory-value', label: 'Inventory Value', visible: true, order: 12 },
  { id: 'staff-leaderboard', label: 'Staff Leaderboard', visible: true, order: 13 },
];

function mergeWithDefaults(saved: WidgetConfig[] | null): WidgetConfig[] {
  if (!saved || !Array.isArray(saved) || saved.length === 0) return [...DEFAULT_WIDGETS];
  // Merge: keep saved order/visibility, add any new defaults that aren't in saved
  const result: WidgetConfig[] = [];
  const savedMap = new Map(saved.map(w => [w.id, w]));
  // First, add all saved widgets that still exist in defaults
  const defaultIds = new Set(DEFAULT_WIDGETS.map(w => w.id));
  for (const s of saved) {
    if (defaultIds.has(s.id)) result.push({ ...s });
  }
  // Then add any new defaults not in saved
  for (const d of DEFAULT_WIDGETS) {
    if (!savedMap.has(d.id)) result.push({ ...d, order: result.length });
  }
  // Re-index orders
  return result.map((w, i) => ({ ...w, order: i }));
}

function WidgetCustomizeModal({ widgets, onSave, onClose }: {
  widgets: WidgetConfig[];
  onSave: (widgets: WidgetConfig[]) => void;
  onClose: () => void;
}) {
  const [draft, setDraft] = useState<WidgetConfig[]>(() => [...widgets]);

  const toggle = (id: string) => {
    setDraft(prev => prev.map(w => w.id === id ? { ...w, visible: !w.visible } : w));
  };

  const move = (index: number, dir: -1 | 1) => {
    const newIndex = index + dir;
    if (newIndex < 0 || newIndex >= draft.length) return;
    setDraft(prev => {
      const next = [...prev];
      [next[index], next[newIndex]] = [next[newIndex], next[index]];
      return next.map((w, i) => ({ ...w, order: i }));
    });
  };

  const reset = () => setDraft([...DEFAULT_WIDGETS]);

  // WEB-FX-003: Esc dismisses the customize modal.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="dashboard-customize-title"
        className="bg-white dark:bg-surface-900 rounded-xl shadow-xl w-full max-w-md mx-4"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 id="dashboard-customize-title" className="font-semibold text-surface-900 dark:text-surface-100">Customize Dashboard</h3>
          <button onClick={onClose} className="p-1 rounded hover:bg-surface-100 dark:hover:bg-surface-800 text-surface-400">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="p-4 max-h-[60vh] overflow-y-auto">
          <p className="text-xs text-surface-500 mb-3">Toggle widgets on/off and reorder them with the arrows.</p>
          <div className="space-y-1">
            {draft.map((w, i) => (
              <div key={w.id} className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800/50">
                <button
                  onClick={() => toggle(w.id)}
                  className={cn('p-1 rounded transition-colors', w.visible ? 'text-green-500 hover:text-green-600' : 'text-surface-300 hover:text-surface-400')}
                  title={w.visible ? 'Hide widget' : 'Show widget'}
                >
                  {w.visible ? <Eye className="h-4 w-4" /> : <EyeOff className="h-4 w-4" />}
                </button>
                <span className={cn('flex-1 text-sm', w.visible ? 'text-surface-900 dark:text-surface-100' : 'text-surface-400 line-through')}>
                  {w.label}
                </span>
                <div className="flex gap-0.5">
                  <button
                    onClick={() => move(i, -1)}
                    disabled={i === 0}
                    className="p-1 rounded hover:bg-surface-200 dark:hover:bg-surface-700 text-surface-400 disabled:opacity-30"
                  >
                    <ChevronUp className="h-3.5 w-3.5" />
                  </button>
                  <button
                    onClick={() => move(i, 1)}
                    disabled={i === draft.length - 1}
                    className="p-1 rounded hover:bg-surface-200 dark:hover:bg-surface-700 text-surface-400 disabled:opacity-30"
                  >
                    <ChevronDown className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-between p-4 border-t border-surface-100 dark:border-surface-800">
          <button
            onClick={reset}
            className="inline-flex items-center gap-1.5 text-xs text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
          >
            <RotateCcw className="h-3.5 w-3.5" /> Reset to Defaults
          </button>
          <div className="flex gap-2">
            <button onClick={onClose} className="px-3 py-1.5 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-800">
              Cancel
            </button>
            <button
              onClick={() => onSave(draft)}
              className="px-3 py-1.5 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 font-medium"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── DASH-2: Today's Appointments ────────────────────────────────────────────

function TodaysAppointments() {
  const navigate = useNavigate();
  // SCAN-1162: local-tz day boundaries — see localYmd comment above.
  const today = localYmd(new Date());
  const tomorrow = localYmd(new Date(Date.now() + 86400000));

  const { data: apptData, isLoading } = useQuery({
    queryKey: ['todays-appointments', today],
    queryFn: () => leadApi.appointments({ from_date: today, to_date: tomorrow }),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });

  const appointments: any[] = (apptData?.data as any)?.data?.appointments ?? (apptData?.data as any)?.data ?? [];

  return (
    <div className="card mb-4">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <CalendarClock className="h-5 w-5 text-indigo-500" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Today's Appointments</h3>
        </div>
        <button
          onClick={() => navigate('/calendar')}
          className="text-xs text-primary-600 hover:text-primary-700 font-medium"
        >
          View Calendar
        </button>
      </div>
      {isLoading ? (
        <div className="flex items-center justify-center py-8">
          <Loader2 className="h-5 w-5 animate-spin text-primary-500" />
        </div>
      ) : appointments.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-8 text-surface-400">
          <CalendarClock className="h-8 w-8 mb-2 text-surface-300 dark:text-surface-600" />
          <p className="text-sm">No appointments today</p>
        </div>
      ) : (
        <div className="divide-y divide-surface-100 dark:divide-surface-800">
          {appointments.map((appt: any) => {
            const startTime = appt.start_time ? new Date(appt.start_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }) : '--';
            const customerName = appt.customer_first_name
              ? `${appt.customer_first_name} ${appt.customer_last_name || ''}`.trim()
              : 'Walk-in';
            return (
              <div
                key={appt.id}
                onClick={() => appt.lead_id ? navigate(`/leads/${appt.lead_id}`) : undefined}
                className="flex items-center gap-3 px-4 py-3 hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer"
              >
                <div className="h-8 w-8 rounded-lg bg-indigo-50 dark:bg-indigo-900/30 flex items-center justify-center flex-shrink-0">
                  <CalendarClock className="h-4 w-4 text-indigo-500" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">
                    {customerName}
                  </p>
                  <p className="text-xs text-surface-500 truncate">
                    {appt.title || 'Appointment'}
                    {appt.assigned_first_name && <> &middot; {appt.assigned_first_name}</>}
                  </p>
                </div>
                <span className="text-xs font-medium text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-900/30 px-2 py-0.5 rounded flex-shrink-0">
                  {startTime}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ─── DASH-3: COGS Info Banner ────────────────────────────────────────────────

function CogsInfoBanner({ kpis }: { kpis: DashboardKpis | null }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [syncing, setSyncing] = useState(false);
  if (!kpis) return null;
  if (kpis.cogs !== 0 || kpis.total_sales === 0) return null;

  const handleSync = async () => {
    setSyncing(true);
    try {
      await catalogApi.syncCostPrices();
      toast.success('Cost prices synced from supplier catalog');
      // Refetch KPIs
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    } catch { toast.error('Sync failed'); }
    finally { setSyncing(false); }
  };

  return (
    <div className="mb-4 flex items-center gap-3 rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/20 px-4 py-2.5">
      <span className="text-lg">💡</span>
      <p className="flex-1 text-sm text-blue-700 dark:text-blue-300">
        Cost prices missing on some inventory items. Sync from supplier catalog or set manually.
      </p>
      <button
        onClick={handleSync}
        disabled={syncing}
        className="shrink-0 text-xs font-medium text-blue-600 dark:text-blue-400 hover:underline disabled:opacity-50"
      >
        {syncing ? 'Syncing...' : 'Sync from Catalog'}
      </button>
      <button
        onClick={() => navigate('/inventory')}
        className="shrink-0 text-xs font-medium text-blue-600 dark:text-blue-400 hover:underline"
      >
        Go to Inventory
      </button>
    </div>
  );
}

// ─── ENR-D1: Revenue Trend Widget ───────────────────────────────────────────

function RevenueTrendWidget({ data }: { data: DashboardSummary | null }) {
  const trend = data?.revenue_trend ?? [];
  if (trend.length === 0) return null;

  const maxRevenue = Math.max(...trend.map(m => m.revenue), 1);

  return (
    <div className="card mb-4">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <TrendingUp className="h-5 w-5 text-emerald-500" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Revenue Trend</h3>
        </div>
        <span className="text-xs text-surface-400">Last 12 months</span>
      </div>
      <div className="p-4">
        <div className="flex items-end gap-1" style={{ height: 120 }}>
          {trend.map((m) => {
            const pct = maxRevenue > 0 ? (m.revenue / maxRevenue) * 100 : 0;
            const label = m.month.slice(5); // "MM"
            return (
              <div key={m.month} className="flex-1 flex flex-col items-center gap-1">
                <div
                  className="w-full rounded-t bg-emerald-500/80 dark:bg-emerald-500/60 transition-all hover:bg-emerald-500"
                  style={{ height: `${Math.max(pct, 2)}%` }}
                  title={`${m.month}: ${formatCurrency(m.revenue)}`}
                />
                <span className="text-[10px] text-surface-400">{label}</span>
              </div>
            );
          })}
        </div>
        {/* Month-over-month comparison for last two months */}
        {trend.length >= 2 && (() => {
          const curr = trend[trend.length - 1].revenue;
          const prev = trend[trend.length - 2].revenue;
          const change = prev > 0 ? ((curr - prev) / prev) * 100 : 0;
          return (
            <div className="mt-3 text-xs text-surface-500 flex items-center gap-2">
              <span>Latest month: <strong className="text-surface-700 dark:text-surface-300">{formatCurrency(curr)}</strong></span>
              {prev > 0 && (
                <span className={change >= 0 ? 'text-green-600' : 'text-red-500'}>
                  {change >= 0 ? '+' : ''}{change.toFixed(1)}% vs prior month
                </span>
              )}
            </div>
          );
        })()}
      </div>
    </div>
  );
}

// ─── ENR-D2: Top Services Widget ────────────────────────────────────────────

function TopServicesWidget({ data }: { data: DashboardSummary | null }) {
  const navigate = useNavigate();
  const services = data?.top_services ?? [];
  if (services.length === 0) return null;

  const maxRev = Math.max(...services.map(s => s.revenue), 1);

  return (
    <div className="card mb-4">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <BadgeDollarSign className="h-5 w-5 text-blue-500" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Top Services by Revenue</h3>
        </div>
        <button
          onClick={() => navigate('/reports')}
          className="text-xs text-primary-600 hover:text-primary-700 font-medium"
        >
          View Reports
        </button>
      </div>
      <div className="divide-y divide-surface-100 dark:divide-surface-800">
        {services.map((s, i) => {
          const pct = maxRev > 0 ? (s.revenue / maxRev) * 100 : 0;
          return (
            <div key={s.name} className="px-4 py-3 flex items-center gap-3">
              <span className="text-xs font-bold text-surface-400 w-5 text-right">{i + 1}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{s.name}</p>
                <div className="mt-1 h-1.5 rounded-full bg-surface-100 dark:bg-surface-800 overflow-hidden">
                  <div className="h-full rounded-full bg-blue-500/70" style={{ width: `${pct}%` }} />
                </div>
              </div>
              <div className="text-right flex-shrink-0">
                <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{formatCurrency(s.revenue)}</p>
                <p className="text-[10px] text-surface-400">{s.count} job{s.count !== 1 ? 's' : ''}</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── ENR-D3: Customer Acquisition Trend ─────────────────────────────────────

function CustomerTrendWidget({ data }: { data: DashboardSummary | null }) {
  const trend = data?.customer_trend ?? [];
  if (trend.length === 0) return null;

  const maxCust = Math.max(...trend.map(m => m.new_customers), 1);

  return (
    <div className="card mb-4">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Activity className="h-5 w-5 text-purple-500" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">New Customer Trend</h3>
        </div>
        <span className="text-xs text-surface-400">Last 6 months</span>
      </div>
      <div className="p-4">
        <div className="flex items-end gap-2" style={{ height: 80 }}>
          {trend.map((m) => {
            const pct = maxCust > 0 ? (m.new_customers / maxCust) * 100 : 0;
            const monthLabel = new Date(m.month + '-01').toLocaleDateString('en-US', { month: 'short' });
            return (
              <div key={m.month} className="flex-1 flex flex-col items-center gap-1">
                <span className="text-[10px] font-medium text-surface-600 dark:text-surface-400">{m.new_customers}</span>
                <div
                  className="w-full rounded-t bg-purple-500/70 dark:bg-purple-500/50 transition-all hover:bg-purple-500"
                  style={{ height: `${Math.max(pct, 4)}%` }}
                  title={`${m.month}: ${m.new_customers} new customers`}
                />
                <span className="text-[10px] text-surface-400">{monthLabel}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ─── ENR-D4: Inventory Value Widget ─────────────────────────────────────────

function InventoryValueWidget({ data }: { data: DashboardSummary | null }) {
  const navigate = useNavigate();
  const value = data?.inventory_value;
  if (value == null || value === 0) return null;

  return (
    <div
      onClick={() => navigate('/inventory')}
      className="card mb-4 p-4 cursor-pointer hover:ring-2 hover:ring-primary-500/30 transition-shadow"
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="h-10 w-10 rounded-lg bg-amber-50 dark:bg-amber-900/30 flex items-center justify-center">
            <Package className="h-5 w-5 text-amber-500" />
          </div>
          <div>
            <p className="text-xs font-semibold text-amber-600 dark:text-amber-400 uppercase tracking-wider">Inventory Value</p>
            <p className="text-xl font-bold text-surface-900 dark:text-surface-100">{formatCurrency(value)}</p>
          </div>
        </div>
        <span className="text-xs text-surface-400">Cost at current stock levels</span>
      </div>
    </div>
  );
}

// ─── ENR-D5: Staff Leaderboard Widget ───────────────────────────────────────

function StaffLeaderboardWidget({ data }: { data: DashboardSummary | null }) {
  const staff = data?.staff_leaderboard ?? [];
  if (staff.length === 0) return null;

  return (
    <div className="card mb-4">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800">
        <div className="flex items-center gap-2">
          <Wallet className="h-5 w-5 text-indigo-500" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Staff Leaderboard</h3>
          <span className="text-xs text-surface-400 ml-auto">This month</span>
        </div>
      </div>
      <div className="divide-y divide-surface-100 dark:divide-surface-800">
        {staff.map((s, i) => (
          <div key={s.name} className="flex items-center gap-3 px-4 py-3">
            <div className={cn(
              'h-7 w-7 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0',
              i === 0 ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300'
                : i === 1 ? 'bg-surface-200 dark:bg-surface-700 text-surface-600 dark:text-surface-300'
                : i === 2 ? 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400'
                : 'bg-surface-100 dark:bg-surface-800 text-surface-500'
            )}>
              {i + 1}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{s.name}</p>
            </div>
            <div className="text-right flex-shrink-0">
              <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{s.tickets_closed} closed</p>
              <p className="text-[10px] text-surface-400">{formatCurrency(s.revenue)}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// AUDIT-D5: Separate daily sales widget that always fetches last 7 days
function DailySalesWidget({ last7Range, employeeId }: { last7Range: { from: string; to: string }; employeeId?: number }) {
  const navigate = useNavigate();
  const { data: salesKpiData, isLoading: salesLoading } = useQuery({
    queryKey: ['dashboard-kpis-7day', last7Range.from, last7Range.to, employeeId],
    queryFn: () => reportApi.dashboardKpis({ from_date: last7Range.from, to_date: last7Range.to, employee_id: employeeId }),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });
  const dailySales = salesKpiData?.data?.data?.daily_sales ?? [];

  return (
    <div className="card">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Daily Sales (Last 7 Days)</h3>
        <button
          onClick={() => navigate('/reports')}
          className="inline-flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 font-medium"
        >
          <Download className="h-3 w-3" /> Download Report
        </button>
      </div>
      <div className="overflow-x-auto max-h-80 overflow-y-auto">
        {salesLoading ? (
          <div className="flex items-center justify-center py-10">
            <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
          </div>
        ) : !dailySales.length ? (
          <div className="flex flex-col items-center justify-center py-10">
            <DollarSign className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-2" />
            <p className="text-sm text-surface-400">No sales data</p>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-white dark:bg-surface-900">
              <tr className="border-b border-surface-100 dark:border-surface-800">
                <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Date</th>
                <th className="text-right px-4 py-2 font-medium text-surface-500 text-xs">Sale</th>
                <th className="text-right px-4 py-2 font-medium text-surface-500 text-xs">COGS</th>
                <th className="text-right px-4 py-2 font-medium text-surface-500 text-xs">Net Profit</th>
                <th className="text-right px-4 py-2 font-medium text-surface-500 text-xs">Tax</th>
              </tr>
            </thead>
            <tbody>
              {dailySales.map((d: any) => {
                // RPT-DASH-UI1: Losses (negative net profit) must render in red
                // and be surfaced, not clamped to green. The server already
                // passes negative values through honestly (RPT5 fix) so the UI
                // should mirror that instead of painting every row green.
                const isLoss = typeof d.net_profit === 'number' && d.net_profit < 0;
                return (
                  <tr key={d.date} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-2 text-surface-900 dark:text-surface-100 text-xs">{formatDate(d.date)}</td>
                    <td className="px-4 py-2 text-right text-surface-900 dark:text-surface-100 text-xs font-medium">{formatCurrency(d.sale)}</td>
                    <td className="px-4 py-2 text-right text-surface-500 text-xs">{formatCurrency(d.cogs)}</td>
                    <td className={cn(
                      'px-4 py-2 text-right text-xs font-medium',
                      isLoss ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400',
                    )}>{formatCurrency(d.net_profit)}</td>
                    <td className="px-4 py-2 text-right text-surface-500 text-xs">{formatCurrency(d.tax)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

/**
 * Thin role router. Keeps the technician-only dashboard and the admin/manager
 * full dashboard as separate components so each gets a stable list of hooks
 * on every render. Previously the technician branch returned AFTER several
 * hooks had run, but BEFORE ~30 more hooks in the full dashboard body —
 * switching role mid-session would change the hook call count and trip
 * React's Rules of Hooks (SCAN-967).
 */
export function DashboardPage() {
  const user = useAuthStore((s) => s.user);
  const role = user?.role ?? 'technician';
  if (role === 'technician' && user?.id) {
    return <TechDashboard userId={user.id} />;
  }
  return <AdminOrManagerDashboard />;
}

function AdminOrManagerDashboard() {
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);
  const role = user?.role ?? 'technician';
  const [datePreset, setDatePreset] = useState<DatePreset>('thisMonth');
  const [employeeId, setEmployeeId] = useState<number | undefined>(undefined);
  const [showCustomize, setShowCustomize] = useState(false);
  const queryClient = useQueryClient();

  // Widget config
  const { data: widgetPrefData } = useQuery({
    queryKey: ['prefs', 'dashboard_widgets'],
    queryFn: () => preferencesApi.get('dashboard_widgets'),
    staleTime: 60_000,
  });
  const widgetConfig = useMemo(
    () => mergeWithDefaults(widgetPrefData?.data?.data ?? null),
    [widgetPrefData]
  );
  const isWidgetVisible = useCallback((id: string) => {
    const w = widgetConfig.find(c => c.id === id);
    return w ? w.visible : true;
  }, [widgetConfig]);

  const handleSaveWidgets = async (widgets: WidgetConfig[]) => {
    await preferencesApi.set('dashboard_widgets', widgets);
    queryClient.invalidateQueries({ queryKey: ['prefs', 'dashboard_widgets'] });
    setShowCustomize(false);
  };

  const { from, to } = useMemo(() => getDateRange(datePreset), [datePreset]);

  // admin and manager see the full dashboard (technician is routed away at
  // the DashboardPage level, so no early return here — keeps the hook list
  // stable across every render of this body).
  // FIXED-by-Fixer-A20 — WEB-FAE-001: routed through `useHasRole` so role-source
  // authority lives in one hook (matches `<PermissionBoundary>` semantics).
  const showFinancials = useHasRole(['admin', 'manager']);

  // Fetch KPIs
  const { data: kpiData, isLoading: kpiLoading } = useQuery({
    queryKey: ['dashboard-kpis', from, to, employeeId],
    queryFn: () => reportApi.dashboardKpis({ from_date: from, to_date: to, employee_id: employeeId }),
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });

  const kpis: DashboardKpis | null = kpiData?.data?.data ?? null;

  // Fetch users for employee filter
  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => settingsApi.getUsers(),
  });
  const users: { id: number; first_name: string; last_name: string }[] =
    usersData?.data?.data?.users || usersData?.data?.data || [];

  // Missing parts
  const { data: missingData } = useQuery({
    queryKey: ['missing-parts'],
    queryFn: () => missingPartsApi.list(),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });

  const { data: queueData } = useQuery({
    queryKey: ['order-queue-summary'],
    queryFn: () => catalogApi.getOrderQueueSummary(),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });

  const { data: queueItemsData } = useQuery({
    queryKey: ['order-queue-items'],
    queryFn: () => catalogApi.getOrderQueue('pending'),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });

  // Today's summary (basic dashboard KPIs)
  const { data: summaryData, isLoading: summaryLoading } = useQuery({
    queryKey: ['dashboard-summary'],
    queryFn: () => reportApi.dashboard(),
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });
  const summary: DashboardSummary | null = summaryData?.data?.data ?? null;

  // Needs attention
  const { data: attentionData, isLoading: attentionLoading } = useQuery({
    queryKey: ['needs-attention'],
    queryFn: () => reportApi.needsAttention(),
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });
  const needsAttention: NeedsAttentionData | null = attentionData?.data?.data ?? null;

  // Tech workload for manager emphasis
  const { data: workloadData } = useQuery({
    queryKey: ['tech-workload'],
    queryFn: () => reportApi.techWorkload(),
    enabled: role === 'manager',
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
  });
  const techWorkload: any[] = workloadData?.data?.data ?? [];

  const missingParts: MissingPart[] = missingData?.data?.data ?? [];
  const queueSummary: OrderQueueSummary | null = queueData?.data?.data ?? null;
  const queueItems: OrderQueueItem[] = queueItemsData?.data?.data?.items || queueItemsData?.data?.data || [];
  const hasMissingParts = missingParts.length > 0 || (queueSummary?.total_items ?? 0) > 0;

  // Day-1 onboarding state (audit section 42). Renders above KPIs when
  // the tenant is new. All surfaces are skippable — see GettingStartedWidget.
  const { data: onboardingData } = useQuery({
    queryKey: ['onboarding-state'],
    queryFn: () => onboardingApi.getState(),
    staleTime: 30_000,
  });
  const onboardingState: OnboardingState | null = onboardingData?.data?.data ?? null;

  // Phase B1: hide noisy BI widgets until shop has taken a real payment
  const isDayOne = !onboardingState?.first_payment_at;

  // Phase E1: fire milestone toasts on first_ticket_at / first_payment_at transitions
  useMilestoneToasts(onboardingState);

  return (
    <div>
      {/* Confetti + toast on new milestones (audit section 42, idea 9) */}
      <SuccessCelebration state={onboardingState} />

      {/* Getting-Started checklist (audit section 42, ideas 1, 2, 13) */}
      {onboardingState && !onboardingState.checklist_dismissed && (
        <GettingStartedWidget preloadedState={onboardingState} />
      )}

      {/* Phase B2: day-3/5/7 re-engagement nudges */}
      <DailyNudge preloadedState={onboardingState} />

      {/* Sample data toggle (audit section 42, idea 3) */}
      {onboardingState && (
        <SampleDataCard state={onboardingState} />
      )}

      {/* Header */}
      <div className="mb-4 md:mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl md:text-2xl font-bold text-surface-900 dark:text-surface-100">Dashboard</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">
            {role === 'manager' ? 'Team overview and shop performance' : 'Overview of your shop performance'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {hasMissingParts && (() => {
            const totalNeeded = missingParts.length + (queueSummary?.total_items ?? 0);
            return (
              <div className="flex items-center gap-2 bg-amber-50 dark:bg-amber-900/30 border border-amber-200 dark:border-amber-700 rounded-lg px-3 py-2">
                <AlertTriangle className="h-4 w-4 text-amber-500 flex-shrink-0" />
                <span className="text-sm text-amber-700 dark:text-amber-300 font-medium">
                  {totalNeeded} part{totalNeeded !== 1 ? 's' : ''} need ordering
                </span>
              </div>
            );
          })()}
          <button
            onClick={() => setShowCustomize(true)}
            className="p-2 rounded-lg hover:bg-surface-100 dark:hover:bg-surface-800 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 transition-colors"
            title="Customize dashboard widgets"
          >
            <Settings2 className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* ─── Phase B1: Day-1 Focus row — visible only before first payment ─── */}
      {isDayOne && (
        <div className="mb-6 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <button
            type="button"
            onClick={() => navigate('/pos')}
            className="flex items-center gap-3 rounded-xl border border-primary-200 bg-primary-50 px-4 py-3 text-left transition-colors hover:bg-primary-100 dark:border-primary-500/30 dark:bg-primary-500/10 dark:hover:bg-primary-500/20"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary-600 text-white">
              <ShoppingCart className="h-4 w-4" />
            </div>
            <div>
              <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">Open POS</p>
              <p className="text-xs text-surface-500 dark:text-surface-400">Check in your first customer</p>
            </div>
            <ArrowRight className="ml-auto h-4 w-4 text-primary-500" />
          </button>
          <button
            type="button"
            onClick={() => navigate('/customers/new')}
            className="flex items-center gap-3 rounded-xl border border-primary-200 bg-primary-50 px-4 py-3 text-left transition-colors hover:bg-primary-100 dark:border-primary-500/30 dark:bg-primary-500/10 dark:hover:bg-primary-500/20"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-teal-600 text-white">
              <Plus className="h-4 w-4" />
            </div>
            <div>
              <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">Add customer</p>
              <p className="text-xs text-surface-500 dark:text-surface-400">Create your first customer record</p>
            </div>
            <ArrowRight className="ml-auto h-4 w-4 text-primary-500" />
          </button>
        </div>
      )}

      {/* ─── Business Intelligence hero (audit 47) ────────────────────────
           Profit margin is the #1 thing owners should see. Rendered BEFORE
           the date range filter so it is the first data on the page.
           Phase B1: gated behind first_payment_at (isDayOne = false). */}
      {showFinancials && !isDayOne && (
        <div className="mb-6 space-y-4">
          <ProfitHeroCard />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <CashTrappedCard />
            <ChurnAlert />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <RepeatCustomersCard />
            <TechLeaderboard />
          </div>
          <BusyHoursHeatmap days={30} />
          <ForecastChart />
        </div>
      )}

      {/* Date range + Employee filter */}
      <div className="card mb-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 p-3">
          {/* Date preset buttons */}
          <div className="flex gap-1 flex-wrap">
            {DATE_PRESETS.map((dp) => (
              <button
                key={dp.key}
                onClick={() => setDatePreset(dp.key)}
                className={cn(
                  'px-3 py-1.5 text-xs font-medium rounded-lg transition-colors',
                  datePreset === dp.key
                    ? 'bg-primary-600 text-white'
                    : 'bg-surface-100 dark:bg-surface-800 text-surface-600 dark:text-surface-400 hover:bg-surface-200 dark:hover:bg-surface-700'
                )}
              >
                {dp.label}
              </button>
            ))}
          </div>

          {/* Employee filter */}
          <select
            value={employeeId ?? ''}
            onChange={(e) => setEmployeeId(e.target.value ? Number(e.target.value) : undefined)}
            className="rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm text-surface-700 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
          >
            <option value="">All Employees</option>
            {users.map((u) => (
              <option key={u.id} value={u.id}>{u.first_name} {u.last_name}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Widgets rendered in user-configured order */}
      {widgetConfig.map((w) => {
        if (!w.visible) return null;
        switch (w.id) {
          case 'today-summary':
            return <TodaySummary key={w.id} data={summary} loading={summaryLoading} />;

          case 'team-workload':
            if (role !== 'manager' || techWorkload.length === 0) return null;
            return (
              <div key={w.id} className="card mb-4">
                <div className="p-4 border-b border-surface-100 dark:border-surface-800">
                  <h3 className="font-semibold text-surface-900 dark:text-surface-100">Team Workload</h3>
                </div>
                <div className="divide-y divide-surface-100 dark:divide-surface-800">
                  {techWorkload.map((tech: any) => (
                    <div key={tech.id} className="flex items-center gap-4 px-4 py-3">
                      <div className="h-8 w-8 rounded-full bg-brand-100 dark:bg-brand-900/30 flex items-center justify-center text-sm font-bold text-brand-700 dark:text-brand-300 flex-shrink-0">
                        {tech.name.charAt(0)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{tech.name}</p>
                        <div className="flex gap-3 mt-0.5">
                          <span className="text-xs text-surface-500">{tech.open_tickets} open</span>
                          <span className="text-xs text-amber-600">{tech.in_progress} in progress</span>
                          <span className="text-xs text-red-500">{tech.waiting_parts} waiting parts</span>
                        </div>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{formatCurrency(tech.revenue_this_month)}</p>
                        <p className="text-xs text-surface-500">{tech.avg_repair_hours}h avg</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            );

          case 'needs-attention':
            return <NeedsAttentionCard key={w.id} data={needsAttention} loading={attentionLoading} />;

          case 'kpi-cards': {
            if (!showFinancials) return null;
            const allKpiCards = [
              { label: 'Total Sales', value: kpis?.total_sales ?? 0, tooltip: 'Sum of all payments in period', href: '/reports' },
              { label: 'Tax', value: kpis?.tax ?? 0, tooltip: 'Tax collected on invoices', href: '/reports' },
              { label: 'Discounts', value: kpis?.discounts ?? 0, tooltip: 'Total discounts applied', href: '/invoices' },
              { label: 'COGS', value: kpis?.cogs ?? 0, tooltip: 'Cost of goods sold (parts cost)', href: '/inventory' },
              { label: 'Net Profit', value: kpis?.net_profit ?? 0, tooltip: 'Sales minus COGS and discounts', href: '/reports' },
              { label: 'Refunds', value: kpis?.refunds ?? 0, tooltip: 'Total refunded amount', href: undefined },
              { label: 'Expenses', value: kpis?.expenses ?? 0, tooltip: 'Business expenses in period', href: '/expenses' },
              { label: 'Receivables', value: kpis?.receivables ?? 0, tooltip: 'Outstanding unpaid invoice amounts', href: '/invoices?status=unpaid' },
            ];
            const nonZero = allKpiCards.filter(c => c.value !== 0);
            const zeroCards = allKpiCards.filter(c => c.value === 0);
            return (
              <div key={w.id} className="mb-4">
                {nonZero.length > 0 && (
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    {nonZero.map(c => (
                      <KpiCard key={c.label} label={c.label} value={kpis ? formatCurrency(c.value) : '--'} tooltip={c.tooltip} loading={kpiLoading} href={c.href} />
                    ))}
                  </div>
                )}
                {zeroCards.length > 0 && (
                  <div className="flex flex-wrap gap-2 mt-2">
                    {zeroCards.map(c => (
                      <span
                        key={c.label}
                        onClick={c.href ? () => navigate(c.href!) : undefined}
                        className={cn(
                          'text-xs text-surface-400 dark:text-surface-500 bg-surface-50 dark:bg-surface-800/50 px-2 py-1 rounded',
                          c.href && 'cursor-pointer hover:text-surface-600 dark:hover:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 transition-colors'
                        )}
                        title={c.tooltip}
                      >
                        {c.label}: $0.00
                      </span>
                    ))}
                  </div>
                )}
                <CogsInfoBanner kpis={kpis} />
              </div>
            );
          }

          case 'quick-actions':
            return <QuickActions key={w.id} />;

          case 'sales-by-type': {
            if (!showFinancials || !kpis) return null;
            // AUDIT-D7: Hide rows where both qty and revenue are zero
            const nonZeroRows = kpis.sales_by_type.filter(row => row.quantity !== 0 || row.sales !== 0);
            if (nonZeroRows.length === 0) return null;
            return (
              <div key={w.id} className="card mb-4">
                <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
                  <h3 className="font-semibold text-surface-900 dark:text-surface-100">Sales By Item Type</h3>
                  <button
                    onClick={() => navigate('/reports')}
                    className="text-xs text-primary-600 hover:text-primary-700 font-medium"
                  >
                    View Report
                  </button>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-surface-100 dark:border-surface-800">
                        <th className="text-left px-4 py-3 font-medium text-surface-500">Type</th>
                        <th className="text-right px-4 py-3 font-medium text-surface-500">Qty</th>
                        <th className="text-right px-4 py-3 font-medium text-surface-500">Sales</th>
                        <th className="text-right px-4 py-3 font-medium text-surface-500">Discounts</th>
                        <th className="text-right px-4 py-3 font-medium text-surface-500">COGS</th>
                        <th className="text-right px-4 py-3 font-medium text-surface-500">Net Profit</th>
                        <th className="text-right px-4 py-3 font-medium text-surface-500">Tax</th>
                      </tr>
                    </thead>
                    <tbody>
                      {nonZeroRows.map((row) => (
                        <tr key={row.type} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                          <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{row.type}</td>
                          <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{row.quantity}</td>
                          <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(row.sales)}</td>
                          <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(row.discounts)}</td>
                          <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(row.cogs)}</td>
                          <td className="px-4 py-3 text-right font-medium text-green-600 dark:text-green-400">{formatCurrency(row.net_profit)}</td>
                          <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(row.tax)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            );
          }

          case 'tickets-and-sales': {
            // AUDIT-D6: Hide Assigned column if all tickets have no assignee
            const openTickets = kpis?.open_tickets ?? [];
            const hasAnyAssigned = openTickets.some(t => !!t.assigned_to);

            // AUDIT-D5: Always fetch last 7 days for daily sales, regardless of date filter
            const last7Range = getDateRange('last7');

            return (
              <div key={w.id} className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
                {/* Left: Repair Tickets (open) */}
                <div className="card">
                  <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
                    <h3 className="font-semibold text-surface-900 dark:text-surface-100">Repair Tickets</h3>
                    <button
                      onClick={() => navigate('/tickets')}
                      className="text-xs text-primary-600 hover:text-primary-700 font-medium"
                    >
                      View All
                    </button>
                  </div>
                  <div className="overflow-x-auto max-h-80 overflow-y-auto">
                    {kpiLoading ? (
                      <div className="flex items-center justify-center py-10">
                        <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
                      </div>
                    ) : !openTickets.length ? (
                      <div className="flex flex-col items-center justify-center py-10">
                        <Ticket className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-2" />
                        <p className="text-sm text-surface-400">No open tickets</p>
                      </div>
                    ) : (
                      <table className="w-full text-sm">
                        <thead className="sticky top-0 bg-white dark:bg-surface-900">
                          <tr className="border-b border-surface-100 dark:border-surface-800">
                            <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">ID</th>
                            <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Task</th>
                            {hasAnyAssigned && <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Assigned</th>}
                            <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Customer</th>
                            <th className="text-left px-4 py-2 font-medium text-surface-500 text-xs">Status</th>
                          </tr>
                        </thead>
                        <tbody>
                          {openTickets.map((t) => (
                            <tr
                              key={t.id}
                              onClick={() => navigate(`/tickets/${t.id}`)}
                              className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30 cursor-pointer"
                            >
                              <td className="px-4 py-2 font-medium text-primary-600 dark:text-primary-400 text-xs">
                                {formatTicketId(t.order_id || t.id)}
                              </td>
                              <td className="px-4 py-2 text-surface-700 dark:text-surface-300 text-xs max-w-[120px] truncate">
                                {t.task || '--'}
                              </td>
                              {hasAnyAssigned && (
                                <td className="px-4 py-2 text-xs">
                                  {t.assigned_to ? (
                                    <span className="text-surface-500">{t.assigned_to}</span>
                                  ) : (
                                    <span className="text-amber-500 font-medium">Unassigned</span>
                                  )}
                                </td>
                              )}
                              <td className="px-4 py-2 text-surface-500 text-xs max-w-[100px] truncate">{t.customer_name || '--'}</td>
                              <td className="px-4 py-2">
                                <span
                                  className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium"
                                  style={{ backgroundColor: `${t.status_color}18`, color: t.status_color }}
                                >
                                  <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: t.status_color }} />
                                  {t.status_name}
                                </span>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}
                  </div>
                </div>

                {/* Right: Daily Sales (last 7 days) - only for admin/manager */}
                {showFinancials && (
                  <DailySalesWidget last7Range={last7Range} employeeId={employeeId} />
                )}
              </div>
            );
          }

          case 'missing-parts':
            if (!hasMissingParts) return null;
            return <MissingPartsCard key={w.id} parts={missingParts} queueSummary={queueSummary} queueItems={queueItems} />;

          case 'appointments':
            return <TodaysAppointments key={w.id} />;

          case 'revenue-trend':
            if (!showFinancials) return null;
            return <RevenueTrendWidget key={w.id} data={summary} />;

          case 'top-services':
            return <TopServicesWidget key={w.id} data={summary} />;

          case 'customer-trend':
            return <CustomerTrendWidget key={w.id} data={summary} />;

          case 'inventory-value':
            return <InventoryValueWidget key={w.id} data={summary} />;

          case 'staff-leaderboard':
            if (!showFinancials) return null;
            return <StaffLeaderboardWidget key={w.id} data={summary} />;

          default:
            return null;
        }
      })}

      {/* Widget Customize Modal */}
      {showCustomize && (
        <WidgetCustomizeModal
          widgets={widgetConfig}
          onSave={handleSaveWidgets}
          onClose={() => setShowCustomize(false)}
        />
      )}
    </div>
  );
}
