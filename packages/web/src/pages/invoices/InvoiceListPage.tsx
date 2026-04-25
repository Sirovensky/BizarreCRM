import { useState, useRef, useMemo } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { FileText, Search, ChevronLeft, ChevronRight, Loader2, DollarSign, Receipt, Landmark, AlertCircle, Ban, CheckCircle2, Bell } from 'lucide-react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';
import toast from 'react-hot-toast';
import { invoiceApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';

const STATUS_TABS = [
  { key: '', label: 'All' },
  { key: 'unpaid', label: 'Unpaid' },
  { key: 'partial', label: 'Partial' },
  { key: 'overdue', label: 'Overdue' },
  { key: 'paid', label: 'Paid' },
  { key: 'void', label: 'Void' },
];

const STATUS_COLORS: Record<string, string> = {
  unpaid: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  partial: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  paid: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  void: 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
  refunded: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
};

const PIE_COLORS_STATUS: Record<string, string> = {
  paid: '#22c55e',
  unpaid: '#ef4444',
  partial: '#f59e0b',
  void: '#94a3b8',
  refunded: '#a855f7',
};

const PIE_COLORS_METHOD = ['#3b82f6', '#8b5cf6', '#06b6d4', '#f97316', '#ec4899', '#14b8a6', '#64748b', '#eab308'];

const DATE_TABS = [
  { key: 'today', label: 'Today' },
  { key: '7', label: '7 Days' },
  { key: '30', label: '30 Days' },
  { key: '', label: 'All' },
];

function getDateRange(key: string): { from_date?: string; to_date?: string } {
  if (!key) return {};
  const now = new Date();
  const to_date = now.toISOString().slice(0, 10);
  if (key === 'today') return { from_date: to_date, to_date };
  const days = parseInt(key);
  const from = new Date(now.getTime() - days * 86400_000);
  return { from_date: from.toISOString().slice(0, 10), to_date };
}

function formatInvoiceId(orderId: string | number | null | undefined): string {
  if (!orderId) return '\u2014';
  const s = String(orderId);
  return s.startsWith('INV') ? s : `INV-${s}`;
}

// Matches the subset of invoice row fields the list UI reads. Nullable per
// server shape. Keeping the interface loose (optional fields + a permissive
// extras bag) lets the server grow without breaking the client.
interface InvoiceRow {
  id: number;
  order_id?: string | number | null;
  status?: string | null;
  due_on?: string | null;
  customer_name?: string | null;
  customer_id?: number | null;
  total?: number | string | null;
  paid_amount?: number | string | null;
  balance_due?: number | string | null;
  created_at?: string | null;
  payment_method?: string | null;
  currency_code?: string | null;
}

export function InvoiceListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  const status = searchParams.get('status') || '';
  const dateRange = searchParams.get('date_range') || '';
  const page = Number(searchParams.get('page') || '1');
  const pageSize = Number(searchParams.get('pagesize') || localStorage.getItem('invoices_pagesize') || '25');
  const keyword = searchParams.get('keyword') || '';
  const [searchInput, setSearchInput] = useState(keyword);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Bulk selection state
  const [selected, setSelected] = useState<Set<number>>(new Set());

  const dateParams = useMemo(() => getDateRange(dateRange), [dateRange]);

  const setParam = (key: string, val: string) => {
    const p = new URLSearchParams(searchParams);
    if (val) p.set(key, val); else p.delete(key);
    p.set('page', '1');
    setSearchParams(p, { replace: true });
  };

  const handleSearch = (val: string) => {
    setSearchInput(val);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setParam('keyword', val), 300);
  };

  const setPage = (n: number) => {
    const p = new URLSearchParams(searchParams);
    p.set('page', String(n));
    setSearchParams(p, { replace: true });
  };

  const { data, isLoading } = useQuery({
    queryKey: ['invoices', { page, pageSize, status, keyword, dateRange }],
    queryFn: () => invoiceApi.list({ page, pagesize: pageSize, status: status || undefined, keyword: keyword || undefined, ...dateParams }),
  });

  const { data: statsData } = useQuery({
    // Include the active filters in the cache key so the stats chart refetches
    // when the user changes date range or status tab; otherwise the charts
    // show stale aggregates from the last filter combination.
    queryKey: ['invoice-stats', { status, dateRange }],
    queryFn: () => invoiceApi.stats(),
  });

  const rawInvoices = data?.data?.data?.invoices;
  const invoices: InvoiceRow[] = Array.isArray(rawInvoices) ? (rawInvoices as InvoiceRow[]) : [];
  const pagination = data?.data?.data?.pagination;
  const overdueCount = useMemo(() => {
    if (!status || status === 'overdue') return 0; // only show count on non-overdue tabs
    return invoices.filter((inv) => {
      if (inv.status !== 'unpaid' && inv.status !== 'partial') return false;
      if (!inv.due_on) return false;
      const ts = Date.parse(inv.due_on);
      return !isNaN(ts) && ts < Date.now();
    }).length;
  }, [invoices, status]);
  const stats = statsData?.data?.data;
  const kpis = stats?.kpis;
  const statusDist: Array<{ status: string; count: number }> = stats?.status_distribution || [];
  const methodDist: Array<{ method: string | null; count: number }> = stats?.method_distribution || [];

  const statusPieData = useMemo(
    () => statusDist.map(s => ({ name: s.status, value: s.count })),
    [statusDist],
  );
  const methodPieData = useMemo(
    () => methodDist.map(m => ({ name: m.method || 'Unknown', value: m.count })),
    [methodDist],
  );

  // Bulk action mutation
  const bulkMut = useMutation({
    mutationFn: ({ action }: { action: string }) =>
      invoiceApi.bulkAction(action, Array.from(selected)),
    onSuccess: () => {
      toast.success('Bulk action completed');
      setSelected(new Set());
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      queryClient.invalidateQueries({ queryKey: ['invoice-stats'] });
    },
    onError: () => toast.error('Bulk action failed'),
  });

  // @audit-fixed: confirm before destructive bulk actions (was firing on single click)
  // WEB-FV-001: replaced native window.confirm with confirmStore (async modal)
  const handleBulkAction = async (action: string, label: string) => {
    if (bulkMut.isPending) return;
    const ok = await confirm(`${label} ${selected.size} invoice(s)? This action cannot be undone.`, {
      title: `${label} invoices`,
      confirmLabel: label,
      danger: true,
    });
    if (!ok) return;
    bulkMut.mutate({ action });
  };

  function toggleSelectAll() {
    if (selected.size === invoices.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(invoices.map((inv: any) => inv.id)));
    }
  }

  function toggleSelect(id: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <div className="flex flex-col h-full">
      <div className="mb-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Invoices</h1>
          <p className="text-surface-500 dark:text-surface-400">Track payments and billing</p>
        </div>
        <span className="text-xs text-surface-400 dark:text-surface-500 italic">Invoices are created from tickets</span>
      </div>

      {/* KPI Cards — always visible */}
      {/* @audit-fixed: hardcoded "$" + .toFixed(2) replaced with formatCurrency to honor store currency setting */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4 shrink-0">
        <KpiCard icon={<DollarSign className="h-5 w-5" />} label="Total Sales" value={kpis ? formatCurrency(kpis.total_sales) : '...'} color="text-green-600 dark:text-green-400" bgColor="bg-green-50 dark:bg-green-900/20" />
        <KpiCard icon={<Receipt className="h-5 w-5" />} label="Invoices" value={kpis ? String(kpis.invoice_count) : '...'} color="text-blue-600 dark:text-blue-400" bgColor="bg-blue-50 dark:bg-blue-900/20" />
        <KpiCard icon={<Landmark className="h-5 w-5" />} label="Tax Collected" value={kpis ? formatCurrency(kpis.tax_collected) : '...'} color="text-purple-600 dark:text-purple-400" bgColor="bg-purple-50 dark:bg-purple-900/20" />
        <KpiCard icon={<AlertCircle className="h-5 w-5" />} label="Outstanding" value={kpis ? formatCurrency(kpis.outstanding_receivables) : '...'}
          color={kpis && Number(kpis.outstanding_receivables) > 0 ? 'text-red-600 dark:text-red-400' : 'text-surface-500'} bgColor="bg-red-50 dark:bg-red-900/20" />
      </div>

      {/* Overview Charts */}
      {(statusPieData.length > 0 || methodPieData.length > 0) && (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4 shrink-0">
          {statusPieData.length > 0 && (
            <div className="card p-4">
              <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-300 mb-2">Payment Status</h3>
              <div className="flex items-center gap-4">
                <div className="w-28 h-28">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={statusPieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={25} outerRadius={50} paddingAngle={2}>
                        {/* WEB-FF-021: key by entry.name (status, e.g. "paid"/"unpaid") so React reconciles cell→color
                            pairings stably across poll-driven refreshes. Index keys flicker when the dataset shrinks
                            (e.g. all "draft" rows resolve and the slice drops out). */}
                        {statusPieData.map((entry) => (
                          <Cell key={entry.name} fill={PIE_COLORS_STATUS[entry.name] || '#94a3b8'} />
                        ))}
                      </Pie>
                      <Tooltip formatter={(value: number) => [value, 'Count']} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="flex flex-col gap-1">
                  {statusPieData.map((s, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs">
                      <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: PIE_COLORS_STATUS[s.name] || '#94a3b8' }} />
                      <span className="capitalize text-surface-600 dark:text-surface-400">{s.name}</span>
                      <span className="font-medium text-surface-800 dark:text-surface-200">{s.value}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
          {methodPieData.length > 0 && (
            <div className="card p-4">
              <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-300 mb-2">Payment Methods</h3>
              <div className="flex items-center gap-4">
                <div className="w-28 h-28">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={methodPieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={25} outerRadius={50} paddingAngle={2}>
                        {/* WEB-FF-021: key by entry.name (method, e.g. "card"/"cash") so slice→color identity is
                            stable when one method drops to zero on refresh. Color still cycles by index for variety. */}
                        {methodPieData.map((entry, i) => (
                          <Cell key={entry.name} fill={PIE_COLORS_METHOD[i % PIE_COLORS_METHOD.length]} />
                        ))}
                      </Pie>
                      <Tooltip formatter={(value: number) => [value, 'Count']} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="flex flex-col gap-1">
                  {methodPieData.map((m, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs">
                      <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: PIE_COLORS_METHOD[i % PIE_COLORS_METHOD.length] }} />
                      <span className="text-surface-600 dark:text-surface-400">{m.name}</span>
                      <span className="font-medium text-surface-800 dark:text-surface-200">{m.value}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Status tabs */}
      <div className="flex gap-0 mb-3 border-b border-surface-200 dark:border-surface-700 shrink-0">
        {STATUS_TABS.map((t) => (
          <button key={t.key} onClick={() => setParam('status', t.key)}
            className={cn('px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
              status === t.key
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200'
            )}>
            {t.label}
          </button>
        ))}
      </div>

      {/* Date Range Tabs */}
      <div className="flex gap-2 mb-3 shrink-0">
        {DATE_TABS.map((t) => (
          <button key={t.key} onClick={() => setParam('date_range', t.key)}
            className={cn('px-3 py-1.5 text-xs font-medium rounded-full border transition-colors',
              dateRange === t.key
                ? 'border-primary-500 bg-primary-50 text-primary-600 dark:bg-primary-900/20 dark:text-primary-400 dark:border-primary-700'
                : 'border-surface-200 text-surface-500 hover:text-surface-700 dark:border-surface-700 dark:text-surface-400 dark:hover:text-surface-200'
            )}>
            {t.label}
          </button>
        ))}
      </div>

      {/* Search */}
      <div className="mb-3 shrink-0">
        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
          <input type="text" placeholder="Search invoices..." value={searchInput} onChange={(e) => handleSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-primary-500 transition-colors" />
        </div>
      </div>

      <div className="card overflow-hidden flex-1 flex flex-col min-h-0">
        {/* Bulk action bar */}
        {selected.size > 0 && (
          <div className="flex items-center gap-3 border-b border-surface-200 bg-primary-50 px-4 py-2.5 dark:border-surface-700 dark:bg-primary-950/30 shrink-0">
            <span className="text-sm font-medium text-primary-700 dark:text-primary-300">
              {selected.size} selected
            </span>
            {/* @audit-fixed: bulk actions now go through handleBulkAction confirmation (was firing on single click) */}
            <button
              onClick={() => handleBulkAction('void', 'Void')}
              disabled={bulkMut.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 disabled:opacity-50"
            >
              <Ban className="h-3.5 w-3.5" /> Void Selected
            </button>
            <button
              onClick={() => handleBulkAction('mark_paid', 'Mark as paid')}
              disabled={bulkMut.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 disabled:opacity-50"
            >
              <CheckCircle2 className="h-3.5 w-3.5" /> Mark Paid
            </button>
            <button
              onClick={() => handleBulkAction('send_reminder', 'Send reminders to')}
              disabled={bulkMut.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 disabled:opacity-50"
            >
              <Bell className="h-3.5 w-3.5" /> Send Reminders
            </button>
            <button
              onClick={() => setSelected(new Set())}
              className="ml-auto text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
            >
              Clear
            </button>
          </div>
        )}

        {isLoading ? (
          <div className="flex items-center justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-surface-400" /></div>
        ) : invoices.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20">
            <FileText className="h-16 w-16 text-surface-300 dark:text-surface-600 mb-4" />
            <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">No invoices found</h2>
          </div>
        ) : (
          <>
            <div className="overflow-auto flex-1 min-h-0">
              <table className="w-full">
                <thead className="sticky top-0 z-10">
                  <tr className="border-b border-surface-200 dark:border-surface-700">
                    <th className="px-4 py-3 w-10 bg-surface-50 dark:bg-surface-800/50">
                      <input
                        type="checkbox"
                        checked={invoices.length > 0 && selected.size === invoices.length}
                        onChange={toggleSelectAll}
                        className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                      />
                    </th>
                    {['Invoice', 'Customer', 'Ticket', 'Date', 'Total', 'Paid', 'Due', 'Status', 'Actions'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                  {invoices.map((inv: any) => {
                    const isOverdue = (inv.status === 'unpaid' || inv.status === 'partial') && inv.due_on && new Date(inv.due_on) < new Date();
                    const isSelected = selected.has(inv.id);
                    return (
                    <tr key={inv.id} onClick={() => navigate(`/invoices/${inv.id}`)}
                      className={cn(
                        'hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer transition-colors',
                        isSelected && 'bg-primary-50/50 dark:bg-primary-950/20',
                        isOverdue ? 'border-l-4 border-l-red-600' :
                        inv.status === 'paid' ? 'border-l-4 border-l-green-400' :
                        inv.status === 'void' ? 'border-l-4 border-l-surface-300' :
                        Number(inv.amount_due) > 0 ? 'border-l-4 border-l-red-400' : '',
                      )}>
                      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                        <input
                          type="checkbox"
                          checked={isSelected}
                          onChange={() => toggleSelect(inv.id)}
                          className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                        />
                      </td>
                      <td className="px-4 py-3 text-sm font-mono font-medium text-primary-600 dark:text-primary-400">{formatInvoiceId(inv.order_id)}</td>
                      <td className="px-4 py-3 text-sm">
                        <div className="font-medium text-surface-900 dark:text-surface-100">{inv.first_name || inv.last_name ? `${inv.first_name || ''} ${inv.last_name || ''}`.trim() : 'Walk-in'}</div>
                        {inv.organization && <div className="text-xs text-surface-400">{inv.organization}</div>}
                      </td>
                      <td className="px-4 py-3 text-sm" onClick={e => e.stopPropagation()}>
                        {inv.ticket_id ? (
                          <Link to={`/tickets/${inv.ticket_id}`}
                            className="font-mono text-xs px-2 py-0.5 rounded bg-primary-50 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400 hover:underline">
                            {inv.ticket_order_id || `T-${inv.ticket_id}`}
                          </Link>
                        ) : (
                          <span className="text-surface-400 text-xs">{'\u2014'}</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">
                        {/* @audit-fixed: use formatDate helper instead of hardcoded en-US locale */}
                        {formatDate(inv.created_at)}
                      </td>
                      {/* @audit-fixed: hardcoded "$" + toFixed replaced with formatCurrency */}
                      <td className="px-4 py-3 text-sm font-medium text-surface-900 dark:text-surface-100">{formatCurrency(inv.total)}</td>
                      <td className="px-4 py-3 text-sm text-green-600 dark:text-green-400">{formatCurrency(inv.amount_paid)}</td>
                      <td className="px-4 py-3 text-sm">
                        <span className={cn(Number(inv.amount_due) > 0 ? 'text-red-600 dark:text-red-400 font-medium' : 'text-surface-400')}>
                          {formatCurrency(inv.amount_due)}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm">
                        <span className={cn('inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize',
                          isOverdue ? 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300' : (STATUS_COLORS[inv.status] || ''))}>
                          {isOverdue ? 'Overdue' : inv.status}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm">
                        <Link to={`/invoices/${inv.id}`} onClick={(e) => e.stopPropagation()}
                          className="text-sm text-primary-600 hover:text-primary-700 dark:text-primary-400 font-medium">
                          View
                        </Link>
                      </td>
                    </tr>
                  );})}
                </tbody>
              </table>
            </div>
            {pagination && (
              <div className="flex items-center justify-between px-4 py-3 border-t border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/30">
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-1.5">
                    <span className="text-xs text-surface-500 dark:text-surface-400">Show</span>
                    <select
                      value={pageSize}
                      onChange={(e) => {
                        const v = e.target.value;
                        localStorage.setItem('invoices_pagesize', v);
                        const p = new URLSearchParams(searchParams);
                        p.set('pagesize', v);
                        p.set('page', '1');
                        setSearchParams(p, { replace: true });
                      }}
                      className="text-xs rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-2 py-1 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400"
                    >
                      {[10, 25, 50, 100, 250].map((n) => (
                        <option key={n} value={n}>{n}</option>
                      ))}
                    </select>
                    <span className="text-xs text-surface-500 dark:text-surface-400">per page</span>
                  </div>
                  <p className="text-sm text-surface-500 dark:text-surface-400">Page {pagination.page} of {pagination.total_pages} <span className="text-surface-400">({pagination.total} total)</span></p>
                </div>
                {pagination.total_pages > 1 && (
                  <div className="flex items-center gap-2">
                    <button onClick={() => setPage(page - 1)} disabled={page <= 1} className="inline-flex items-center justify-center gap-1 px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                      <ChevronLeft className="h-4 w-4" /> Previous
                    </button>
                    <button onClick={() => setPage(page + 1)} disabled={page >= pagination.total_pages} className="inline-flex items-center justify-center gap-1 px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                      Next <ChevronRight className="h-4 w-4" />
                    </button>
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

function KpiCard({ icon, label, value, color, bgColor }: { icon: React.ReactNode; label: string; value: string; color: string; bgColor: string }) {
  return (
    <div className="card p-4 flex items-center gap-3">
      <div className={cn('p-2.5 rounded-lg', bgColor, color)}>
        {icon}
      </div>
      <div>
        <p className="text-xs font-medium text-surface-500 dark:text-surface-400 uppercase tracking-wide">{label}</p>
        <p className={cn('text-lg font-bold', color)}>{value}</p>
      </div>
    </div>
  );
}
