import { useQuery } from '@tanstack/react-query';
import { Gift, Users, TrendingUp, Share2 } from 'lucide-react';
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
}

export function ReferralsDashboard() {
  const { data, isLoading } = useQuery<ReferralsQueryResult>({
    queryKey: ['reports', 'referrals'],
    queryFn: async () => {
      try {
        const res = await api.get('/reports/referrals');
        const rows = (res.data?.data as ReferralRow[] | undefined) ?? [];
        return { rows, unavailable: false };
      } catch {
        // FA-M15: endpoint missing (older server) or role-denied — render
        // a friendly "Not available" state rather than loop-retrying.
        return { rows: [], unavailable: true };
      }
    },
  });

  const rows = data?.rows ?? [];
  const unavailable = data?.unavailable ?? false;
  const stats = computeStats(rows);
  const leaderboard = computeLeaderboard(rows);

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
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
            <StatCard icon={Share2} label="Total referrals" value={stats.total} />
            <StatCard icon={Users} label="Converted" value={stats.converted} />
            <StatCard icon={TrendingUp} label="Conversion rate" value={`${stats.conversion_rate}%`} />
          </div>

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
