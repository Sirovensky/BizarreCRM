import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  DollarSign, Ticket, Users, Package, Receipt,
  Download, TrendingUp,
  Hash, UserCheck, Clock, Boxes, AlertTriangle, BarChart3,
  ShieldAlert, Smartphone, Cpu, UserPlus, Lock,
} from 'lucide-react';
import { usePlanStore } from '@/stores/planStore';
import type { PlanFeatures } from '@bizarre-crm/shared';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell,
  LineChart, Line,
} from 'recharts';
import { reportApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';
import { WarrantyClaimsTab } from './components/WarrantyClaimsTab';
import { DeviceModelsTab } from './components/DeviceModelsTab';
import { PartsUsageTab } from './components/PartsUsageTab';
import { TechnicianHoursTab } from './components/TechnicianHoursTab';
import { StalledTicketsTab } from './components/StalledTicketsTab';
import { CustomerAcquisitionTab } from './components/CustomerAcquisitionTab';
import { SummaryCard, LoadingState, EmptyState, ErrorState } from './components/ReportHelpers';
import { DateRangePicker } from '@/components/shared/DateRangePicker';

// ─── Types ────────────────────────────────────────────────────────────────────

type Tab = 'sales' | 'tickets' | 'employees' | 'inventory' | 'tax' | 'insights'
  | 'warranty' | 'devices' | 'parts' | 'tech-hours' | 'stalled' | 'acquisition';

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

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function defaultFrom() {
  const d = new Date(Date.now() - 30 * 86400_000);
  return d.toISOString().slice(0, 10);
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
      const y = new Date(Date.now() - 86400_000).toISOString().slice(0, 10);
      return { from: y, to: y };
    }
    case 'last_7':
      return { from: new Date(Date.now() - 7 * 86400_000).toISOString().slice(0, 10), to: today };
    case 'last_30':
      return { from: new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10), to: today };
    case 'this_month':
      return { from: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10), to: today };
    case 'last_month': {
      const now = new Date();
      return {
        from: new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString().slice(0, 10),
        to: new Date(now.getFullYear(), now.getMonth(), 0).toISOString().slice(0, 10),
      };
    }
    default:
      return { from: value.from || defaultFrom(), to: value.to || today };
  }
}

