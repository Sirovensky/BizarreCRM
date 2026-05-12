/**
 * Commission period lock — criticalaudit.md §53 idea #7.
 *
 * Compact card that lists payroll periods with a Lock button. Once locked,
 * the row shows a lock icon and the locked-by user. The server-side checks
 * refuse:
 *   - commission edits in the locked range (`isCommissionLocked`)
 *   - clock-in/out edits and timesheet adjustments in the locked range
 *     (employees.routes :375,447-448)
 *   - tip edits on payments inside the range (pos.routes :787)
 * UI is a one-way switch on purpose — the inline copy below mirrors the
 * same scope so the admin doesn't think they're only freezing commissions.
 *
 * Drop-in for the payroll page or settings; also re-used by GoalsPage in a
 * follow-up if needed.
 */
import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Lock, LockOpen, Plus, Loader2, Download } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { confirm } from '@/stores/confirmStore';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { formatDate } from '@/utils/format';

interface PayrollPeriod {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  locked_at: string | null;
  locked_by_user_id: number | null;
  notes: string | null;
}

interface PayrollPeriodSummary {
  commission_count: number;
  commission_total: number;
  time_entry_count: number;
  total_hours: number;
  tip_count: number;
  tip_total: number;
  distinct_employee_count: number;
  gross_total: number;
}

/**
 * WEB-UIUX-1145: lazy-load the lock-consequences preview only when the row's
 * <details> is expanded so we don't fan 100 summary queries on every page
 * render. `enabled: open` keeps the query dormant until the operator opts in.
 */
function PeriodLockConsequencesPreview({ period }: { period: PayrollPeriod }) {
  const [open, setOpen] = useState(false);
  const { data, isLoading, isError } = useQuery({
    queryKey: ['team', 'payroll', 'period-summary', period.id],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: PayrollPeriodSummary }>(
        `/team/payroll/periods/${period.id}/summary`,
      );
      return res.data.data;
    },
    enabled: open,
    staleTime: 60_000,
  });
  return (
    <details
      className="mt-1 text-[11px] text-surface-600 dark:text-surface-400"
      onToggle={(e) => setOpen((e.target as HTMLDetailsElement).open)}
    >
      <summary className="cursor-pointer select-none hover:text-surface-800 dark:hover:text-surface-200">
        What does locking this period affect?
      </summary>
      <div className="mt-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 p-2">
        {isLoading && <span className="inline-flex items-center gap-1"><Loader2 className="h-3 w-3 animate-spin" /> Loading…</span>}
        {isError && <span className="text-red-600 dark:text-red-400">Could not load summary.</span>}
        {data && (
          <ul className="space-y-0.5">
            <li>
              <strong>{data.commission_count}</strong> commission row{data.commission_count === 1 ? '' : 's'}
              {' '}(${(data.commission_total ?? 0).toFixed(2)})
            </li>
            <li>
              <strong>{data.time_entry_count}</strong> time entr{data.time_entry_count === 1 ? 'y' : 'ies'}
              {' '}({(data.total_hours ?? 0).toFixed(2)}h)
            </li>
            <li>
              <strong>{data.tip_count}</strong> tip row{data.tip_count === 1 ? '' : 's'}
              {' '}(${(data.tip_total ?? 0).toFixed(2)})
            </li>
            <li>Touches <strong>{data.distinct_employee_count}</strong> employee{data.distinct_employee_count === 1 ? '' : 's'}</li>
            <li className="pt-1 border-t border-surface-200 dark:border-surface-700">
              Gross subject to lock: <strong>${(data.gross_total ?? 0).toFixed(2)}</strong>
            </li>
          </ul>
        )}
      </div>
    </details>
  );
}

