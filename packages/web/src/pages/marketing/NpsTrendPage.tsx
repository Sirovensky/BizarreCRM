import { useQuery } from '@tanstack/react-query';
import { BarChart3, TrendingUp, ThumbsUp, ThumbsDown } from 'lucide-react';
import { api } from '@/api/client';

/**
 * NpsTrendPage — visualise customer NPS scores + monthly trend.
 *
 * The reports agent owns `nps_responses` (migration 090) and exposes the
 * trend under /reports/nps-trend. The server returns
 *   { trend, current_nps, overall, monthly: trend, recent }
 * where `monthly` is an alias for `trend` kept for this page. This is a
 * read-only consumer.
 *
 * NPS formula: (%promoters - %detractors) where
 *   promoters  = score 9-10
 *   passives   = score 7-8
 *   detractors = score 0-6
 */

interface NpsTrendResponse {
  success: boolean;
  data: {
    overall: { promoters: number; passives: number; detractors: number; nps: number };
    monthly: Array<{ month: string; promoters: number; passives: number; detractors: number; nps: number }>;
    recent: Array<{
      id: number;
      score: number;
      comment: string | null;
      responded_at: string;
      customer_name: string | null;
    }>;
  };
}

export function NpsTrendPage() {
  const { data, isLoading } = useQuery<NpsTrendResponse>({
    queryKey: ['reports', 'nps-trend'],
    queryFn: async () => {
      try {
        const res = await api.get('/reports/nps-trend');
        return res.data as NpsTrendResponse;
      } catch {
        return {
          success: true,
          data: {
            overall: { promoters: 0, passives: 0, detractors: 0, nps: 0 },
            monthly: [],
            recent: [],
          },
        };
      }
    },
  });

  const overall = data?.data?.overall ?? { promoters: 0, passives: 0, detractors: 0, nps: 0 };
  const monthly = data?.data?.monthly ?? [];
  const recent = data?.data?.recent ?? [];

  const total = overall.promoters + overall.passives + overall.detractors;
  const promoterPct = total === 0 ? 0 : Math.round((overall.promoters / total) * 100);
  const passivePct = total === 0 ? 0 : Math.round((overall.passives / total) * 100);
  const detractorPct = total === 0 ? 0 : Math.round((overall.detractors / total) * 100);

  return (
    <div className="max-w-6xl mx-auto">
      <header className="mb-6 flex items-center gap-3">
        <BarChart3 className="h-6 w-6 text-primary-600 dark:text-primary-400" />
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">NPS Trend</h1>
          <p className="text-sm text-surface-500">How likely are your customers to recommend you?</p>
        </div>
      </header>

      {isLoading ? (
        <div className="text-center py-12 text-surface-500">Loading NPS data...</div>
      ) : (
        <>
          <section className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <ScoreCard label="Overall NPS" value={overall.nps} accent="emerald" large />
            <SimpleCard label="Promoters" value={`${overall.promoters}`} sub={`${promoterPct}%`} icon={ThumbsUp} tone="emerald" />
            <SimpleCard label="Passives" value={`${overall.passives}`} sub={`${passivePct}%`} tone="amber" />
            <SimpleCard label="Detractors" value={`${overall.detractors}`} sub={`${detractorPct}%`} icon={ThumbsDown} tone="red" />
          </section>

          <section className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4 mb-6">
            <h2 className="font-semibold text-surface-900 dark:text-surface-100 mb-3 flex items-center gap-2">
              <TrendingUp className="h-4 w-4" /> Monthly trend
            </h2>
            {monthly.length === 0 ? (
              <div className="py-8 text-center text-sm text-surface-500">
                No NPS responses recorded yet. Wire the post-pickup SMS survey to start collecting.
              </div>
            ) : (
              <div className="flex items-end gap-2 h-40 overflow-x-auto">
                {monthly.map((m) => {
                  const height = Math.max(4, Math.abs(m.nps));
                  const color = m.nps >= 50 ? 'bg-emerald-500' : m.nps >= 0 ? 'bg-sky-500' : 'bg-red-500';
                  return (
                    <div key={m.month} className="flex flex-col items-center gap-1 flex-shrink-0 w-16">
                      <div className="text-[10px] tabular-nums font-semibold">{m.nps}</div>
                      <div className={`w-full rounded-t ${color}`} style={{ height: `${height}%` }} />
                      <div className="text-[10px] text-surface-500">{m.month}</div>
                    </div>
                  );
                })}
              </div>
            )}
          </section>

          <section className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4">
            <h2 className="font-semibold text-surface-900 dark:text-surface-100 mb-3">Recent responses</h2>
            {recent.length === 0 ? (
              <div className="py-6 text-center text-sm text-surface-500">No responses yet.</div>
            ) : (
              <ul className="divide-y divide-surface-200 dark:divide-surface-700">
                {recent.map((r) => (
                  <li key={r.id} className="py-3 flex items-start gap-3">
                    <div className={`flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center font-bold ${
                      r.score >= 9
                        ? 'bg-emerald-100 text-emerald-700'
                        : r.score >= 7
                          ? 'bg-amber-100 text-amber-700'
                          : 'bg-red-100 text-red-700'
                    }`}>
                      {r.score}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <div className="font-medium text-sm">{r.customer_name ?? 'Anonymous'}</div>
                        <div className="text-[10px] text-surface-500">
                          {new Date(r.responded_at).toLocaleDateString()}
                        </div>
                      </div>
                      {r.comment && (
                        <div className="text-xs text-surface-600 dark:text-surface-400 mt-1 whitespace-pre-wrap">
                          {r.comment}
                        </div>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
    </div>
  );
}

interface ScoreCardProps {
  label: string;
  value: number | string;
  accent: 'emerald' | 'sky' | 'amber' | 'red';
  large?: boolean;
}

function ScoreCard({ label, value, accent, large }: ScoreCardProps) {
  const accentClasses = {
    emerald: 'text-emerald-600 dark:text-emerald-400',
    sky: 'text-sky-600 dark:text-sky-400',
    amber: 'text-amber-600 dark:text-amber-400',
    red: 'text-red-600 dark:text-red-400',
  };
  return (
    <div className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4">
      <div className="text-xs text-surface-500 uppercase tracking-wide">{label}</div>
      <div className={`mt-2 font-bold tabular-nums ${accentClasses[accent]} ${large ? 'text-4xl' : 'text-2xl'}`}>
        {value}
      </div>
    </div>
  );
}

interface SimpleCardProps {
  label: string;
  value: string;
  sub?: string;
  icon?: typeof ThumbsUp;
  tone: 'emerald' | 'amber' | 'red';
}

function SimpleCard({ label, value, sub, icon: Icon, tone }: SimpleCardProps) {
  const toneClasses = {
    emerald: 'text-emerald-600 dark:text-emerald-400',
    amber: 'text-amber-600 dark:text-amber-400',
    red: 'text-red-600 dark:text-red-400',
  };
  return (
    <div className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4">
      <div className="flex items-center gap-2 text-xs text-surface-500 uppercase tracking-wide">
        {Icon && <Icon className={`h-4 w-4 ${toneClasses[tone]}`} />}
        {label}
      </div>
      <div className={`mt-2 text-2xl font-bold tabular-nums ${toneClasses[tone]}`}>{value}</div>
      {sub && <div className="text-xs text-surface-500 mt-1">{sub}</div>}
    </div>
  );
}
