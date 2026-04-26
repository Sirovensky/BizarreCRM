import { useQuery } from '@tanstack/react-query';
import { AlertTriangle, Gift, Users, TrendingUp, Share2 } from 'lucide-react';
import axios from 'axios';
import { api } from '@/api/client';

/**
 * ReferralsDashboard — read-only view of the referrals table maintained
 * by the portal agent. Shows:
 *   - Total referrals sent
 *   - Total converted (referred_customer_id or converted_invoice_id set)
 *   - Recent activity list (joined with customer names)
 *   - Leaderboard: top referrers by conversions
 *
 * No writes here — code minting happens on the customer detail page or
 * on the customer portal. This page is pure analytics.
 *
 * FA-M15: the server endpoint is `GET /api/v1/reports/referrals`
 * (reports.routes.ts:2896, admin/manager-gated). If the endpoint is
 * missing (older server) or the caller lacks role, we render a
 * "Not available" empty state instead of a broken fetch loop.
 */

interface ReferralStats {
  total: number;
  converted: number;
  conversion_rate: number;
}

interface ReferralRow {
  id: number;
  referral_code: string;
  referrer_customer_id: number;
  referrer_name: string | null;
  referred_name: string | null;
  reward_applied: number;
  created_at: string;
  converted_at: string | null;
}

interface LeaderboardRow {
  customer_id: number;
  name: string;
  referrals: number;
  conversions: number;
}

/**
 * Compute stats on the client from the referrals list. The CRM server
 * exposes the raw rows via an internal helper endpoint — until a dedicated
 * `/crm/referrals/stats` endpoint is wired, compute on the client so this
 * page still ships.
 */
function computeStats(rows: ReferralRow[]): ReferralStats {
  const total = rows.length;
  const converted = rows.filter((r) => r.converted_at).length;
  const conversion_rate = total === 0 ? 0 : Math.round((converted / total) * 100);
  return { total, converted, conversion_rate };
}

function computeLeaderboard(rows: ReferralRow[]): LeaderboardRow[] {
  const byReferrer = new Map<number, LeaderboardRow>();
  for (const r of rows) {
    const existing = byReferrer.get(r.referrer_customer_id) ?? {
      customer_id: r.referrer_customer_id,
      name: r.referrer_name ?? `Customer #${r.referrer_customer_id}`,
      referrals: 0,
      conversions: 0,
    };
    existing.referrals += 1;
    if (r.converted_at) existing.conversions += 1;
    byReferrer.set(r.referrer_customer_id, existing);
  }
  return Array.from(byReferrer.values())
    .sort((a, b) => b.conversions - a.conversions || b.referrals - a.referrals)
    .slice(0, 10);
}

interface ReferralsQueryResult {
  rows: ReferralRow[];
  unavailable: boolean;
  /**
   * WEB-FC-012 (Fixer-B23 2026-04-25): server-reported total row count if
   * the API exposes it (e.g. via `meta.total` or `X-Total-Count` header).
   * Falls back to `null` when unavailable so the UI can show
   * "Showing N of N+" honestly instead of pretending the first page is the
   * whole dataset.
   */
  serverTotal: number | null;
}

