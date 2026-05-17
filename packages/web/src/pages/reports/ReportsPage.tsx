import { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  DollarSign, Ticket, Users, Package, Receipt,
  Download, TrendingUp,
  Hash, UserCheck, Clock, Boxes, AlertTriangle, BarChart3,
  ShieldAlert, Smartphone, Cpu, UserPlus, Lock, FileText, Loader2, RefreshCw,
} from 'lucide-react';
import { api } from '@/api/client';
import { usePlanStore } from '@/stores/planStore';
import { toCsvRow } from '@/utils/csv';
import type { PlanFeatures } from '@bizarre-crm/shared';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell,
  LineChart, Line,
} from 'recharts';
import { reportApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate, timeAgo } from '@/utils/format';
import {
  CHART_PALETTE,
  CHART_COLOR_PRIMARY,
  CHART_COLOR_WARNING,
  CHART_COLOR_DANGER,
  CHART_COLOR_MUTED,
  CHART_TOOLTIP_STYLE,
} from './components/chartColors';
import { BusyHoursHeatmap } from '@/components/reports/BusyHoursHeatmap';
import { ChurnAlert } from '@/components/reports/ChurnAlert';
import { ForecastChart } from '@/components/reports/ForecastChart';
import { TechLeaderboard } from '@/components/reports/TechLeaderboard';
import { RepeatCustomersCard } from '@/components/reports/RepeatCustomersCard';
import { CashTrappedCard } from '@/components/reports/CashTrappedCard';
import { WarrantyClaimsTab } from './components/WarrantyClaimsTab';
import { DeviceModelsTab } from './components/DeviceModelsTab';
import { PartsUsageTab } from './components/PartsUsageTab';
import { TechnicianHoursTab } from './components/TechnicianHoursTab';
import { StalledTicketsTab } from './components/StalledTicketsTab';
import { CustomerAcquisitionTab } from './components/CustomerAcquisitionTab';
import { RefundsReportTab } from './components/RefundsReportTab';
import { SummaryCard, LoadingState, EmptyState, ErrorState } from './components/ReportHelpers';
import { DateRangePicker } from '@/components/shared/DateRangePicker';

// ─── Types ────────────────────────────────────────────────────────────────────

type Tab = 'sales' | 'tickets' | 'employees' | 'inventory' | 'tax' | 'insights'
  | 'warranty' | 'devices' | 'parts' | 'tech-hours' | 'stalled' | 'acquisition'
  | 'refunds';
type DateRangeState = { from?: string; to?: string; preset?: string };
type SalesGroupBy = 'day' | 'week' | 'month';
type InsightsSubTab = 'tickets' | 'sales';

interface SalesData {
  rows: { period: string; invoices: number; revenue: number; unique_customers: number }[];
  totals: { total_invoices: number; total_revenue: number; unique_customers: number; previous_revenue: number; revenue_change_pct: number | null };
  byMethod: { method: string; revenue: number; count: number }[];
  from: string;
  to: string;
}

interface TicketsData {
  byStatus: { status: string; color: string; count: number }[];
  byDay: { day: string; created: number }[];
  byTech: { tech_name: string; ticket_count: number; closed_count: number; total_revenue: number }[];
  summary: { total_created: number; total_closed: number; total_revenue: number; avg_ticket_value: number; avg_turnaround_hours: number | null };
  from: string;
  to: string;
}

interface EmployeesData {
  rows: { id: number; name: string; role: string; tickets_assigned: number; tickets_closed: number; commission_earned: number; hours_worked: number; revenue_generated: number }[];
  from: string;
  to: string;
}

interface InventoryData {
  lowStock: { id: number; name: string; sku: string; in_stock: number; reorder_level: number; retail_price: number; cost_price: number; item_type: string }[];
  valueSummary: { item_type: string; item_count: number; total_units: number; total_cost_value: number; total_retail_value: number }[];
  outOfStock: number;
  topMoving: { name: string; sku: string; used_qty: number; in_stock: number }[];
}

