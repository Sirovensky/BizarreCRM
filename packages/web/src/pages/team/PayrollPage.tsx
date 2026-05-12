import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  AlertCircle,
  CalendarDays,
  CheckCircle2,
  FileText,
  Loader2,
  Lock,
  LockOpen,
  ShieldAlert,
  type LucideIcon,
} from 'lucide-react';
import { api } from '@/api/client';
import { CommissionPeriodLock } from '@/components/team/CommissionPeriodLock';
import { useHasRole } from '@/hooks/useHasRole';
import { extractApiError } from '@/utils/apiError';
import { formatDateTime } from '@/utils/format';

interface PayrollPeriod {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  locked_at: string | null;
  locked_by_user_id: number | null;
  notes: string | null;
}

interface StatCardProps {
  icon: LucideIcon;
  label: string;
  value: string;
  detail: string;
  tone: 'blue' | 'green' | 'amber' | 'surface';
}

const toneClasses: Record<StatCardProps['tone'], string> = {
  blue: 'bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-200',
  green: 'bg-green-50 text-green-700 dark:bg-green-950/40 dark:text-green-200',
  amber: 'bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-200',
  surface: 'bg-surface-100 text-surface-700 dark:bg-surface-800 dark:text-surface-200',
};

function StatCard({ icon: Icon, label, value, detail, tone }: StatCardProps) {
  return (
    <div className="rounded-lg border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-900">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-medium uppercase text-surface-500 dark:text-surface-400">{label}</p>
          <p className="mt-2 text-2xl font-semibold tabular-nums text-surface-900 dark:text-surface-50">{value}</p>
        </div>
        <span className={`rounded-lg p-2 ${toneClasses[tone]}`}>
          <Icon className="h-5 w-5" />
        </span>
      </div>
      <p className="mt-3 text-sm text-surface-500 dark:text-surface-400">{detail}</p>
    </div>
  );
}