function downloadCsv(filename: string, headers: string[], rows: string[][]) {
  const escape = (v: string) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csvContent = [
    headers.map(escape).join(','),
    ...rows.map((row) => row.map(escape).join(',')),
  ].join('\n');
  // RPT-CSV2: Prepend UTF-8 BOM (\uFEFF) so Excel on Windows opens the file
  // with the correct encoding instead of garbling currency symbols and accented
  // characters in customer names.
  const blob = new Blob(['\uFEFF' + csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

// ─── Tabs Config ──────────────────────────────────────────────────────────────

type ReportTabConfig = { key: Tab; label: string; icon: any; proFeature?: keyof PlanFeatures };

// Free tier gets basic reports (sales, tickets, employees, inventory, tax).
// Pro-only reports require the `advancedReports` feature.
const TABS: ReportTabConfig[] = [
  { key: 'sales', label: 'Sales', icon: DollarSign },
  { key: 'tickets', label: 'Tickets', icon: Ticket },
  { key: 'employees', label: 'Employees', icon: Users },
  { key: 'inventory', label: 'Inventory', icon: Package },
  { key: 'tax', label: 'Tax', icon: Receipt },
  { key: 'insights', label: 'Insights', icon: BarChart3, proFeature: 'advancedReports' },
  { key: 'warranty', label: 'Warranty', icon: ShieldAlert, proFeature: 'advancedReports' },
  { key: 'devices', label: 'Devices', icon: Smartphone, proFeature: 'advancedReports' },
  { key: 'parts', label: 'Parts', icon: Cpu, proFeature: 'advancedReports' },
  { key: 'tech-hours', label: 'Tech Hours', icon: Clock, proFeature: 'advancedReports' },
  { key: 'stalled', label: 'Stalled', icon: AlertTriangle, proFeature: 'advancedReports' },
  { key: 'acquisition', label: 'Customers', icon: UserPlus, proFeature: 'advancedReports' },
];

// ─── Sales Tab ────────────────────────────────────────────────────────────────

function SalesTab({ from, to }: { from: string; to: string }) {
  const navigate = useNavigate();
  const [groupBy, setGroupBy] = useState<'day' | 'week' | 'month'>('day');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'sales', from, to, groupBy],
    queryFn: async () => {
      const res = await reportApi.sales({ from_date: from, to_date: to, group_by: groupBy });
      return res.data.data as SalesData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load sales report" />;

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
                onClick={() => setGroupBy(g)}
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
              // Fill in gaps with $0 for all grouping modes
              const rawChartData = (() => {
                const revenueMap = new Map(rows.map(r => [r.period, r.revenue]));
                const result: { period: string; revenue: number; rawDate: string }[] = [];
                const current = new Date(from + 'T00:00:00');
                const end = new Date(to + 'T00:00:00');

                if (groupBy === 'day') {
                  while (current <= end) {
                    const key = current.toISOString().slice(0, 10);
                    result.push({ period: formatDate(key), revenue: revenueMap.get(key) || 0, rawDate: key });
                    current.setDate(current.getDate() + 1);
                  }
                } else if (groupBy === 'week') {
                  // Generate week start dates (Monday)
                  const day = current.getDay();
                  current.setDate(current.getDate() - (day === 0 ? 6 : day - 1)); // go to Monday
                  while (current <= end) {
                    const key = current.toISOString().slice(0, 10);
                    const weekEnd = new Date(current);
                    weekEnd.setDate(weekEnd.getDate() + 6);
                    const label = `${formatDate(key)} – ${formatDate(weekEnd.toISOString().slice(0, 10))}`;
                    result.push({ period: label, revenue: revenueMap.get(key) || 0, rawDate: key });
                    current.setDate(current.getDate() + 7);
                  }
                } else {
                  // month — generate each month in range
                  current.setDate(1);
                  while (current <= end) {
                    const key = current.toISOString().slice(0, 7); // YYYY-MM
                    const label = current.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
                    result.push({ period: label, revenue: revenueMap.get(key) || 0, rawDate: key });
                    current.setMonth(current.getMonth() + 1);
                  }
                }
                return result;
              })();

              const handleChartClick = (data: any) => {
                if (data?.activePayload?.[0]?.payload?.rawDate) {
                  const date = data.activePayload[0].payload.rawDate;
                  navigate(`/invoices?from=${date}&to=${date}`);
                }
              };

              return (
                <div className="p-4" style={{ height: 260 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={rawChartData} onClick={handleChartClick} style={{ cursor: 'pointer' }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="currentColor" className="text-surface-200 dark:text-surface-700" />
                      <XAxis dataKey="period" tick={{ fontSize: 11, fill: '#9ca3af' }} />
                      {/* @audit-fixed: chart axis was hardcoded "$" — now uses formatCurrency to honor store currency */}
                      <YAxis tick={{ fontSize: 11, fill: '#9ca3af' }} tickFormatter={(v: number) => formatCurrency(v)} />
                      <Tooltip contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: '1px solid #374151', borderRadius: 8, color: '#f3f4f6' }} formatter={(value: number) => [formatCurrency(value), 'Revenue']} labelFormatter={(label: string) => `${label} (click to view invoices)`} />
                      <Line type="monotone" dataKey="revenue" stroke="#3b82f6" strokeWidth={2} dot={{ r: 3 }} activeDot={{ r: 6, style: { cursor: 'pointer' } }} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
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
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'tickets', from, to],
    queryFn: async () => {
      const res = await reportApi.tickets({ from_date: from, to_date: to });
      return res.data.data as TicketsData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load tickets report" />;

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
        <SummaryCard
          label="Avg Turnaround" value={summary.avg_turnaround_hours != null ? `${summary.avg_turnaround_hours}h` : 'N/A'}
          icon={Clock} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
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
                {byDay.map((d) => {
                  const maxCreated = Math.max(...byDay.map((x) => x.created), 1);
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
                })}
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

const WORKLOAD_COLORS = ['#3b82f6', '#f59e0b', '#ef4444', '#10b981', '#8b5cf6', '#ec4899'];

function TechWorkloadChart() {
  const { data, isLoading } = useQuery({
    queryKey: ['reports', 'tech-workload'],
    queryFn: async () => {
      const res = await reportApi.techWorkload();
      return res.data.data as TechWorkloadItem[];
    },
  });

  if (isLoading) return <LoadingState />;
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
              <XAxis dataKey="name" tick={{ fontSize: 12, fill: '#9ca3af' }} />
              <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: '#9ca3af' }} />
              <Tooltip contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: '1px solid #374151', borderRadius: 8, color: '#f3f4f6' }} />
              <Bar dataKey="Open" stackId="a" fill="#3b82f6" radius={[0, 0, 0, 0]} />
              <Bar dataKey="In Progress" stackId="a" fill="#f59e0b" />
              <Bar dataKey="Waiting Parts" stackId="a" fill="#ef4444" radius={[4, 4, 0, 0]} />
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
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'employees', from, to],
    queryFn: async () => {
      const res = await reportApi.employees({ from_date: from, to_date: to });
      return res.data.data as EmployeesData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load employee report" />;

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
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'tax', from, to],
    queryFn: async () => {
      const res = await reportApi.tax({ from_date: from, to_date: to });
      return res.data.data as TaxData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load tax report" />;

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

const CHART_COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#f97316', '#84cc16', '#6366f1'];

function InsightsTab({ from, to }: { from: string; to: string }) {
  const [subTab, setSubTab] = useState<'tickets' | 'sales'>('tickets');
  const [compare, setCompare] = useState(false);

  // Calculate previous period (same duration, shifted back)
  const fromMs = new Date(from + 'T00:00:00').getTime();
  const toMs = new Date(to + 'T00:00:00').getTime();
  const durationMs = toMs - fromMs;
  const prevFrom = new Date(fromMs - durationMs - 86400_000).toISOString().slice(0, 10);
  const prevTo = new Date(fromMs - 86400_000).toISOString().slice(0, 10);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'insights', from, to],
    queryFn: async () => {
      const res = await reportApi.insights({ from_date: from, to_date: to });
      return res.data.data as InsightsData;
    },
  });

  const { data: prevData } = useQuery({
    queryKey: ['reports', 'insights', prevFrom, prevTo],
    queryFn: async () => {
      const res = await reportApi.insights({ from_date: prevFrom, to_date: prevTo });
      return res.data.data as InsightsData;
    },
    enabled: compare,
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load insights data" />;

  const { popular_models, repairs_by_month, revenue_by_model, popular_services } = data;

  // Build comparison data for repairs by month (overlay current vs previous)
  const comparisonRepairs = compare && prevData
    ? repairs_by_month.map((r, i) => ({
        month: r.month,
        current: r.count,
        previous: prevData.repairs_by_month[i]?.count ?? 0,
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
              onClick={() => setSubTab(t)}
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
            onChange={(e) => setCompare(e.target.checked)}
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
                    <XAxis type="number" tick={{ fontSize: 12, fill: '#9ca3af' }} />
                    <YAxis dataKey="name" type="category" width={120} tick={{ fontSize: 11, fill: '#9ca3af' }} />
                    <Tooltip
                      contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: 'none', borderRadius: 8, color: '#f3f4f6' }}
                      formatter={(value: number) => [value, 'Repairs']}
                    />
                    <Bar dataKey="count" radius={[0, 4, 4, 0]}>
                      {popular_models.map((_, i) => (
                        <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
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
                      <XAxis dataKey="month" tick={{ fontSize: 11, fill: '#9ca3af' }} />
                      <YAxis tick={{ fontSize: 12, fill: '#9ca3af' }} />
                      <Tooltip
                        contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: 'none', borderRadius: 8, color: '#f3f4f6' }}
                      />
                      <Bar dataKey="previous" fill="#d1d5db" radius={[4, 4, 0, 0]} name="Previous Period" />
                      <Bar dataKey="current" fill="#3b82f6" radius={[4, 4, 0, 0]} name="Current Period" />
                    </BarChart>
                  ) : (
                    <BarChart data={repairs_by_month} margin={{ left: 0, right: 20, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                      <XAxis dataKey="month" tick={{ fontSize: 11, fill: '#9ca3af' }} />
                      <YAxis tick={{ fontSize: 12, fill: '#9ca3af' }} />
                      <Tooltip
                        contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: 'none', borderRadius: 8, color: '#f3f4f6' }}
                        formatter={(value: number) => [value, 'Tickets']}
                      />
                      <Bar dataKey="count" fill="#3b82f6" radius={[4, 4, 0, 0]} />
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
                    <XAxis dataKey="name" tick={{ fontSize: 10, fill: '#9ca3af' }} angle={-20} textAnchor="end" height={60} />
                    <YAxis tick={{ fontSize: 12, fill: '#9ca3af' }} />
                    <Tooltip
                      contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: 'none', borderRadius: 8, color: '#f3f4f6' }}
                      formatter={(value: number) => [value, 'Count']}
                    />
                    <Bar dataKey="count" radius={[4, 4, 0, 0]}>
                      {popular_services.map((_, i) => (
                        <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
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
                      <XAxis type="number" tick={{ fontSize: 12, fill: '#9ca3af' }} tickFormatter={(v) => `$${v}`} />
                      <YAxis dataKey="name" type="category" width={140} tick={{ fontSize: 11, fill: '#9ca3af' }} />
                      <Tooltip
                        contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: 'none', borderRadius: 8, color: '#f3f4f6' }}
                        formatter={(value: number) => [`$${value.toFixed(2)}`]}
                      />
                      <Bar dataKey="previous" fill="#d1d5db" radius={[0, 4, 4, 0]} name="Previous Period" />
                      <Bar dataKey="current" fill="#3b82f6" radius={[0, 4, 4, 0]} name="Current Period" />
                    </BarChart>
                  ) : (
                    <BarChart data={revenue_by_model} layout="vertical" margin={{ left: 10, right: 20, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-surface-200, #e5e7eb)" />
                      <XAxis type="number" tick={{ fontSize: 12, fill: '#9ca3af' }} tickFormatter={(v) => `$${v}`} />
                      <YAxis dataKey="name" type="category" width={140} tick={{ fontSize: 11, fill: '#9ca3af' }} />
                      <Tooltip
                        contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: 'none', borderRadius: 8, color: '#f3f4f6' }}
                        formatter={(value: number) => [`$${value.toFixed(2)}`, 'Revenue']}
                      />
                      <Bar dataKey="revenue" radius={[0, 4, 4, 0]}>
                        {revenue_by_model.map((_, i) => (
                          <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
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
  const [activeTab, setActiveTab] = useState<Tab>('sales');
  const [dateRange, setDateRange] = useState<{ from?: string; to?: string; preset?: string }>({
    preset: 'last_30',
  });
  const { from: fromDate, to: toDate } = resolveDateRange(dateRange);
  const queryClient = useQueryClient();

  // Tier gating: reads plan features and exposes upgrade modal opener
  const planFeatures = usePlanStore((s) => s.features);
  const planHasFetched = usePlanStore((s) => s.hasFetched);
  const openUpgradeModal = usePlanStore((s) => s.openUpgradeModal);
  const isReportTabLocked = (tab: ReportTabConfig): boolean => {
    if (!tab.proFeature) return false;
    if (!planHasFetched) return false; // don't lock while loading
    return !planFeatures[tab.proFeature];
  };

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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTab, planHasFetched, planFeatures]);

  async function handleExport() {
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
          ['reports', 'sales', fromDate, toDate, 'day'],
          async () => { const res = await reportApi.sales({ from_date: fromDate, to_date: toDate, group_by: 'day' }); return res.data.data as SalesData; },
        );
        downloadCsv(`sales_${dateStr}.csv`,
          ['Period', 'Invoices', 'Revenue', 'Unique Customers'],
          data.rows.map((r) => [r.period, String(r.invoices), String(r.revenue), String(r.unique_customers)]),
        );
      } else if (activeTab === 'tickets') {
        const data = await getCached<TicketsData>(
          ['reports', 'tickets', fromDate, toDate],
          async () => { const res = await reportApi.tickets({ from_date: fromDate, to_date: toDate }); return res.data.data as TicketsData; },
        );
        downloadCsv(`tickets_${dateStr}.csv`,
          ['Day', 'Created'],
          data.byDay.map((r) => [r.day, String(r.created)]),
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
    }
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Reports</h1>
          <p className="text-surface-500 dark:text-surface-400">Analyze your business performance</p>
        </div>
        <button
          onClick={handleExport}
          className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-surface-700 dark:text-surface-300 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
        >
          <Download className="h-4 w-4" />
          Export
        </button>
      </div>

      {/* Date Range — applies to all tabs except Inventory */}
      {activeTab !== 'inventory' && (
        <div className="card mb-4">
          <div className="flex items-center gap-3 p-3">
            <Clock className="h-4 w-4 text-surface-400 mr-1 shrink-0" />
            <span className="text-xs font-medium text-surface-500 dark:text-surface-400 mr-1 shrink-0">Period:</span>
            <DateRangePicker
              value={dateRange}
              onChange={setDateRange}
            />
          </div>
        </div>
      )}

      {/* Tab navigation */}
      <div className="card mb-6">
        <div className="overflow-x-auto p-4">
          <div className="flex gap-1 bg-surface-100 dark:bg-surface-800 rounded-lg p-1 w-fit">
            {TABS.map((tab) => {
              const Icon = tab.icon;
              const locked = isReportTabLocked(tab);
              return (
                <button
                  key={tab.key}
                  onClick={() => {
                    if (locked && tab.proFeature) {
                      openUpgradeModal(tab.proFeature);
                      return;
                    }
                    setActiveTab(tab.key);
                  }}
                  className={cn(
                    'flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-md transition-colors whitespace-nowrap',
                    activeTab === tab.key
                      ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                      : locked
                        ? 'text-surface-400 hover:text-surface-600 dark:text-surface-500 dark:hover:text-surface-400'
                        : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
                  )}
                  title={locked ? `${tab.label} requires Pro plan` : undefined}
                >
                  <Icon className="h-4 w-4" />
                  <span className="hidden sm:inline">{tab.label}</span>
                  {locked && <Lock className="h-3 w-3 text-amber-500" />}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      {/* Tab Content */}
      {activeTab === 'sales' && <SalesTab from={fromDate} to={toDate} />}
      {activeTab === 'tickets' && <TicketsTab from={fromDate} to={toDate} />}
      {activeTab === 'employees' && <EmployeesTab from={fromDate} to={toDate} />}
      {activeTab === 'inventory' && <InventoryTab />}
      {activeTab === 'tax' && <TaxTab from={fromDate} to={toDate} />}
      {activeTab === 'insights' && <InsightsTab from={fromDate} to={toDate} />}
      {activeTab === 'warranty' && <WarrantyClaimsTab from={fromDate} to={toDate} />}
      {activeTab === 'devices' && <DeviceModelsTab from={fromDate} to={toDate} />}
      {activeTab === 'parts' && <PartsUsageTab from={fromDate} to={toDate} />}
      {activeTab === 'tech-hours' && <TechnicianHoursTab from={fromDate} to={toDate} />}
      {activeTab === 'stalled' && <StalledTicketsTab from={fromDate} to={toDate} />}
      {activeTab === 'acquisition' && <CustomerAcquisitionTab from={fromDate} to={toDate} />}
    </div>
  );
}