interface TaxData {
  rows: { tax_class: string; rate: number; tax_collected: number; revenue: number }[];
  from: string;
  to: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function toLocalDate(d: Date): string {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

function todayStr() {
  return toLocalDate(new Date());
}

function defaultFrom() {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return toLocalDate(d);
}

function defaultTo() {
  return todayStr();
}

/** Resolve a DateRangeValue (which may be a named preset) to concrete {from, to} strings. */
function resolveDateRange(value: { from?: string; to?: string; preset?: string }): { from: string; to: string } {
  const today = todayStr();
  const preset = value.preset;
  switch (preset) {
    case 'today':
      return { from: today, to: today };
    case 'yesterday': {
      const d = new Date();
      d.setDate(d.getDate() - 1);
      const y = toLocalDate(d);
      return { from: y, to: y };
    }
    case 'last_7': {
      // WEB-UIUX-924: subtract 6 days so the window is today + 6 prior days = 7 days inclusive.
      // Previously subtracted 7 which produced an 8-day window.
      const d = new Date();
      d.setDate(d.getDate() - 6);
      return { from: toLocalDate(d), to: today };
    }
    case 'last_30': {
      // WEB-UIUX-924: subtract 29 days so the window is today + 29 prior days = 30 days inclusive.
      // Previously subtracted 30 which produced a 31-day window.
      const d = new Date();
      d.setDate(d.getDate() - 29);
      return { from: toLocalDate(d), to: today };
    }
    case 'this_month':
      return { from: toLocalDate(new Date(new Date().getFullYear(), new Date().getMonth(), 1)), to: today };
    case 'last_month': {
      const now = new Date();
      return {
        from: toLocalDate(new Date(now.getFullYear(), now.getMonth() - 1, 1)),
        to: toLocalDate(new Date(now.getFullYear(), now.getMonth(), 0)),
      };
    }
    case 'this_year': {
      const now = new Date();
      return { from: toLocalDate(new Date(now.getFullYear(), 0, 1)), to: today };
    }
    case 'last_year': {
      const now = new Date();
      return {
        from: toLocalDate(new Date(now.getFullYear() - 1, 0, 1)),
        to: toLocalDate(new Date(now.getFullYear() - 1, 11, 31)),
      };
    }
    case 'all_time':
      // Lower bound chosen to predate any plausible repair-shop record while
      // staying above the SQLite epoch, so server date validators don't choke.
      return { from: '2000-01-01', to: today };
    default:
      return { from: value.from || defaultFrom(), to: value.to || today };
  }
}

function downloadCsv(filename: string, headers: string[], rows: string[][]) {
  // SCAN-1161: shared formula-injection-safe row serializer.
  const csvContent = [
    toCsvRow(headers),
    ...rows.map(toCsvRow),
  ].join('\n');
  // RPT-CSV2: Prepend UTF-8 BOM (\uFEFF) so Excel on Windows opens the file
  // with the correct encoding instead of garbling currency symbols and accented
  // characters in customer names.
  const blob = new Blob(['\uFEFF' + csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  // WEB-FC-022: revokeObjectURL synchronously after `.click()` races on
  // Firefox/Safari — the browser may not have started the download when the
  // URL is invalidated, cancelling the save. Defer cleanup so the navigation
  // for the blob URL has time to begin.
  setTimeout(() => {
    if (a.parentNode) a.parentNode.removeChild(a);
    URL.revokeObjectURL(url);
  }, 1000);
}

// ─── Error helpers ────────────────────────────────────────────────────────────

/**
 * WEB-W3-032: Extract a human-readable message from an axios/fetch error.
 * If the server returned a date-range cap error (400), surface the cap limit
 * and the admin-override note rather than the generic "Failed to load" string.
 */
function extractErrorMessage(err: unknown, fallback: string): string {
  if (!err) return fallback;
  const axiosMsg: string | undefined =
    (err as any)?.response?.data?.message ??
    (err as any)?.response?.data?.error;
  if (axiosMsg) return axiosMsg;
  const msg = (err as Error)?.message;
  return msg || fallback;
}

// ─── Tabs Config ──────────────────────────────────────────────────────────────

type ReportTabConfig = {
  key: Tab;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  proFeature?: keyof PlanFeatures;
};

// Free tier gets basic reports (sales, tickets, employees, inventory, tax).
// Pro-only reports require the `advancedReports` feature.
const TABS: ReportTabConfig[] = [
  { key: 'sales', label: 'Sales', icon: DollarSign },
  { key: 'tickets', label: 'Tickets', icon: Ticket },
  { key: 'employees', label: 'Employees', icon: Users },
  { key: 'inventory', label: 'Inventory', icon: Package },
  { key: 'tax', label: 'Tax', icon: Receipt },
  // WEB-UIUX-1397: per-refund breakdown — server's GET /refunds was unread
  // by Reports until now. Free tier; the data is already on Dashboard KPI.
  { key: 'refunds', label: 'Refunds', icon: Receipt },
  { key: 'insights', label: 'Insights', icon: BarChart3, proFeature: 'advancedReports' },
  { key: 'warranty', label: 'Warranty', icon: ShieldAlert, proFeature: 'advancedReports' },
  { key: 'devices', label: 'Devices', icon: Smartphone, proFeature: 'advancedReports' },
  { key: 'parts', label: 'Parts', icon: Cpu, proFeature: 'advancedReports' },
  { key: 'tech-hours', label: 'Tech Hours', icon: Clock, proFeature: 'advancedReports' },
  { key: 'stalled', label: 'Stalled', icon: AlertTriangle, proFeature: 'advancedReports' },
  { key: 'acquisition', label: 'Customers', icon: UserPlus, proFeature: 'advancedReports' },
];

const REPORT_TAB_KEYS = TABS.map((tab) => tab.key);
const DATE_RANGE_PRESETS = ['today', 'yesterday', 'last_7', 'last_30', 'this_month', 'last_month', 'this_year', 'last_year', 'all_time', 'custom'] as const;
const DEFAULT_REPORT_DATE_RANGE: DateRangeState = { preset: 'last_30' };
const REPORT_CHART_AXIS_TICK_FILL = 'var(--reports-chart-axis-tick, rgb(var(--surface-500)))';

function isValidTabParam(value: string | null): value is Tab {
  return !!value && REPORT_TAB_KEYS.includes(value as Tab);
}

function isValidYmd(value: string | null | undefined): value is string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year
    && date.getUTCMonth() === month - 1
    && date.getUTCDate() === day;
}

/**
 * BUGHUNT-2026-05-10-37: returns true when the caller-supplied range has BOTH
 * a valid `from` and `to` AND `from > to` — that's the case `normalizeDateRange`
 * silently rewrites to the default 7-day window. Callers use this to surface
 * a toast/banner instead of letting the rewrite happen invisibly.
 */
function isInvertedDateRange(value: DateRangeState): boolean {
  const from = isValidYmd(value.from) ? value.from : undefined;
  const to = isValidYmd(value.to) ? value.to : undefined;
  return Boolean(from && to && from > to);
}

function normalizeDateRange(value: DateRangeState): DateRangeState {
  const preset = value.preset;
  const isKnownPreset = !!preset && (DATE_RANGE_PRESETS as readonly string[]).includes(preset);
  if (preset && preset !== 'custom' && isKnownPreset) {
    return { preset };
  }

  const from = isValidYmd(value.from) ? value.from : undefined;
  const to = isValidYmd(value.to) ? value.to : undefined;
  if (from && to && from > to) {
    return { ...DEFAULT_REPORT_DATE_RANGE };
  }
  if ((isKnownPreset && preset === 'custom') || from || to) {
    return { preset: 'custom', from, to };
  }
  return { ...DEFAULT_REPORT_DATE_RANGE };
}

function dateRangeKey(value: DateRangeState): string {
  return `${value.preset ?? ''}|${value.from ?? ''}|${value.to ?? ''}`;
}

function readDateRangeParam(params: URLSearchParams): DateRangeState {
  return normalizeDateRange({
    preset: params.get('preset') ?? undefined,
    from: params.get('from') ?? undefined,
    to: params.get('to') ?? undefined,
  });
}

function writeDateRangeParam(params: URLSearchParams, value: DateRangeState) {
  const next = normalizeDateRange(value);
  params.delete('preset');
  params.delete('from');
  params.delete('to');
  if (next.preset && next.preset !== 'custom') {
    if (next.preset !== DEFAULT_REPORT_DATE_RANGE.preset) {
      params.set('preset', next.preset);
    }
    return;
  }
  if (next.preset === 'custom') params.set('preset', 'custom');
  if (next.from) params.set('from', next.from);
  if (next.to) params.set('to', next.to);
}

function readGroupByParam(params: URLSearchParams): SalesGroupBy {
  const value = params.get('groupBy');
  return value === 'week' || value === 'month' ? value : 'day';
}

function writeGroupByParam(params: URLSearchParams, value: SalesGroupBy) {
  if (value === 'day') params.delete('groupBy');
  else params.set('groupBy', value);
}

function readInsightsSubTabParam(params: URLSearchParams): InsightsSubTab {
  return params.get('subTab') === 'sales' ? 'sales' : 'tickets';
}

function writeInsightsSubTabParam(params: URLSearchParams, value: InsightsSubTab) {
  if (value === 'tickets') params.delete('subTab');
  else params.set('subTab', value);
}

function readCompareParam(params: URLSearchParams): boolean {
  const value = params.get('compare');
  return value === '1' || value === 'true';
}

function writeCompareParam(params: URLSearchParams, value: boolean) {
  if (value) params.set('compare', '1');
  else params.delete('compare');
}

// ─── Sales Tab ────────────────────────────────────────────────────────────────

function SalesTab({
  from,
  to,
  groupBy,
  onGroupByChange,
}: {
  from: string;
  to: string;
  groupBy: SalesGroupBy;
  onGroupByChange: (groupBy: SalesGroupBy) => void;
}) {
  const navigate = useNavigate();

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports', 'sales', from, to, groupBy],
    queryFn: async () => {
      const res = await reportApi.sales({ from_date: from, to_date: to, group_by: groupBy });
      return res.data.data as SalesData;
    },
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message={extractErrorMessage(error, 'Failed to load sales report')} />;

  const { totals, byMethod, rows } = data;

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="card flex items-center gap-4 p-5">
          <div className="flex items-center justify-center h-12 w-12 rounded-xl bg-green-50 dark:bg-green-950">
            <DollarSign className="h-6 w-6 text-green-500" />
          </div>
          <div>
            <p className="text-sm text-surface-500 dark:text-surface-400">Total Revenue</p>
            <p className="text-2xl font-bold text-surface-900 dark:text-surface-100">{formatCurrency(totals.total_revenue)}</p>
            {totals.revenue_change_pct != null && (
              <p className={`text-xs font-medium ${totals.revenue_change_pct >= 0 ? 'text-green-600' : 'text-red-500'}`}>
                {totals.revenue_change_pct >= 0 ? '+' : ''}{totals.revenue_change_pct?.toFixed(1) ?? '0.0'}% vs previous period
              </p>
            )}
          </div>
        </div>
        <SummaryCard
          label="Invoices" value={String(totals.total_invoices)}
          icon={Hash} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Unique Customers" value={String(totals.unique_customers)}
          icon={UserCheck} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
        />
      </div>

      {/* Payment Method Breakdown */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Payment Method Breakdown</h3>
        </div>
        {byMethod.length === 0 ? (
          <EmptyState message="No payment data for this period" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Method</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Transactions</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Revenue</th>
                </tr>
              </thead>
              <tbody>
                {byMethod.map((m) => (
                  <tr key={m.method} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 text-surface-900 dark:text-surface-100">{m.method || 'Unknown'}</td>
                    <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{m.count}</td>
                    <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(m.revenue)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Revenue by Period */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Revenue by Period</h3>
          <div className="flex gap-1 bg-surface-100 dark:bg-surface-800 rounded-lg p-0.5">
            {(['day', 'week', 'month'] as const).map((g) => (
              <button
                key={g}
                onClick={() => onGroupByChange(g)}
                className={cn(
                  'px-3 py-1 text-xs font-medium rounded-md transition-colors',
                  groupBy === g
                    ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                    : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
                )}
              >
                {g.charAt(0).toUpperCase() + g.slice(1)}
              </button>
            ))}
          </div>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No revenue data for this period" />
        ) : (
          <>
            {/* Revenue Line Chart — clickable dots navigate to invoices filtered by date */}
            {(() => {
              const rawChartData = (() => {
                const rowMap = new Map(rows.map(r => [r.period, r]));
                const result: { period: string; revenue: number | null; rawDate: string; rawFrom: string; rawTo: string; hasData: boolean }[] = [];
                const current = new Date(from + 'T00:00:00');
                const end = new Date(to + 'T00:00:00');
                const addPoint = (key: string, label: string, rawFrom: string, rawTo: string) => {
                  const row = rowMap.get(key);
                  result.push({
                    period: label,
                    revenue: row ? row.revenue : null,
                    rawDate: key,
                    rawFrom,
                    rawTo,
                    hasData: !!row,
                  });
                };

                if (groupBy === 'day') {
                  while (current <= end) {
                    const key = toLocalDate(current);
                    addPoint(key, formatDate(key), key, key);
                    current.setDate(current.getDate() + 1);
                  }
                } else if (groupBy === 'week') {
                  // Generate week start dates (Monday)
                  const day = current.getDay();
                  current.setDate(current.getDate() - (day === 0 ? 6 : day - 1)); // go to Monday
                  while (current <= end) {
                    const key = toLocalDate(current);
                    const weekEnd = new Date(current);
                    weekEnd.setDate(weekEnd.getDate() + 6);
                    const weekTo = toLocalDate(weekEnd);
                    const rawFrom = key < from ? from : key;
                    const rawTo = weekTo > to ? to : weekTo;
                    const label = `${formatDate(rawFrom)} – ${formatDate(rawTo)}`;
                    addPoint(key, label, rawFrom, rawTo);
                    current.setDate(current.getDate() + 7);
                  }
                } else {
                  // month — generate each month in range
                  current.setDate(1);
                  while (current <= end) {
                    const key = toLocalDate(current).slice(0, 7); // YYYY-MM
                    const monthStart = `${key}-01`;
                    const monthEnd = new Date(current.getFullYear(), current.getMonth() + 1, 0);
                    const monthTo = toLocalDate(monthEnd);
                    const rawFrom = monthStart < from ? from : monthStart;
                    const rawTo = monthTo > to ? to : monthTo;
                    const label = current.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
                    addPoint(key, label, rawFrom, rawTo);
                    current.setMonth(current.getMonth() + 1);
                  }
                }
                return result;
              })();

              const handleChartClick = (data: any) => {
                const point = data?.activePayload?.[0]?.payload;
                if (point?.hasData && point?.rawFrom && point?.rawTo) {
                  const params = new URLSearchParams({
                    from_date: point.rawFrom,
                    to_date: point.rawTo,
                  });
                  navigate(`/invoices?${params.toString()}`);
                }
              };

              return (
                <>
                  <div className="p-4" style={{ height: 260 }}>
                    <ResponsiveContainer width="100%" height="100%">
                      <LineChart data={rawChartData} onClick={handleChartClick} style={{ cursor: 'pointer' }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="currentColor" className="text-surface-200 dark:text-surface-700" />
                        <XAxis dataKey="period" tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                        {/* @audit-fixed: chart axis was hardcoded "$" — now uses formatCurrency to honor store currency */}
                        <YAxis tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} tickFormatter={(v: number) => formatCurrency(v)} />
                        <Tooltip
                          contentStyle={CHART_TOOLTIP_STYLE}
                          filterNull={false}
                          formatter={(value: any, _name: any, item: any) => [
                            item?.payload?.hasData ? formatCurrency(value) : 'Missing report row',
                            'Revenue',
                          ]}
                          labelFormatter={(label: string, payload: any[]) =>
                            payload?.[0]?.payload?.hasData
                              ? `${label} (click to view invoices)`
                              : `${label} (not returned by report API)`
                          }
                        />
                        <Line type="monotone" dataKey="revenue" stroke={CHART_COLOR_PRIMARY} strokeWidth={2} connectNulls={false} dot={{ r: 3 }} activeDot={{ r: 6, style: { cursor: 'pointer' } }} />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>
                  <p className="px-4 pb-3 text-xs text-surface-500 dark:text-surface-400">
                    Gaps mark periods the report API did not return. Returned periods with $0 revenue still render as $0 points.
                  </p>
                </>
              );
            })()}
            <div className="overflow-x-auto max-h-96 overflow-y-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-white dark:bg-surface-900">
                  <tr className="border-b border-surface-100 dark:border-surface-800">
                    <th className="text-left px-4 py-3 font-medium text-surface-500">Period</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Invoices</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Customers</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.period} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                      <td className="px-4 py-3 text-surface-900 dark:text-surface-100">{formatDate(r.period)}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{r.invoices}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{r.unique_customers}</td>
                      <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(r.revenue)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ─── Tickets Tab ──────────────────────────────────────────────────────────────

function TicketsTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports', 'tickets', from, to],
    queryFn: async () => {
      const res = await reportApi.tickets({ from_date: from, to_date: to });
      return res.data.data as TicketsData;
    },
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message={extractErrorMessage(error, 'Failed to load tickets report')} />;

  const { byStatus, byDay, byTech, summary } = data;

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
        <SummaryCard
          label="Created" value={String(summary.total_created)}
          icon={Ticket} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Closed" value={String(summary.total_closed)}
          icon={Ticket} color="text-green-500" bg="bg-green-50 dark:bg-green-950"
        />
        <SummaryCard
          label="Revenue" value={formatCurrency(summary.total_revenue)}
          icon={DollarSign} color="text-emerald-500" bg="bg-emerald-50 dark:bg-emerald-950"
        />
        <SummaryCard
          label="Avg Value" value={formatCurrency(summary.avg_ticket_value)}
          icon={TrendingUp} color="text-amber-500" bg="bg-amber-50 dark:bg-amber-950"
        />
        {/* WEB-UIUX-930: disclose that On-Hold / Awaiting-Customer time is excluded from
            this figure — server uses calculateAvgActiveRepairTime which strips hold time */}
        <SummaryCard
          label="Avg Turnaround" value={summary.avg_turnaround_hours != null ? `${summary.avg_turnaround_hours}h` : 'N/A'}
          icon={Clock} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
          tooltip="Active hours from create→close. On-Hold and Awaiting-Customer status time is excluded."
        />
      </div>

      {/* By Status */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">By Status</h3>
        </div>
        {byStatus.length === 0 ? (
          <EmptyState message="No tickets in this period" />
        ) : (
          <div className="p-4 flex flex-wrap gap-3">
            {byStatus.map((s) => (
              <div
                key={s.status}
                className="flex items-center gap-2 rounded-lg border border-surface-100 dark:border-surface-800 px-4 py-3"
              >
                <span
                  className="h-3 w-3 rounded-full flex-shrink-0"
                  style={{ backgroundColor: s.color }}
                />
                <span className="text-sm text-surface-700 dark:text-surface-300">{s.status}</span>
                <span className="text-lg font-bold text-surface-900 dark:text-surface-100">{s.count}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* By Technician */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">By Technician</h3>
        </div>
        {byTech.length === 0 ? (
          <EmptyState message="No assigned tickets in this period" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Technician</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Assigned</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Closed</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Revenue</th>
                </tr>
              </thead>
              <tbody>
                {byTech.map((t) => (
                  <tr key={t.tech_name} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 text-surface-900 dark:text-surface-100">{t.tech_name}</td>
                    <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{t.ticket_count}</td>
                    <td className="px-4 py-3 text-right text-green-600 dark:text-green-400">{t.closed_count}</td>
                    <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(t.total_revenue)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Tickets by Day */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Tickets Created by Day</h3>
        </div>
        {byDay.length === 0 ? (
          <EmptyState message="No tickets created in this period" />
        ) : (
          <div className="overflow-x-auto max-h-80 overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Date</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Created</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500 w-1/2">Volume</th>
                </tr>
              </thead>
              <tbody>
                {(() => {
                  // Hoist the max once: this was previously recomputed inside
                  // the map callback, making each row O(n) and the list O(n²)
                  // for up to 90 days of data.
                  const maxCreated = Math.max(...byDay.map((x) => x.created), 1);
                  return byDay.map((d) => {
                    const pct = (d.created / maxCreated) * 100;
                    return (
                      <tr key={d.day} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                        <td className="px-4 py-3 text-surface-900 dark:text-surface-100">{formatDate(d.day)}</td>
                        <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{d.created}</td>
                        <td className="px-4 py-3">
                          <div className="h-4 bg-surface-100 dark:bg-surface-800 rounded-full overflow-hidden">
                            <div
                              className="h-full bg-blue-500 rounded-full transition-all"
                              style={{ width: `${pct}%` }}
                            />
                          </div>
                        </td>
                      </tr>
                    );
                  });
                })()}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Employees Tab ────────────────────────────────────────────────────────────

interface TechWorkloadItem {
  id: number;
  name: string;
  open_tickets: number;
  in_progress: number;
  waiting_parts: number;
  avg_repair_hours: number;
  revenue_this_month: number;
}

const WORKLOAD_COLORS = CHART_PALETTE.slice(0, 6);

function TechWorkloadChart() {
  // WEB-FF-015 (Fixer-B17 2026-04-25): query previously destructured only
  // `{ data, isLoading }` — a 401 / 500 quietly fell through to the
  // "No technician workload data" empty-state, indistinguishable from a
  // shop with zero techs. Wire `isError` so a failed fetch surfaces as a
  // real ErrorState and managers know to refresh / re-auth.
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'tech-workload'],
    queryFn: async () => {
      const res = await reportApi.techWorkload();
      return res.data.data as TechWorkloadItem[];
    },
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load technician workload" />;
  if (!data || data.length === 0) return <EmptyState message="No technician workload data" />;

  const chartData = data.map((t) => ({
    name: t.name.split(' ')[0],
    'Open': t.open_tickets,
    'In Progress': t.in_progress,
    'Waiting Parts': t.waiting_parts,
  }));

  return (
    <div className="card mb-6">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Tech Workload Distribution</h3>
        <p className="text-xs text-surface-500 mt-0.5">Current open ticket distribution by technician</p>
      </div>
      <div className="p-4">
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartData} barCategoryGap="20%">
              <CartesianGrid strokeDasharray="3 3" stroke="currentColor" className="text-surface-200 dark:text-surface-700" />
              <XAxis dataKey="name" tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} />
              <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} />
              <Tooltip contentStyle={CHART_TOOLTIP_STYLE} />
              <Bar dataKey="Open" stackId="a" fill={CHART_COLOR_PRIMARY} radius={[0, 0, 0, 0]} />
              <Bar dataKey="In Progress" stackId="a" fill={CHART_COLOR_WARNING} />
              <Bar dataKey="Waiting Parts" stackId="a" fill={CHART_COLOR_DANGER} radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Summary cards per tech */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-4">
          {data.map((tech, i) => (
            <div key={tech.id} className="flex items-center gap-3 rounded-lg border border-surface-100 dark:border-surface-800 p-3">
              <div
                className="h-8 w-8 rounded-full flex items-center justify-center text-white text-xs font-bold flex-shrink-0"
                style={{ backgroundColor: WORKLOAD_COLORS[i % WORKLOAD_COLORS.length] }}
              >
                {tech.name.charAt(0)}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{tech.name}</p>
                <p className="text-xs text-surface-500">
                  {tech.open_tickets} open · {tech.avg_repair_hours}h avg · {formatCurrency(tech.revenue_this_month)}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function EmployeesTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports', 'employees', from, to],
    queryFn: async () => {
      const res = await reportApi.employees({ from_date: from, to_date: to });
      return res.data.data as EmployeesData;
    },
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message={extractErrorMessage(error, 'Failed to load employee report')} />;

  const { rows } = data;

  return (
    <div className="space-y-6">
      {/* Tech Workload Chart */}
      <TechWorkloadChart />

      {rows.length === 0 ? (
        <EmptyState message="No employee data for this period" />
      ) : (
        <div className="card">
          <div className="p-4 border-b border-surface-100 dark:border-surface-800">
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Employee Performance</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Name</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Role</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Assigned</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Closed</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Revenue</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Hours</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Commission</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.name}</td>
                    <td className="px-4 py-3">
                      <span className={cn(
                        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                        r.role === 'admin' ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400' :
                        r.role === 'manager' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400' :
                        'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                      )}>
                        {r.role}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{r.tickets_assigned}</td>
                    <td className="px-4 py-3 text-right text-green-600 dark:text-green-400">{r.tickets_closed}</td>
                    <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(r.revenue_generated)}</td>
                    <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{r.hours_worked.toFixed(1)}h</td>
                    <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(r.commission_earned)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Inventory Tab ────────────────────────────────────────────────────────────

function InventoryTab() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'inventory'],
    queryFn: async () => {
      const res = await reportApi.inventory();
      return res.data.data as InventoryData;
    },
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load inventory report" />;

  const { lowStock, valueSummary, outOfStock, topMoving } = data;

  return (
    <div className="space-y-6">
      {/* Out of stock alert */}
      {outOfStock > 0 && (
        <div className="card p-4 border-l-4 border-red-500 flex items-center gap-3">
          <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0" />
          <span className="text-sm text-surface-700 dark:text-surface-300">
            <strong className="text-red-600 dark:text-red-400">{outOfStock}</strong> items are completely out of stock
          </span>
        </div>
      )}

      {/* Value Summary Cards */}
      {valueSummary.length > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {valueSummary.map((vs) => (
            <div key={vs.item_type} className="card p-5">
              <div className="flex items-center gap-2 mb-3">
                <Boxes className="h-5 w-5 text-surface-400" />
                <span className="text-sm font-medium text-surface-500 capitalize">{vs.item_type}s</span>
              </div>
              <div className="space-y-1">
                <div className="flex justify-between text-sm">
                  <span className="text-surface-500">Items</span>
                  <span className="font-medium text-surface-900 dark:text-surface-100">{vs.item_count}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-surface-500">Units</span>
                  <span className="font-medium text-surface-900 dark:text-surface-100">{vs.total_units}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-surface-500">Cost Value</span>
                  <span className="font-medium text-surface-900 dark:text-surface-100">{formatCurrency(vs.total_cost_value)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-surface-500">Retail Value</span>
                  <span className="font-bold text-green-600 dark:text-green-400">{formatCurrency(vs.total_retail_value)}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Low Stock */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 text-amber-500" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Low Stock Items</h3>
          {lowStock.length > 0 && (
            <span className="ml-auto text-xs font-medium bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 rounded-full px-2 py-0.5">
              {lowStock.length} items
            </span>
          )}
        </div>
        {lowStock.length === 0 ? (
          <EmptyState message="All items are above reorder level" />
        ) : (
          <div className="overflow-x-auto max-h-96 overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Item</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">SKU</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">In Stock</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Reorder At</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Price</th>
                </tr>
              </thead>
              <tbody>
                {lowStock.map((item) => (
                  <tr key={item.id} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{item.name}</td>
                    <td className="px-4 py-3 text-surface-500 font-mono text-xs">{item.sku || '--'}</td>
                    <td className="px-4 py-3 text-right">
                      <span className={cn(
                        'font-bold',
                        item.in_stock === 0 ? 'text-red-600 dark:text-red-400' : 'text-amber-600 dark:text-amber-400'
                      )}>
                        {item.in_stock}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right text-surface-500">{item.reorder_level}</td>
                    <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(item.retail_price)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Top Moving Items (most used in repairs) */}
      {topMoving && topMoving.length > 0 && (
        <div className="card">
          <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center gap-2">
            <TrendingUp className="h-5 w-5 text-blue-500" />
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Top Moving Parts (Last 30 Days)</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Item</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">SKU</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Used</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">In Stock</th>
                </tr>
              </thead>
              <tbody>
                {topMoving.map((item, i) => (
                  <tr key={i} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{item.name}</td>
                    <td className="px-4 py-3 text-surface-500 font-mono text-xs">{item.sku || '--'}</td>
                    <td className="px-4 py-3 text-right font-bold text-blue-600 dark:text-blue-400">{item.used_qty}</td>
                    <td className="px-4 py-3 text-right">
                      <span className={cn(
                        'font-medium',
                        item.in_stock === 0 ? 'text-red-600 dark:text-red-400' :
                        item.in_stock <= 3 ? 'text-amber-600 dark:text-amber-400' :
                        'text-surface-900 dark:text-surface-100'
                      )}>
                        {item.in_stock}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Tax Tab ──────────────────────────────────────────────────────────────────

function TaxTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports', 'tax', from, to],
    queryFn: async () => {
      const res = await reportApi.tax({ from_date: from, to_date: to });
      return res.data.data as TaxData;
    },
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message={extractErrorMessage(error, 'Failed to load tax report')} />;

  const { rows } = data;
  const totalTax = rows.reduce((sum, r) => sum + (r.tax_collected || 0), 0);
  const totalRevenue = rows.reduce((sum, r) => sum + (r.revenue || 0), 0);

  return (
    <div className="space-y-6">
      {/* Summary */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <SummaryCard
          label="Total Tax Collected" value={formatCurrency(totalTax)}
          icon={Receipt} color="text-amber-500" bg="bg-amber-50 dark:bg-amber-950"
        />
        <SummaryCard
          label="Taxable Revenue" value={formatCurrency(totalRevenue)}
          icon={TrendingUp} color="text-green-500" bg="bg-green-50 dark:bg-green-950"
        />
      </div>

      {/* Breakdown */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Tax Class Breakdown</h3>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No tax data for this period" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Tax Class</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Rate</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Revenue</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Tax Collected</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.tax_class || 'No Tax Class'}</td>
                    <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{r.rate != null ? `${r.rate}%` : '--'}</td>
                    <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(r.revenue)}</td>
                    <td className="px-4 py-3 text-right font-bold text-surface-900 dark:text-surface-100">{formatCurrency(r.tax_collected)}</td>
                  </tr>
                ))}
                {/* Totals row */}
                <tr className="bg-surface-50 dark:bg-surface-800/30 font-semibold">
                  <td className="px-4 py-3 text-surface-900 dark:text-surface-100">Total</td>
                  <td className="px-4 py-3" />
                  <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(totalRevenue)}</td>
                  <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(totalTax)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Insights Tab ────────────────────────────────────────────────────────────

interface InsightsData {
  popular_models: { name: string; count: number }[];
  repairs_by_month: { month: string; count: number }[];
  revenue_by_model: { name: string; revenue: number }[];
  popular_services: { name: string; count: number }[];
}

const CHART_COLORS = CHART_PALETTE;

function InsightsTab({
  from,
  to,
  subTab,
  onSubTabChange,
  compare,
  onCompareChange,
}: {
  from: string;
  to: string;
  subTab: InsightsSubTab;
  onSubTabChange: (subTab: InsightsSubTab) => void;
  compare: boolean;
  onCompareChange: (compare: boolean) => void;
}) {
  // Calculate previous period (same duration, shifted back).
  // BUGHUNT-2026-05-16: previously the suffix was 'T00:00:00' (no 'Z'),
  // anchoring midnight to LOCAL time. Combined with `toLocalDate`'s UTC
  // round-trip below, the previous-period window could shift by a day in
  // non-UTC zones. Anchor to UTC explicitly to stay consistent.
  const fromMs = new Date(from + 'T00:00:00Z').getTime();
  const toMs = new Date(to + 'T00:00:00Z').getTime();
  const durationMs = toMs - fromMs;
  const prevFrom = toLocalDate(new Date(fromMs - durationMs - 86400_000));
  const prevTo = toLocalDate(new Date(fromMs - 86400_000));

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports', 'insights', from, to],
    queryFn: async () => {
      const res = await reportApi.insights({ from_date: from, to_date: to });
      return res.data.data as InsightsData;
    },
    staleTime: 30_000,
  });

  const { data: prevData } = useQuery({
    queryKey: ['reports', 'insights', prevFrom, prevTo],
    queryFn: async () => {
      const res = await reportApi.insights({ from_date: prevFrom, to_date: prevTo });
      return res.data.data as InsightsData;
    },
    enabled: compare,
    staleTime: 30_000,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message={extractErrorMessage(error, 'Failed to load insights data')} />;

  const { popular_models, repairs_by_month, revenue_by_model, popular_services } = data;

  // WEB-UIUX-926: Build comparison data for repairs by month keyed on month label,
  // not array index. Array-index pairing silently mismatches when the current and
  // previous periods span different months (e.g. a 3-month window shifted back 3
  // months produces different month keys at each position). A Map lookup is O(1)
  // and gracefully returns 0 when the prior period has no bucket for a given month.
  const prevRepairMap = prevData
    ? new Map(prevData.repairs_by_month.map((r) => [r.month, r.count]))
    : null;
  const comparisonRepairs = compare && prevData
    ? repairs_by_month.map((r) => ({
        month: r.month,
        current: r.count,
        previous: prevRepairMap?.get(r.month) ?? 0,
      }))
    : null;

  // Build comparison data for revenue by model
  const comparisonRevenue = compare && prevData
    ? revenue_by_model.map((r) => {
        const prev = prevData.revenue_by_model.find((p) => p.name === r.name);
        return { name: r.name, current: r.revenue, previous: prev?.revenue ?? 0 };
      })
    : null;

  return (
    <div className="space-y-6">
      {/* Sub-tabs + Compare toggle */}
      <div className="flex items-center gap-4">
        <div className="flex gap-1 bg-surface-100 dark:bg-surface-800 rounded-lg p-0.5 w-fit">
          {(['tickets', 'sales'] as const).map((t) => (
            <button
              key={t}
              onClick={() => onSubTabChange(t)}
              className={cn(
                'px-4 py-1.5 text-xs font-medium rounded-md transition-colors',
                subTab === t
                  ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                  : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
              )}
            >
              {t === 'tickets' ? 'Tickets' : 'Sales'}
            </button>
          ))}
        </div>
        <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
          <input
            type="checkbox"
            checked={compare}
            onChange={(e) => onCompareChange(e.target.checked)}
            className="h-3.5 w-3.5 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
          />
          <span className="text-surface-500 dark:text-surface-400">
            Compare with previous period
            {compare && <span className="ml-1 text-xs text-surface-400">({prevFrom} to {prevTo})</span>}
          </span>
        </label>
      </div>

      {subTab === 'tickets' ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Most Popular Model Repaired */}
          <div className="card">
            <div className="p-4 border-b border-surface-100 dark:border-surface-800">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100">Most Popular Model Repaired</h3>
            </div>
            {popular_models.length === 0 ? (
              <EmptyState message="No repair data for this period" />
            ) : (
              <div className="p-4" style={{ height: 320 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={popular_models} layout="vertical" margin={{ left: 10, right: 20, top: 5, bottom: 5 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                    <XAxis type="number" tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                    <YAxis dataKey="name" type="category" width={120} tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                    <Tooltip
                      contentStyle={CHART_TOOLTIP_STYLE}
                      formatter={(value: number) => [value, 'Repairs']}
                    />
                    <Bar dataKey="count" radius={[0, 4, 4, 0]}>
                      {popular_models.map((entry, i) => (
                        <Cell key={entry.name} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>

          {/* Number of Repairs by Month (with optional comparison) */}
          <div className="card">
            <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100">Number of Repairs</h3>
              {compare && (
                <div className="flex items-center gap-3 text-xs text-surface-500 dark:text-surface-400">
                  <span className="flex items-center gap-1"><span className="h-2.5 w-2.5 rounded-sm bg-blue-500" /> Current</span>
                  <span className="flex items-center gap-1"><span className="h-2.5 w-2.5 rounded-sm bg-surface-300" /> Previous</span>
                </div>
              )}
            </div>
            {repairs_by_month.length === 0 ? (
              <EmptyState message="No repair data for this period" />
            ) : (
              <div className="p-4" style={{ height: 320 }}>
                <ResponsiveContainer width="100%" height="100%">
                  {comparisonRepairs ? (
                    <BarChart data={comparisonRepairs} margin={{ left: 0, right: 20, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                      <XAxis dataKey="month" tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                      <YAxis tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                      <Tooltip
                        contentStyle={CHART_TOOLTIP_STYLE}
                      />
                      <Bar dataKey="previous" fill={CHART_COLOR_MUTED} radius={[4, 4, 0, 0]} name="Previous Period" />
                      <Bar dataKey="current" fill={CHART_COLOR_PRIMARY} radius={[4, 4, 0, 0]} name="Current Period" />
                    </BarChart>
                  ) : (
                    <BarChart data={repairs_by_month} margin={{ left: 0, right: 20, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                      <XAxis dataKey="month" tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                      <YAxis tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                      <Tooltip
                        contentStyle={CHART_TOOLTIP_STYLE}
                        formatter={(value: number) => [value, 'Tickets']}
                      />
                      <Bar dataKey="count" fill={CHART_COLOR_PRIMARY} radius={[4, 4, 0, 0]} />
                    </BarChart>
                  )}
                </ResponsiveContainer>
              </div>
            )}
          </div>

          {/* Most Popular Repair Services */}
          <div className="card lg:col-span-2">
            <div className="p-4 border-b border-surface-100 dark:border-surface-800">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100">Most Popular Repair Services</h3>
            </div>
            {popular_services.length === 0 ? (
              <EmptyState message="No service data for this period" />
            ) : (
              <div className="p-4" style={{ height: 320 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={popular_services} margin={{ left: 0, right: 20, top: 5, bottom: 5 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                    <XAxis dataKey="name" tick={{ fontSize: 10, fill: REPORT_CHART_AXIS_TICK_FILL }} angle={-20} textAnchor="end" height={60} />
                    <YAxis tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                    <Tooltip
                      contentStyle={CHART_TOOLTIP_STYLE}
                      formatter={(value: number) => [value, 'Count']}
                    />
                    <Bar dataKey="count" radius={[4, 4, 0, 0]}>
                      {popular_services.map((entry, i) => (
                        <Cell key={entry.name} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-6">
          {/* Revenue by Model */}
          <div className="card">
            <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100">Revenue by Model</h3>
              {compare && (
                <div className="flex items-center gap-3 text-xs text-surface-500 dark:text-surface-400">
                  <span className="flex items-center gap-1"><span className="h-2.5 w-2.5 rounded-sm bg-blue-500" /> Current</span>
                  <span className="flex items-center gap-1"><span className="h-2.5 w-2.5 rounded-sm bg-surface-300" /> Previous</span>
                </div>
              )}
            </div>
            {revenue_by_model.length === 0 ? (
              <EmptyState message="No revenue data for this period" />
            ) : (
              <div className="p-4" style={{ height: 400 }}>
                <ResponsiveContainer width="100%" height="100%">
                  {comparisonRevenue ? (
                    <BarChart data={comparisonRevenue} layout="vertical" margin={{ left: 10, right: 20, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                      {/* @audit-fixed (WEB-FF-003 / Fixer-UUU 2026-04-25): chart axes/tooltips honored hardcoded "$" — switched to formatCurrency for tenant currency */}
                      <XAxis type="number" tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} tickFormatter={(v: number) => formatCurrency(v)} />
                      <YAxis dataKey="name" type="category" width={140} tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                      <Tooltip
                        contentStyle={CHART_TOOLTIP_STYLE}
                        formatter={(value: number) => [formatCurrency(value)]}
                      />
                      <Bar dataKey="previous" fill={CHART_COLOR_MUTED} radius={[0, 4, 4, 0]} name="Previous Period" />
                      <Bar dataKey="current" fill={CHART_COLOR_PRIMARY} radius={[0, 4, 4, 0]} name="Current Period" />
                    </BarChart>
                  ) : (
                    <BarChart data={revenue_by_model} layout="vertical" margin={{ left: 10, right: 20, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                      <XAxis type="number" tick={{ fontSize: 12, fill: REPORT_CHART_AXIS_TICK_FILL }} tickFormatter={(v: number) => formatCurrency(v)} />
                      <YAxis dataKey="name" type="category" width={140} tick={{ fontSize: 11, fill: REPORT_CHART_AXIS_TICK_FILL }} />
                      <Tooltip
                        contentStyle={CHART_TOOLTIP_STYLE}
                        formatter={(value: number) => [formatCurrency(value), 'Revenue']}
                      />
                      <Bar dataKey="revenue" radius={[0, 4, 4, 0]}>
                        {revenue_by_model.map((entry, i) => (
                          <Cell key={entry.name} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                        ))}
                      </Bar>
                    </BarChart>
                  )}
                </ResponsiveContainer>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Main ReportsPage ─────────────────────────────────────────────────────────

export function ReportsPage() {
  // WEB-FK-010: report URLs carry validated view state for refresh/share links.
  const [searchParams, setSearchParams] = useSearchParams();
  const [activeTab, setActiveTabState] = useState<Tab>(() => (
    isValidTabParam(searchParams.get('tab')) ? searchParams.get('tab') as Tab : 'sales'
  ));
  const [dateRange, setDateRangeState] = useState<DateRangeState>(() => readDateRangeParam(searchParams));
  const [groupBy, setGroupByState] = useState<SalesGroupBy>(() => readGroupByParam(searchParams));
  const [insightsSubTab, setInsightsSubTabState] = useState<InsightsSubTab>(() => readInsightsSubTabParam(searchParams));
  const [compareInsights, setCompareInsightsState] = useState(() => readCompareParam(searchParams));
  const [exportLoading, setExportLoading] = useState(false);
  const [pdfLoading, setPdfLoading] = useState(false);
  const updateReportSearchParams = useCallback((write: (params: URLSearchParams) => void) => {
    setSearchParams((prev) => {
      const sp = new URLSearchParams(prev);
      write(sp);
      return sp;
    }, { replace: true });
  }, [setSearchParams]);

  useEffect(() => {
    const nextTab = isValidTabParam(searchParams.get('tab')) ? searchParams.get('tab') as Tab : 'sales';
    // BUGHUNT-2026-05-10-37: also warn when a bookmarked / hand-typed URL
    // carries an inverted range — readDateRangeParam silently drops it.
    const rawDateRange: DateRangeState = {
      preset: searchParams.get('preset') ?? undefined,
      from: searchParams.get('from') ?? undefined,
      to: searchParams.get('to') ?? undefined,
    };
    if (isInvertedDateRange(rawDateRange)) {
      toast.error(
        `URL range "${rawDateRange.from} → ${rawDateRange.to}" reversed — using default window instead.`,
        { duration: 6000 },
      );
    }
    const nextDateRange = readDateRangeParam(searchParams);
    const nextGroupBy = readGroupByParam(searchParams);
    const nextInsightsSubTab = readInsightsSubTabParam(searchParams);
    const nextCompareInsights = readCompareParam(searchParams);

    setActiveTabState((current) => current === nextTab ? current : nextTab);
    setDateRangeState((current) => dateRangeKey(current) === dateRangeKey(nextDateRange) ? current : nextDateRange);
    setGroupByState((current) => current === nextGroupBy ? current : nextGroupBy);
    setInsightsSubTabState((current) => current === nextInsightsSubTab ? current : nextInsightsSubTab);
    setCompareInsightsState((current) => current === nextCompareInsights ? current : nextCompareInsights);
  }, [searchParams]);

  const setActiveTab = useCallback((next: Tab) => {
    setActiveTabState(next);
    updateReportSearchParams((sp) => {
      if (next === 'sales') sp.delete('tab');
      else sp.set('tab', next);
    });
  }, [updateReportSearchParams]);
  const setDateRange = useCallback((next: DateRangeState) => {
    // BUGHUNT-2026-05-10-37: previously a from > to range was silently
    // rewritten to the default 7-day window, so fiscal/tax exports could
    // run over a different period than the user typed without any signal.
    // Surface the rewrite as an explicit toast and keep the normalize path
    // intact so the rest of the page still sees a valid range.
    if (isInvertedDateRange(next)) {
      toast.error(
        `Date range "${next.from} → ${next.to}" reversed — using default window instead. Set "from" before "to" and try again.`,
        { duration: 6000 },
      );
    }
    const normalized = normalizeDateRange(next);
    setDateRangeState(normalized);
    updateReportSearchParams((sp) => writeDateRangeParam(sp, normalized));
  }, [updateReportSearchParams]);
  const setGroupBy = useCallback((next: SalesGroupBy) => {
    setGroupByState(next);
    updateReportSearchParams((sp) => writeGroupByParam(sp, next));
  }, [updateReportSearchParams]);
  const setInsightsSubTab = useCallback((next: InsightsSubTab) => {
    setInsightsSubTabState(next);
    updateReportSearchParams((sp) => writeInsightsSubTabParam(sp, next));
  }, [updateReportSearchParams]);
  const setCompareInsights = useCallback((next: boolean) => {
    setCompareInsightsState(next);
    updateReportSearchParams((sp) => writeCompareParam(sp, next));
  }, [updateReportSearchParams]);
  const { from: fromDate, to: toDate } = resolveDateRange(dateRange);
  const queryClient = useQueryClient();

  // WEB-UIUX-931: derive the most-recent dataUpdatedAt for the active tab so we
  // can show an "Updated X ago" freshness indicator. We read directly from the
  // React Query cache so no extra network call is needed.
  const activeQueryKey = useMemo(() => {
    switch (activeTab) {
      case 'sales': return ['reports', 'sales', fromDate, toDate, groupBy];
      case 'tickets': return ['reports', 'tickets', fromDate, toDate];
      case 'employees': return ['reports', 'employees', fromDate, toDate];
      case 'inventory': return ['reports', 'inventory'];
      case 'tax': return ['reports', 'tax', fromDate, toDate];
      case 'insights': return ['reports', 'insights', fromDate, toDate];
      case 'warranty': return ['reports', 'warranty-claims', fromDate, toDate];
      case 'devices': return ['reports', 'device-models', fromDate, toDate];
      case 'parts': return ['reports', 'parts-usage', fromDate, toDate];
      case 'tech-hours': return ['reports', 'technician-hours', fromDate, toDate];
      case 'stalled': return ['reports', 'stalled-tickets', fromDate, toDate];
      case 'acquisition': return ['reports', 'customer-acquisition', fromDate, toDate];
      default: return null;
    }
  }, [activeTab, fromDate, toDate, groupBy]);

  const [dataUpdatedAt, setDataUpdatedAt] = useState<number | null>(null);
  useEffect(() => {
    if (!activeQueryKey) return;
    const refresh = () => {
      const state = queryClient.getQueryState(activeQueryKey);
      setDataUpdatedAt(state?.dataUpdatedAt ?? null);
    };
    refresh();
    return queryClient.getQueryCache().subscribe(() => refresh());
  }, [activeQueryKey, queryClient]);

  // Tier gating: reads plan features and exposes upgrade modal opener
  const planFeatures = usePlanStore((s) => s.features);
  const planHasFetched = usePlanStore((s) => s.hasFetched);
  const openUpgradeModal = usePlanStore((s) => s.openUpgradeModal);
  const isReportTabLocked = useCallback((tab: ReportTabConfig): boolean => {
    if (!tab.proFeature) return false;
    if (!planHasFetched) return false; // don't lock while loading
    return !planFeatures[tab.proFeature];
  }, [planFeatures, planHasFetched]);

  // Defense-in-depth: if user lands on a locked tab (e.g. via state restore or future
  // URL routing), kick them back to 'sales' and prompt for upgrade. Without this,
  // a free user could see the locked tab content render before the API 403s.
  useEffect(() => {
    if (!planHasFetched) return;
    const currentTab = TABS.find(t => t.key === activeTab);
    if (currentTab && isReportTabLocked(currentTab) && currentTab.proFeature) {
      openUpgradeModal(currentTab.proFeature);
      setActiveTab('sales');
    }
  }, [activeTab, planHasFetched, planFeatures, isReportTabLocked, openUpgradeModal, setActiveTab]);

  async function handleExport() {
    if (exportLoading) return;
    setExportLoading(true);
    try {
      const dateStr = `${fromDate}_to_${toDate}`;

      // Helper: use cached React Query data if available, otherwise fetch fresh.
      async function getCached<T>(queryKey: unknown[], fetcher: () => Promise<T>): Promise<T> {
        const cached = queryClient.getQueryData<T>(queryKey);
        if (cached !== undefined) return cached;
        return fetcher();
      }

      if (activeTab === 'sales') {
        const data = await getCached<SalesData>(
          ['reports', 'sales', fromDate, toDate, groupBy],
          async () => { const res = await reportApi.sales({ from_date: fromDate, to_date: toDate, group_by: groupBy }); return res.data.data as SalesData; },
        );
        downloadCsv(`sales_${dateStr}.csv`,
          ['Period', 'Invoices', 'Revenue', 'Unique Customers'],
          data.rows.map((r) => [r.period, String(r.invoices), String(r.revenue), String(r.unique_customers)]),
        );
      } else if (activeTab === 'tickets') {
        // WEB-UIUX-928: Expanded CSV to include all visible KPIs plus byStatus and
        // byTech breakdowns. The old export only wrote byDay (Day + Created), silently
        // omitting 5 summary KPIs, the status breakdown, and the technician table.
        // Three logical sections are written sequentially with a blank separator row
        // between them so the file stays valid CSV throughout.
        const data = await getCached<TicketsData>(
          ['reports', 'tickets', fromDate, toDate],
          async () => { const res = await reportApi.tickets({ from_date: fromDate, to_date: toDate }); return res.data.data as TicketsData; },
        );
        const { summary, byDay, byStatus, byTech } = data;
        // Build a multi-section CSV. Sections share the same file but are
        // separated by a blank row and a "--- Section ---" label row so the
        // operator can identify each block in a spreadsheet.
        const ticketCsvRows: string[][] = [
          // Section 1 – summary KPIs
          ['Total Created', 'Total Closed', 'Total Revenue', 'Avg Ticket Value', 'Avg Turnaround (hrs)'],
          [
            String(summary.total_created),
            String(summary.total_closed),
            String(summary.total_revenue),
            String(summary.avg_ticket_value),
            summary.avg_turnaround_hours != null ? String(summary.avg_turnaround_hours) : '',
          ],
          [], // blank separator
          // Section 2 – tickets by day
          ['--- By Day ---'],
          ['Day', 'Created'],
          ...byDay.map((r) => [r.day, String(r.created)]),
          [], // blank separator
          // Section 3 – by status
          ['--- By Status ---'],
          ['Status', 'Count'],
          ...byStatus.map((s) => [s.status, String(s.count)]),
          [], // blank separator
          // Section 4 – by technician
          ['--- By Technician ---'],
          ['Technician', 'Assigned', 'Closed', 'Revenue'],
          ...byTech.map((t) => [t.tech_name, String(t.ticket_count), String(t.closed_count), String(t.total_revenue)]),
        ];
        downloadCsv(
          `tickets_${dateStr}.csv`,
          ['--- Summary ---'],
          ticketCsvRows,
        );
      } else if (activeTab === 'employees') {
        const data = await getCached<EmployeesData>(
          ['reports', 'employees', fromDate, toDate],
          async () => { const res = await reportApi.employees({ from_date: fromDate, to_date: toDate }); return res.data.data as EmployeesData; },
        );
        downloadCsv(`employees_${dateStr}.csv`,
          ['Name', 'Role', 'Tickets Assigned', 'Hours Worked', 'Commission Earned'],
          data.rows.map((r) => [r.name, r.role, String(r.tickets_assigned), String(r.hours_worked), String(r.commission_earned)]),
        );
      } else if (activeTab === 'inventory') {
        const data = await getCached<InventoryData>(
          ['reports', 'inventory'],
          async () => { const res = await reportApi.inventory(); return res.data.data as InventoryData; },
        );
        downloadCsv(`inventory_low_stock.csv`,
          ['Name', 'SKU', 'In Stock', 'Reorder Level', 'Retail Price'],
          data.lowStock.map((r) => [r.name, r.sku, String(r.in_stock), String(r.reorder_level), String(r.retail_price)]),
        );
      } else if (activeTab === 'tax') {
        const data = await getCached<TaxData>(
          ['reports', 'tax', fromDate, toDate],
          async () => { const res = await reportApi.tax({ from_date: fromDate, to_date: toDate }); return res.data.data as TaxData; },
        );
        downloadCsv(`tax_${dateStr}.csv`,
          ['Tax Class', 'Rate %', 'Tax Collected', 'Revenue'],
          data.rows.map((r) => [r.tax_class, String(r.rate), String(r.tax_collected), String(r.revenue)]),
        );
      } else if (activeTab === 'insights') {
        const data = await getCached<InsightsData>(
          ['reports', 'insights', fromDate, toDate],
          async () => { const res = await reportApi.insights({ from_date: fromDate, to_date: toDate }); return res.data.data as InsightsData; },
        );
        const modelMap = new Map<string, { popularity: number; revenue: number }>();
        for (const m of data.popular_models) {
          const existing = modelMap.get(m.name);
          modelMap.set(m.name, { popularity: m.count, revenue: existing?.revenue ?? 0 });
        }
        for (const r of data.revenue_by_model) {
          const existing = modelMap.get(r.name);
          modelMap.set(r.name, { popularity: existing?.popularity ?? 0, revenue: r.revenue });
        }
        downloadCsv(`insights_${dateStr}.csv`,
          ['Model', 'Repair Count', 'Revenue'],
          Array.from(modelMap.entries()).map(([name, v]) => [name, String(v.popularity), String(v.revenue)]),
        );
      } else if (activeTab === 'warranty') {
        type WarrantyData = { rows: { model: string; claim_count: number; total_cost: number; avg_repair_cost: number }[] };
        const data = await getCached<WarrantyData>(
          ['reports', 'warranty-claims', fromDate, toDate],
          async () => { const res = await reportApi.warrantyClaims({ from_date: fromDate, to_date: toDate }); return res.data.data as WarrantyData; },
        );
        downloadCsv(`warranty_claims_${dateStr}.csv`,
          ['Model', 'Claims', 'Total Cost', 'Avg Cost'],
          data.rows.map((r) => [r.model, String(r.claim_count), String(r.total_cost), String(r.avg_repair_cost)]),
        );
      } else if (activeTab === 'devices') {
        type DevicesData = { rows: { model: string; repair_count: number; avg_ticket_total: number; total_parts_cost: number }[] };
        const data = await getCached<DevicesData>(
          ['reports', 'device-models', fromDate, toDate],
          async () => { const res = await reportApi.deviceModels({ from_date: fromDate, to_date: toDate }); return res.data.data as DevicesData; },
        );
        downloadCsv(`device_models_${dateStr}.csv`,
          ['Model', 'Repairs', 'Avg Ticket', 'Parts Cost'],
          data.rows.map((r) => [r.model, String(r.repair_count), String(r.avg_ticket_total), String(r.total_parts_cost)]),
        );
      } else if (activeTab === 'parts') {
        type PartsData = { rows: { part_name: string; sku: string; usage_count: number; total_qty_used: number; total_cost: number; supplier: string }[] };
        const data = await getCached<PartsData>(
          ['reports', 'parts-usage', fromDate, toDate],
          async () => { const res = await reportApi.partsUsage({ from_date: fromDate, to_date: toDate }); return res.data.data as PartsData; },
        );
        downloadCsv(`parts_usage_${dateStr}.csv`,
          ['Part', 'SKU', 'Times Used', 'Qty Used', 'Total Cost', 'Supplier'],
          data.rows.map((r) => [r.part_name, r.sku, String(r.usage_count), String(r.total_qty_used), String(r.total_cost), r.supplier]),
        );
      } else if (activeTab === 'tech-hours') {
        type TechHoursData = { rows: { tech_name: string; tickets_closed: number; total_revenue: number; hours_logged: number }[] };
        const data = await getCached<TechHoursData>(
          ['reports', 'technician-hours', fromDate, toDate],
          async () => { const res = await reportApi.technicianHours({ from_date: fromDate, to_date: toDate }); return res.data.data as TechHoursData; },
        );
        downloadCsv(`technician_hours_${dateStr}.csv`,
          ['Technician', 'Tickets Closed', 'Revenue', 'Hours Logged', '$/Hour'],
          data.rows.map((r) => [r.tech_name, String(r.tickets_closed), String(r.total_revenue), String(r.hours_logged.toFixed(1)), r.hours_logged > 0 ? String((r.total_revenue / r.hours_logged).toFixed(2)) : '0']),
        );
      } else if (activeTab === 'stalled') {
        type StalledData = { rows: { tech_name: string; stalled_count: number; ticket_ids: string; max_days_stalled: number }[] };
        const data = await getCached<StalledData>(
          ['reports', 'stalled-tickets', fromDate, toDate],
          async () => { const res = await reportApi.stalledTickets({ from_date: fromDate, to_date: toDate }); return res.data.data as StalledData; },
        );
        downloadCsv(`stalled_tickets_${dateStr}.csv`,
          ['Technician', 'Stalled Count', 'Max Days Stalled', 'Ticket IDs'],
          data.rows.map((r) => [r.tech_name, String(r.stalled_count), String(r.max_days_stalled), r.ticket_ids]),
        );
      } else if (activeTab === 'acquisition') {
        type AcquisitionData = { rows: { month: string; new_customers: number; acquisition_source: string }[] };
        const data = await getCached<AcquisitionData>(
          ['reports', 'customer-acquisition', fromDate, toDate],
          async () => { const res = await reportApi.customerAcquisition({ from_date: fromDate, to_date: toDate }); return res.data.data as AcquisitionData; },
        );
        downloadCsv(`customer_acquisition_${dateStr}.csv`,
          ['Month', 'Source', 'New Customers'],
          data.rows.map((r) => [r.month, r.acquisition_source, String(r.new_customers)]),
        );
      }
    } catch {
      toast.error('Export failed');
    } finally {
      setExportLoading(false);
    }
  }

  async function handleSalesPdf() {
    if (pdfLoading) return;
    setPdfLoading(true);
    try {
      const url = reportApi.salesReportPdfUrl(fromDate, toDate);
      await api.get(url, { responseType: 'text' });
      window.open(url, '_blank', 'noopener');
    } catch (err: any) {
      const msg = extractErrorMessage(err, 'Failed to generate PDF');
      toast.error(msg);
    } finally {
      setPdfLoading(false);
    }
  }

  return (
    <div className="[--reports-chart-axis-tick:rgb(var(--surface-500))] dark:[--reports-chart-axis-tick:rgb(var(--surface-400))]">
      {/* Header */}
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Reports</h1>
          <p className="text-surface-500 dark:text-surface-400">Analyze your business performance</p>
        </div>
        <div className="flex flex-col items-start gap-2 sm:items-end">
          <button
            type="button"
            onClick={handleExport}
            disabled={exportLoading}
            aria-busy={exportLoading}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-surface-700 dark:text-surface-300 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
          >
            {exportLoading ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Exporting...
              </>
            ) : (
              <>
                <Download className="h-4 w-4" aria-hidden="true" />
                Export
              </>
            )}
          </button>
          {activeTab === 'sales' && (
            <button
              type="button"
              onClick={handleSalesPdf}
              disabled={pdfLoading}
              aria-busy={pdfLoading}
              className="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium text-surface-700 dark:text-surface-300 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
              title="Open print-ready PDF in a new tab"
            >
              {pdfLoading ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                  Generating…
                </>
              ) : (
                <>
                  <FileText className="h-4 w-4" aria-hidden="true" />
                  PDF
                </>
              )}
            </button>
          )}
        </div>
      </div>

      {/* Date Range — applies to all tabs except Inventory */}
      {activeTab !== 'inventory' && (
        <div className="card mb-2">
          <div className="flex items-center gap-2 px-3 py-1.5">
            <Clock className="h-3.5 w-3.5 text-surface-400 shrink-0" />
            <span className="text-xs font-medium text-surface-500 dark:text-surface-400 shrink-0">Period:</span>
            <DateRangePicker
              value={dateRange}
              onChange={setDateRange}
            />
            {/* WEB-UIUX-931: show "Updated X ago" so users know how fresh the
                cached data is (staleTime: 30_000 makes staleness opaque otherwise). */}
            {dataUpdatedAt != null && (
              <span className="ml-auto flex items-center gap-1 text-xs text-surface-400 dark:text-surface-500 select-none">
                <RefreshCw className="h-3 w-3 shrink-0" aria-hidden="true" />
                Updated {timeAgo(new Date(dataUpdatedAt).toISOString())}
              </span>
            )}
          </div>
        </div>
      )}

      {/* Tab navigation */}
      <div className="card mb-3">
        <div className="p-1.5">
          <div
            role="tablist"
            aria-label="Report sections"
            className="flex flex-wrap gap-1 rounded-lg bg-surface-100 p-1 dark:bg-surface-800"
          >
            {TABS.map((tab) => {
              const Icon = tab.icon;
              const locked = isReportTabLocked(tab);
              const selected = activeTab === tab.key;
              return (
                <button
                  key={tab.key}
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  aria-label={locked ? `${tab.label} report, requires Pro plan` : `${tab.label} report`}
                  onClick={() => {
                    if (locked && tab.proFeature) {
                      openUpgradeModal(tab.proFeature);
                      return;
                    }
                    setActiveTab(tab.key);
                  }}
                  className={cn(
                    'flex min-w-0 flex-1 items-center justify-center gap-1.5 whitespace-nowrap rounded-md px-2.5 py-1 text-xs font-medium transition-colors sm:text-sm',
                    selected
                      ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                      : locked
                        ? 'text-surface-400 hover:text-surface-600 dark:text-surface-500 dark:hover:text-surface-400'
                        : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
                  )}
                  title={locked ? `${tab.label} requires Pro plan` : undefined}
                >
                  <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
                  <span>{tab.label}</span>
                  {locked && (
                    <>
                      <Lock className="h-3 w-3 shrink-0 text-amber-500" aria-hidden="true" />
                      <span className="sr-only">requires Pro plan</span>
                    </>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      {/* Tab Content */}
      {activeTab === 'sales' && (
        <SalesTab
          from={fromDate}
          to={toDate}
          groupBy={groupBy}
          onGroupByChange={setGroupBy}
        />
      )}
      {activeTab === 'tickets' && <TicketsTab from={fromDate} to={toDate} />}
      {activeTab === 'employees' && <EmployeesTab from={fromDate} to={toDate} />}
      {activeTab === 'inventory' && <InventoryTab />}
      {activeTab === 'tax' && <TaxTab from={fromDate} to={toDate} />}
      {activeTab === 'refunds' && <RefundsReportTab from={fromDate} to={toDate} />}
      {activeTab === 'insights' && (
        <>
          <InsightsTab
            from={fromDate}
            to={toDate}
            subTab={insightsSubTab}
            onSubTabChange={setInsightsSubTab}
            compare={compareInsights}
            onCompareChange={setCompareInsights}
          />
          {/* Heavy BI widgets relocated here from the dashboard 2026-05-09
              so the home page stays glance-friendly. Insights tab is the
              right home for deep customer / staffing / forecast surfaces. */}
          <div className="mt-6 space-y-4">
            <CashTrappedCard />
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <RepeatCustomersCard />
              <ChurnAlert />
            </div>
            <TechLeaderboard />
            <BusyHoursHeatmap days={30} />
            <ForecastChart />
          </div>
        </>
      )}
      {activeTab === 'warranty' && <WarrantyClaimsTab from={fromDate} to={toDate} />}
      {activeTab === 'devices' && <DeviceModelsTab from={fromDate} to={toDate} />}
      {activeTab === 'parts' && <PartsUsageTab from={fromDate} to={toDate} />}
      {activeTab === 'tech-hours' && <TechnicianHoursTab from={fromDate} to={toDate} />}
      {activeTab === 'stalled' && <StalledTicketsTab from={fromDate} to={toDate} />}
      {activeTab === 'acquisition' && <CustomerAcquisitionTab from={fromDate} to={toDate} />}
    </div>
  );
}