function formatDateOnly(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return value;
  const [, y, m, d] = match;
  return new Date(Number(y), Number(m) - 1, Number(d)).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function formatPeriodRange(period: PayrollPeriod): string {
  return `${formatDateOnly(period.start_date)} to ${formatDateOnly(period.end_date)}`;
}

export function PayrollPage() {
  // WEB-FAE-001 follow-up: route role gate through shared useHasRole hook.
  const isManager = useHasRole('manager');
  const {
    data,
    isLoading,
    isError,
    error,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['team', 'payroll', 'periods'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: PayrollPeriod[] }>(
        '/team/payroll/periods',
      );
      return res.data.data;
    },
  });

  const periods = data || [];
  const stats = useMemo(() => {
    const locked = periods.filter((p) => !!p.locked_at);
    const unlocked = periods.filter((p) => !p.locked_at);
    const lastLocked = locked
      .slice()
      .sort((a, b) => new Date(b.locked_at || 0).getTime() - new Date(a.locked_at || 0).getTime())[0];
    return {
      lockedCount: locked.length,
      unlockedCount: unlocked.length,
      latestPeriod: periods[0] || null,
      lastLocked,
    };
  }, [periods]);

  const apiError = isError ? extractApiError(error) : null;

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6 text-surface-900 dark:text-surface-100">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-50">Payroll</h1>
          <p className="mt-1 max-w-2xl text-sm text-surface-500 dark:text-surface-400">
            Periods, locks, and exports for commission and time-entry payroll review.
          </p>
        </div>
        <div className="rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-xs text-surface-600 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300">
          CSV exports use saved payroll periods.
        </div>
      </header>

      {isManager && (
        <div className="flex gap-3 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-900/60 dark:bg-amber-950/30 dark:text-amber-100">
          <ShieldAlert className="mt-0.5 h-5 w-5 flex-none" />
          <div>
            <p className="font-semibold">Admin approval required for final payroll actions</p>
            <p className="mt-1 text-amber-800 dark:text-amber-200">
              Managers can prepare periods. Locking a period and downloading the payroll CSV require an admin account.
            </p>
          </div>
        </div>
      )}

      {isLoading && (
        <div className="rounded-lg border border-surface-200 bg-white p-8 text-center dark:border-surface-700 dark:bg-surface-900">
          <Loader2 className="mx-auto h-8 w-8 animate-spin text-primary-600" />
          <p className="mt-3 text-sm font-medium text-surface-700 dark:text-surface-200">Loading payroll periods...</p>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">Checking period status before showing payroll controls.</p>
        </div>
      )}

      {apiError && (
        <div className="rounded-lg border border-error-200 bg-error-50 p-4 text-error-800 dark:border-error-900 dark:bg-error-950/40 dark:text-error-200">
          <div className="flex gap-3">
            <AlertCircle className="mt-0.5 h-5 w-5 flex-none" />
            <div className="min-w-0">
              <p className="font-semibold">Payroll periods could not be loaded</p>
              <p className="mt-1 text-sm">{apiError.message}</p>
              {(apiError.code || apiError.requestId) && (
                <p className="mt-2 font-mono text-xs text-error-700 dark:text-error-300">
                  {apiError.code ? `${apiError.code} ` : ''}
                  {apiError.requestId ? `ref ${apiError.requestId}` : ''}
                </p>
              )}
              <button
                type="button"
                onClick={() => void refetch()}
                disabled={isFetching}
                className="mt-3 inline-flex items-center rounded border border-error-300 px-3 py-1.5 text-xs font-semibold text-error-800 hover:bg-error-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-error-800 dark:text-error-100 dark:hover:bg-error-900/40"
              >
                {isFetching && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
                Retry
              </button>
            </div>
          </div>
        </div>
      )}

      {!isLoading && !apiError && periods.length === 0 && (
        <div className="rounded-lg border border-surface-200 bg-white p-10 text-center dark:border-surface-700 dark:bg-surface-900">
          <CalendarDays className="mx-auto h-12 w-12 text-surface-300 dark:text-surface-600" />
          <h2 className="mt-4 text-lg font-semibold text-surface-900 dark:text-surface-50">No payroll periods yet</h2>
          <p className="mx-auto mt-2 max-w-lg text-sm text-surface-500 dark:text-surface-400">
            Create a period below before exporting or locking payroll records.
          </p>
        </div>
      )}

      {!isLoading && !apiError && periods.length > 0 && (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              icon={CalendarDays}
              label="Saved periods"
              value={String(periods.length)}
              detail={stats.latestPeriod ? `Latest: ${stats.latestPeriod.name}` : 'No saved periods'}
              tone="blue"
            />
            <StatCard
              icon={Lock}
              label="Locked"
              value={String(stats.lockedCount)}
              detail={stats.lastLocked ? `${stats.lastLocked.name} locked ${formatDateTime(stats.lastLocked.locked_at)}` : 'No periods locked yet'}
              tone="green"
            />
            <StatCard
              icon={LockOpen}
              label="Unlocked"
              value={String(stats.unlockedCount)}
              detail={stats.unlockedCount === 0 ? 'All saved periods are locked' : 'Open for payroll edits'}
              tone="amber"
            />
            <StatCard
              icon={FileText}
              label="Export format"
              value="CSV"
              detail="Admin export includes hours, commissions, tips, and gross totals"
              tone="surface"
            />
          </div>

          <section className="rounded-lg border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-900">
            <div className="border-b border-surface-100 px-4 py-3 dark:border-surface-800">
              <h2 className="text-sm font-semibold text-surface-900 dark:text-surface-50">Recent period status</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-surface-100 text-left text-xs uppercase tracking-wider text-surface-700 dark:bg-surface-800 dark:text-surface-200">
                  <tr>
                    <th className="px-4 py-3 font-semibold">Period</th>
                    <th className="px-4 py-3 font-semibold">Range</th>
                    <th className="px-4 py-3 font-semibold">Status</th>
                    <th className="px-4 py-3 font-semibold">Locked at</th>
                    <th className="px-4 py-3 font-semibold">Notes</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                  {periods.slice(0, 6).map((period) => {
                    const locked = !!period.locked_at;
                    return (
                      <tr key={period.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50">
                        <td className="px-4 py-3 font-semibold text-surface-900 dark:text-surface-50">{period.name}</td>
                        <td className="px-4 py-3 font-mono text-surface-700 dark:text-surface-200">{formatPeriodRange(period)}</td>
                        <td className="px-4 py-3">
                          <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${
                            locked
                              ? 'bg-green-50 text-green-700 dark:bg-green-950/40 dark:text-green-200'
                              : 'bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-200'
                          }`}
                          >
                            {locked ? <CheckCircle2 className="mr-1 h-3 w-3" /> : <LockOpen className="mr-1 h-3 w-3" />}
                            {locked ? 'Locked' : 'Open'}
                          </span>
                        </td>
                        <td className="px-4 py-3 font-mono text-surface-700 dark:text-surface-200">
                          {locked ? formatDateTime(period.locked_at) : '--'}
                        </td>
                        <td className="max-w-xs truncate px-4 py-3 text-surface-700 dark:text-surface-300">
                          {period.notes || '--'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}

      {!isLoading && !apiError && <CommissionPeriodLock />}
    </div>
  );
}