export function ReferralsDashboard() {
  // WEB-FC-011 (Fixer-B23 2026-04-25): only swallow the *expected* "endpoint
  // gone / forbidden" cases (404 + 403/401) into the friendly empty state.
  // 5xx + network errors now surface a real error banner so admins can tell
  // "no referrals yet" from "the server is broken".
  const { data, isLoading, isError, error, refetch, isFetching } = useQuery<ReferralsQueryResult>({
    queryKey: ['reports', 'referrals'],
    queryFn: async () => {
      try {
        const res = await api.get('/reports/referrals');
        const rows = (res.data?.data as ReferralRow[] | undefined) ?? [];
        const meta = res.data?.meta as { total?: number } | undefined;
        const headerTotal = res.headers?.['x-total-count'];
        const serverTotal =
          typeof meta?.total === 'number'
            ? meta.total
            : typeof headerTotal === 'string' && /^\d+$/.test(headerTotal)
              ? Number(headerTotal)
              : null;
        return { rows, unavailable: false, serverTotal };
      } catch (err) {
        // FA-M15: missing endpoint or role-denied are *expected* on older
        // servers / non-admin tenants and render the friendly "Not
        // available" panel. Anything else (5xx, network, CORS) re-throws
        // so react-query exposes isError to the banner below.
        if (axios.isAxiosError(err)) {
          const status = err.response?.status;
          if (status === 404 || status === 403 || status === 401) {
            return { rows: [], unavailable: true, serverTotal: null };
          }
        }
        throw err;
      }
    },
  });

  const rows = data?.rows ?? [];
  const unavailable = data?.unavailable ?? false;
  const serverTotal = data?.serverTotal ?? null;
  const stats = computeStats(rows);
  const leaderboard = computeLeaderboard(rows);
  // WEB-FC-012: when server returns a total > the rows we have, show a
  // truthful "Showing X of Y" hint and warn that the leaderboard / totals
  // are computed from the loaded slice only.
  const isPartialPage = serverTotal !== null && serverTotal > rows.length;

  return (
    <div className="max-w-6xl mx-auto">
      <header className="mb-6 flex items-center gap-3">
        <Gift className="h-6 w-6 text-primary-600 dark:text-primary-400" />
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Referrals</h1>
          <p className="text-sm text-surface-500">Track your word-of-mouth engine.</p>
        </div>
      </header>

      {isLoading ? (
        <div className="text-center py-12 text-surface-500">Loading referrals...</div>
      ) : isError ? (
        <div
          role="alert"
          aria-live="polite"
          className="rounded-xl border border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-950/40 p-6 flex items-start gap-3"
        >
          <AlertTriangle className="h-5 w-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" aria-hidden="true" />
          <div className="flex-1">
            <div className="font-semibold text-red-700 dark:text-red-300">Failed to load referrals</div>
            <p className="text-sm text-red-600 dark:text-red-400 mt-1">
              {error instanceof Error ? error.message : 'An unexpected error occurred. Try again or contact support if it persists.'}
            </p>
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="mt-3 px-3 py-1.5 rounded-md text-sm font-medium border border-red-300 dark:border-red-700 text-red-700 dark:text-red-300 hover:bg-red-100 dark:hover:bg-red-900/40 disabled:opacity-50"
            >
              {isFetching ? 'Retrying...' : 'Retry'}
            </button>
          </div>
        </div>
      ) : unavailable ? (
        <div className="rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-10 text-center">
          <Gift className="h-10 w-10 text-surface-400 mx-auto mb-3" />
          <div className="text-lg font-semibold text-surface-800 dark:text-surface-200 mb-1">
            Referrals analytics are not available
          </div>
          <p className="text-sm text-surface-500 max-w-md mx-auto">
            Your account does not have access to the referrals report, or the server is
            running an older build that does not expose it. Ask an admin to enable
            this feature or update the CRM.
          </p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-2">
            <StatCard
              icon={Share2}
              label="Total referrals"
              value={isPartialPage ? `${stats.total}+` : stats.total}
            />
            <StatCard icon={Users} label="Converted" value={stats.converted} />
            <StatCard icon={TrendingUp} label="Conversion rate" value={`${stats.conversion_rate}%`} />
          </div>

          {isPartialPage && (
            <div
              role="note"
              className="mb-6 text-xs text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-md px-3 py-2"
            >
              Showing {rows.length.toLocaleString()} of {serverTotal!.toLocaleString()} referrals.
              Totals, conversion rate, and the top-referrers leaderboard are computed from the loaded
              page only.
            </div>
          )}

          <section className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4">
              <h2 className="font-semibold text-surface-900 dark:text-surface-100 mb-3">
                Top referrers
              </h2>
              {leaderboard.length === 0 ? (
                <div className="py-6 text-center text-sm text-surface-500">No referrals yet.</div>
              ) : (
                <ul className="divide-y divide-surface-200 dark:divide-surface-700">
                  {leaderboard.map((row, idx) => (
                    <li key={row.customer_id} className="py-2 flex items-center gap-3 text-sm">
                      <span className="w-6 text-center font-bold text-surface-500">#{idx + 1}</span>
                      <span className="flex-1 truncate">{row.name}</span>
                      <span className="text-xs text-surface-500">{row.referrals} sent</span>
                      <span className="text-xs font-semibold text-emerald-600">{row.conversions} converted</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <div className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4">
              <h2 className="font-semibold text-surface-900 dark:text-surface-100 mb-3">
                Recent activity
              </h2>
              {rows.length === 0 ? (
                <div className="py-6 text-center text-sm text-surface-500">Nothing to show.</div>
              ) : (
                <ul className="divide-y divide-surface-200 dark:divide-surface-700">
                  {rows.slice(0, 20).map((r) => (
                    <li key={r.id} className="py-2 text-sm">
                      <div className="flex items-center justify-between">
                        <code className="font-mono text-xs">{r.referral_code}</code>
                        <span className="text-[10px] text-surface-500">
                          {new Date(r.created_at).toLocaleDateString()}
                        </span>
                      </div>
                      <div className="text-xs text-surface-500 mt-0.5">
                        {r.referrer_name ?? `#${r.referrer_customer_id}`} → {r.referred_name ?? 'pending'}
                        {r.converted_at && <span className="text-emerald-600 ml-1">(converted)</span>}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </section>
        </>
      )}
    </div>
  );
}

interface StatCardProps {
  icon: typeof Gift;
  label: string;
  value: number | string;
}

function StatCard({ icon: Icon, label, value }: StatCardProps) {
  return (
    <div className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4">
      <div className="flex items-center gap-2 text-xs text-surface-500 uppercase tracking-wide">
        <Icon className="h-4 w-4" />
        {label}
      </div>
      <div className="mt-2 text-2xl font-bold text-surface-900 dark:text-surface-100 tabular-nums">
        {value}
      </div>
    </div>
  );
}