// WEB-UIUX-1157: surface server-side Zod-style array errors instead of
// collapsing them into the generic "Failed" toast. Accepts `{error}`,
// `{errors: [{path,message}]}`, or `{message}` response shapes.
function parseApiError(err: unknown): string | null {
  if (!err || typeof err !== 'object' || !('response' in err)) return null;
  const data = (err as { response?: { data?: unknown } }).response?.data as
    | { error?: string; message?: string; errors?: Array<{ path?: string | string[]; message?: string }> }
    | undefined;
  if (!data) return null;
  if (Array.isArray(data.errors) && data.errors.length > 0) {
    return data.errors
      .map((e) => {
        const path = Array.isArray(e.path) ? e.path.join('.') : e.path;
        const msg = e.message || '';
        return path ? `${path}: ${msg}` : msg;
      })
      .filter(Boolean)
      .join('; ');
  }
  return data.error || data.message || null;
}

export function CommissionPeriodLock() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newStart, setNewStart] = useState('');
  const [newEnd, setNewEnd] = useState('');
  const newPeriodDialogRef = useFocusTrap<HTMLDivElement>(showNew, {
    initialFocusSelector: 'input',
  });

  // WEB-UIUX-1148: paginate + optional year filter so periods 101+ stop
  // silently falling off the end on weekly-cadence tenants past the first
  // 2 years. Default page-size is 50 (matches server cap of 200).
  const [yearFilter, setYearFilter] = useState<string>('');
  const [page, setPage] = useState(1);
  const perPage = 50;

  // WEB-UIUX-1150: destructure isLoading to avoid empty-state false positive on cold load.
  const { data, isLoading } = useQuery({
    queryKey: ['team', 'payroll', 'periods', yearFilter, page],
    queryFn: async () => {
      const params: Record<string, string | number> = { page, per_page: perPage };
      if (yearFilter) params.year = yearFilter;
      const res = await api.get<{
        success: boolean;
        data: PayrollPeriod[];
        pagination?: { page: number; per_page: number; total: number; total_pages: number };
      }>('/team/payroll/periods', { params });
      return res.data;
    },
  });
  const periods: PayrollPeriod[] = data?.data || [];
  const pagination = data?.pagination;

  // WEB-FX-003: Esc-to-close for new-period dialog.
  // WEB-UIUX-1154: guard Esc with dirty-check so accidental key press doesn't silently discard work.
  useEffect(() => {
    if (!showNew) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        const isDirty = newName || newStart || newEnd;
        if (!isDirty || window.confirm('Discard this period?')) {
          setShowNew(false);
        }
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [showNew, newName, newStart, newEnd]);

  const createMut = useMutation({
    mutationFn: async () => {
      await api.post('/team/payroll/periods', {
        name: newName,
        start_date: newStart,
        end_date: newEnd,
      });
    },
    onSuccess: () => {
      toast.success('Period created');
      queryClient.invalidateQueries({ queryKey: ['team', 'payroll', 'periods'] });
      setShowNew(false);
      setNewName('');
      setNewStart('');
      setNewEnd('');
    },
    onError: (e: unknown) => {
      toast.error(parseApiError(e) || 'Failed to create period');
    },
  });

  const lockMut = useMutation({
    mutationFn: async (id: number) => {
      await api.post(`/team/payroll/lock/${id}`);
    },
    onSuccess: () => {
      toast.success('Period locked');
      queryClient.invalidateQueries({ queryKey: ['team', 'payroll', 'periods'] });
    },
    onError: (e: unknown) => {
      toast.error(parseApiError(e) || 'Lock failed');
    },
  });

  // WEB-UIUX-1158: bulk-lock every unlocked period whose end_date is strictly
  // before the cutoff. Confirm dialog spells out the irreversible scope so
  // the admin doesn't fat-finger a 6-month freeze. Default cutoff = today
  // so the typical "lock everything up to yesterday" gesture is one click.
  const bulkLockMut = useMutation({
    mutationFn: async (cutoff: string) => {
      const res = await api.post<{
        success: boolean;
        data: { locked: number; period_ids: number[]; cutoff: string };
      }>('/team/payroll/lock-bulk', { before_date: cutoff });
      return res.data.data;
    },
    onSuccess: (d) => {
      if (d.locked === 0) {
        toast(`No unlocked periods ended before ${d.cutoff}.`, { icon: 'ℹ️' });
      } else {
        toast.success(`Locked ${d.locked} period${d.locked === 1 ? '' : 's'} ending before ${d.cutoff}.`);
      }
      queryClient.invalidateQueries({ queryKey: ['team', 'payroll', 'periods'] });
    },
    onError: (e: unknown) => {
      toast.error(parseApiError(e) || 'Bulk lock failed');
    },
  });

  async function handleBulkLock() {
    const today = new Date().toISOString().slice(0, 10);
    const cutoff = window.prompt(
      'Lock every unlocked period whose end_date is strictly before this date (YYYY-MM-DD).\n\nThis cannot be undone.',
      today,
    );
    if (!cutoff) return;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(cutoff.trim())) {
      toast.error('Cutoff must be YYYY-MM-DD');
      return;
    }
    const ok = await confirm(
      `Lock every payroll period ending before ${cutoff}? Locked periods refuse all commission / time-entry / tip edits in their range. This cannot be undone.`,
      {
        title: 'Bulk lock payroll periods?',
        confirmLabel: 'Lock all',
        danger: true,
      },
    );
    if (ok) bulkLockMut.mutate(cutoff.trim());
  }

  async function downloadCsv(periodId: number) {
    // WEB-FD-021 (Fixer-C5 2026-04-25): replaced `window.open(/api/v1/...)`
    // with an axios blob fetch + anchor-trigger download so the request
    // carries the bearer header that the rest of the app uses. The previous
    // new-tab approach relied on cookie auth, which 401s in bearer-only
    // tenants. Same pattern used by other CSV/PDF exports per WEB-FB-006.
    try {
      const res = await api.get(`/team/payroll/export.csv`, {
        params: { period: periodId },
        responseType: 'blob',
      });
      const blob = new Blob([res.data as BlobPart], { type: 'text/csv' });
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = `payroll-period-${periodId}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      // WEB-UIUX-1146: toast success after triggering download.
      toast.success(`Downloaded payroll-period-${periodId}.csv`);
      // Revoke after the click so the navigation/download has a chance to
      // start; 60s mirrors WEB-FJ-017 wallet-pass blob-revoke cadence.
      setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[CommissionPeriodLock] CSV export failed', err);
      toast.error('CSV export failed');
    }
  }

  async function handleLockPeriod(period: PayrollPeriod) {
    // WEB-UIUX-1143: spell out every downstream lock so the admin knows
    // commission, clock-in/out, timesheet, and tip-edit paths all freeze.
    const ok = await confirm(
      `Lock payroll period "${period.name}" (${period.start_date} to ${period.end_date})?\n\nAfter locking, the following edits in this date range will be blocked:\n• Commission entries\n• Time entries (clock-in/out)\n• Timesheet adjustments\n• Tip edits on payments\n\nThis cannot be undone.`,
      {
        title: 'Lock payroll period?',
        confirmLabel: 'Lock period',
        danger: true,
      },
    );
    if (ok) lockMut.mutate(period.id);
  }

  return (
    <div className="bg-white dark:bg-surface-800 rounded-lg shadow border dark:border-surface-700 p-4">
      <div className="flex items-center justify-between mb-3 gap-2">
        <h2 className="text-sm font-bold text-surface-800 dark:text-surface-100">Payroll periods</h2>
        <div className="flex items-center gap-2">
          {/* WEB-UIUX-1148: year filter narrows audits to a fiscal window
              without scrolling backwards through paginated history. */}
          <input
            type="number"
            inputMode="numeric"
            min={2000}
            max={2100}
            value={yearFilter}
            onChange={(e) => { setYearFilter(e.target.value.replace(/[^\d]/g, '').slice(0, 4)); setPage(1); }}
            placeholder="Year"
            aria-label="Filter by year"
            className="w-20 rounded border dark:border-surface-600 bg-white dark:bg-surface-700 px-2 py-1 text-xs"
          />
          {/* WEB-UIUX-1158: bulk-lock saves 4×N clicks for monthly catch-up. */}
          <button
            className="px-2 py-1 rounded text-xs inline-flex items-center bg-red-50 text-red-700 hover:bg-red-100 dark:bg-red-900/30 dark:text-red-300 dark:hover:bg-red-900/50 disabled:opacity-50 disabled:cursor-not-allowed"
            onClick={handleBulkLock}
            disabled={bulkLockMut.isPending}
            title="Lock every unlocked period whose end_date is before a chosen cutoff"
          >
            <Lock className="w-3 h-3 mr-1" /> {bulkLockMut.isPending ? 'Locking…' : 'Bulk lock…'}
          </button>
          <button
            className="px-2 py-1 bg-surface-100 hover:bg-surface-200 dark:bg-surface-800 dark:hover:bg-surface-700 rounded text-xs inline-flex items-center"
            onClick={() => setShowNew(true)}
          >
            <Plus className="w-3 h-3 mr-1" /> New period
          </button>
        </div>
      </div>
      {/* WEB-UIUX-1150: show loading skeleton on cold load to avoid empty-state false positive. */}
      {isLoading && (
        <div className="space-y-2">
          {[0, 1, 2].map((i) => (
            <div key={i} className="border dark:border-surface-700 rounded p-2 animate-pulse">
              <div className="flex items-center justify-between">
                <div className="space-y-1">
                  <div className="h-3 w-28 bg-surface-200 dark:bg-surface-700 rounded" />
                  <div className="h-2.5 w-36 bg-surface-100 dark:bg-surface-700/60 rounded" />
                </div>
                <div className="h-6 w-16 bg-surface-200 dark:bg-surface-700 rounded" />
              </div>
            </div>
          ))}
          <p className="text-xs text-surface-500 dark:text-surface-400 text-center py-1 inline-flex items-center justify-center gap-1 w-full">
            <Loader2 className="w-3 h-3 animate-spin" /> Loading periods…
          </p>
        </div>
      )}
      {!isLoading && periods.length === 0 && (
        <p className="text-xs text-surface-500 dark:text-surface-400 py-4 text-center">No payroll periods yet.</p>
      )}
      <div className="space-y-2">
        {periods.map((p) => (
          <div
            key={p.id}
            className={`border dark:border-surface-700 rounded p-2 text-xs ${p.locked_at ? 'bg-surface-50 dark:bg-surface-800/50' : ''}`}
          >
            <div className="flex items-center justify-between">
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-surface-800 dark:text-surface-100">{p.name}</div>
                <div className="text-surface-500 dark:text-surface-400">{p.start_date} → {p.end_date}</div>
                {/* WEB-UIUX-1145: only preview unlocked periods — locked rows
                    are frozen, so the lock-consequences answer is "nothing
                    new". Keeps the locked row visually compact. */}
                {!p.locked_at && <PeriodLockConsequencesPreview period={p} />}
              </div>
              <div className="flex items-center gap-2">
                <button
                  className="p-1 text-surface-600 dark:text-surface-300 hover:text-primary-600"
                  title="Download CSV"
                  onClick={() => downloadCsv(p.id)}
                >
                  <Download className="w-4 h-4" />
                </button>
                {p.locked_at ? (
                  <span className="inline-flex flex-col items-end text-surface-500 dark:text-surface-400" title="Locked">
                    <Lock className="w-4 h-4" />
                    {/* WEB-UIUX-1144: render locked_by_user_id + locked_at beneath the lock icon. */}
                    <span className="text-[10px] leading-tight mt-0.5">
                      Locked by {p.locked_by_user_id} · {formatDate(p.locked_at)}
                    </span>
                  </span>
                ) : (
                  // WEB-UIUX-1141: irreversible Lock action — red, not amber.
                  // WEB-UIUX-1151: disable ONLY the row whose lock is in flight
                  // (variables === p.id) so other rows stay live.
                  // WEB-UIUX-1155: aria-label includes the period name so SR
                  // users hear "Lock 2026-W14" rather than just "Lock, button".
                  <button
                    className="px-2 py-1 bg-red-600 text-white rounded text-xs inline-flex items-center hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
                    disabled={lockMut.isPending && lockMut.variables === p.id}
                    onClick={() => handleLockPeriod(p)}
                    aria-label={`Lock commission period ${p.name} (${p.start_date} to ${p.end_date})`}
                  >
                    {lockMut.isPending && lockMut.variables === p.id ? (
                      <Loader2 className="w-3 h-3 animate-spin mr-1" />
                    ) : (
                      <LockOpen className="w-3 h-3 mr-1" />
                    )}
                    Lock
                  </button>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* WEB-UIUX-1148: pagination footer when total > per_page. Hidden on
          single-page results so weekly tenants in their first year see
          nothing new. */}
      {pagination && pagination.total_pages > 1 && (
        <div className="mt-3 flex items-center justify-between gap-2 text-xs text-surface-500 dark:text-surface-400">
          <span>
            Page {pagination.page} of {pagination.total_pages} · {pagination.total} period{pagination.total === 1 ? '' : 's'}
          </span>
          <div className="flex gap-1">
            <button
              type="button"
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="rounded border dark:border-surface-600 px-2 py-1 disabled:opacity-50 hover:bg-surface-50 dark:hover:bg-surface-700"
            >
              Prev
            </button>
            <button
              type="button"
              onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
              disabled={page >= pagination.total_pages}
              className="rounded border dark:border-surface-600 px-2 py-1 disabled:opacity-50 hover:bg-surface-50 dark:hover:bg-surface-700"
            >
              Next
            </button>
          </div>
        </div>
      )}

      {showNew && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => {
            // WEB-UIUX-1154: dirty-guard on backdrop click — confirm before discarding entered data.
            const isDirty = newName || newStart || newEnd;
            if (!isDirty || window.confirm('Discard this period?')) {
              setShowNew(false);
            }
          }}
        >
          <div
            ref={newPeriodDialogRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="new-payroll-period-title"
            className="bg-white dark:bg-surface-800 rounded-lg shadow-xl max-w-md w-full p-5"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 id="new-payroll-period-title" className="text-lg font-bold mb-4 text-surface-900 dark:text-surface-100">New payroll period</h2>
            <div className="space-y-3">
              <label className="block">
                <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Name</span>
                <input
                  type="text"
                  className="mt-1 w-full border dark:border-surface-600 rounded px-2 py-1.5 text-sm bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder="e.g. 2026-W14"
                />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="block">
                  <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Start</span>
                  <input
                    type="date"
                    className="mt-1 w-full border dark:border-surface-600 rounded px-2 py-1.5 text-sm bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100"
                    value={newStart}
                    onChange={(e) => setNewStart(e.target.value)}
                  />
                </label>
                <label className="block">
                  <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">End</span>
                  <input
                    type="date"
                    className="mt-1 w-full border dark:border-surface-600 rounded px-2 py-1.5 text-sm bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100"
                    value={newEnd}
                    onChange={(e) => setNewEnd(e.target.value)}
                  />
                </label>
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-surface-50 dark:hover:bg-surface-800"
                onClick={() => setShowNew(false)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed"
                // WEB-UIUX-1153: also block submit when end < start so the cashier
                // gets immediate visual feedback instead of a server 400 after click.
                disabled={!newName || !newStart || !newEnd || createMut.isPending || (Boolean(newStart) && Boolean(newEnd) && newEnd < newStart)}
                title={newStart && newEnd && newEnd < newStart ? 'End date must be on or after start date' : undefined}
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                {/* WEB-UIUX-1152: use explicit action label instead of generic "Save". */}
                Create period
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
