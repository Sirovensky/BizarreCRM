/**
 * Commission period lock — criticalaudit.md §53 idea #7.
 *
 * Compact card that lists payroll periods with a Lock button. Once locked,
 * the row shows a lock icon and the locked-by user. The server-side check
 * (isCommissionLocked) refuses any subsequent commission edits in the locked
 * range — so this UI is a one-way switch on purpose.
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

export function CommissionPeriodLock() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newStart, setNewStart] = useState('');
  const [newEnd, setNewEnd] = useState('');
  const newPeriodDialogRef = useFocusTrap<HTMLDivElement>(showNew, {
    initialFocusSelector: 'input',
  });

  // WEB-UIUX-1150: destructure isLoading to avoid empty-state false positive on cold load.
  const { data, isLoading } = useQuery({
    queryKey: ['team', 'payroll', 'periods'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: PayrollPeriod[] }>(
        '/team/payroll/periods',
      );
      return res.data.data;
    },
  });
  const periods: PayrollPeriod[] = data || [];

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
      const msg =
        e && typeof e === 'object' && 'response' in e
          ? (e as { response?: { data?: { error?: string } } }).response?.data?.error
          : null;
      toast.error(msg || 'Failed to create period');
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
      const msg =
        e && typeof e === 'object' && 'response' in e
          ? (e as { response?: { data?: { error?: string } } }).response?.data?.error
          : null;
      toast.error(msg || 'Lock failed');
    },
  });

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
    const ok = await confirm(
      `Lock commission period "${period.name}" (${period.start_date} to ${period.end_date})? Commission edits in this range will be blocked after locking.`,
      {
        title: 'Lock commission period?',
        confirmLabel: 'Lock period',
        danger: true,
      },
    );
    if (ok) lockMut.mutate(period.id);
  }

  return (
    <div className="bg-white dark:bg-surface-800 rounded-lg shadow border dark:border-surface-700 p-4">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-bold text-surface-800 dark:text-surface-100">Payroll periods</h2>
        <button
          className="px-2 py-1 bg-surface-100 hover:bg-surface-200 dark:bg-surface-800 dark:hover:bg-surface-700 rounded text-xs inline-flex items-center"
          onClick={() => setShowNew(true)}
        >
          <Plus className="w-3 h-3 mr-1" /> New period
        </button>
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
              <div>
                <div className="font-semibold text-surface-800 dark:text-surface-100">{p.name}</div>
                <div className="text-surface-500 dark:text-surface-400">{p.start_date} → {p.end_date}</div>
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
                  <button
                    className="px-2 py-1 bg-amber-600 text-white rounded text-xs inline-flex items-center hover:bg-amber-700"
                    disabled={lockMut.isPending}
                    onClick={() => handleLockPeriod(p)}
                  >
                    {lockMut.isPending ? (
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
                className="flex-1 px-3 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center justify-center"
                disabled={!newName || !newStart || !newEnd || createMut.isPending}
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
