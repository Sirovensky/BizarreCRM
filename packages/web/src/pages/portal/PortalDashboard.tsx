import { useState, useEffect } from 'react';
import * as api from './portalApi';
import { safeColor } from '../../utils/safeColor';
import { usePortalI18n } from './i18n';
import { formatCurrency, formatDate } from '../../utils/format';

interface PortalDashboardProps {
  onViewTicket: (ticketId: number) => void;
  onViewEstimates: () => void;
  onViewInvoices: () => void;
  onLogout: () => void;
  customerName: string | null;
}

export function PortalDashboard({ onViewTicket, onViewEstimates, onViewInvoices, onLogout, customerName }: PortalDashboardProps) {
  const { locale } = usePortalI18n();
  const [dashboard, setDashboard] = useState<api.DashboardData | null>(null);
  const [tickets, setTickets] = useState<api.TicketSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([api.getDashboard(), api.getTickets()])
      .then(([dash, tix]) => {
        setDashboard(dash);
        setTickets(tix);
      })
      .catch(() => setError('Failed to load your dashboard. Please try again later.'))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    // WEB-S4-024: skeleton instead of spinner
    return (
      <div className="min-h-screen bg-surface-50 dark:bg-surface-900">
        <div className="bg-white dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700 px-4 py-4">
          <div className="max-w-2xl mx-auto flex items-center justify-between">
            <div className="space-y-2">
              <div className="animate-pulse bg-surface-200 dark:bg-surface-700 h-5 w-40 rounded" />
              <div className="animate-pulse bg-surface-200 dark:bg-surface-700 h-3 w-24 rounded" />
            </div>
            <div className="animate-pulse bg-surface-200 dark:bg-surface-700 h-4 w-16 rounded" />
          </div>
        </div>
        <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
          <div className="grid grid-cols-2 gap-3">
            {[1, 2].map(i => (
              <div key={i} className="animate-pulse bg-surface-200 dark:bg-surface-700 rounded-xl h-20" />
            ))}
          </div>
          <div className="space-y-2">
            {[1, 2, 3].map(i => (
              <div key={i} className="animate-pulse bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-xl h-20" />
            ))}
          </div>
        </div>
      </div>
    );
  }

  const store = dashboard?.store || {};
  const currency = store.store_currency || 'USD';

  return (
    <div className="min-h-screen bg-surface-50 dark:bg-surface-900">
      {/* Header */}
      <div className="bg-white dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700 px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-lg font-bold text-surface-900 dark:text-surface-100">
              Welcome back{customerName ? `, ${customerName}` : ''}
            </h1>
            <p className="text-sm text-surface-500 dark:text-surface-400">{store.store_name || 'Repair Shop'}</p>
          </div>
          <button onClick={onLogout} className="text-sm text-surface-400 dark:text-surface-500 hover:text-surface-600 dark:hover:text-surface-300">
            Sign Out
          </button>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
        {error && (
          <div className="rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 px-4 py-3 text-sm text-red-700 dark:text-red-300">{error}</div>
        )}
        {/* Summary Cards */}
        <div className="grid grid-cols-2 gap-3">
          <SummaryCard label="Open Repairs" value={dashboard?.open_tickets ?? 0} color="blue" />
          <SummaryCard label="Total Repairs" value={dashboard?.total_tickets ?? 0} color="gray" />
          {/* WEB-UIUX-1465: always render Estimates card so history is accessible even when nothing is pending */}
          <button onClick={onViewEstimates} className="text-left">
            <SummaryCard
              label={(dashboard?.pending_estimates ?? 0) > 0 ? 'Pending Estimates' : 'Estimates'}
              value={dashboard?.pending_estimates ?? 0}
              color={(dashboard?.pending_estimates ?? 0) > 0 ? 'amber' : 'gray'}
            />
          </button>
          {(dashboard?.outstanding_balance ?? 0) > 0 && (
            <button onClick={onViewInvoices} className="text-left">
              <SummaryCard
                label="Balance Due"
                value={formatCurrency(dashboard?.outstanding_balance ?? 0, currency, locale)}
                color="red"
              />
            </button>
          )}
        </div>

        {/* Membership self-service (WEB-UIUX-1485 / customer-portal self-service cancel) */}
        <MembershipCard currency={currency} locale={locale} />

        {/* Ticket List */}
        <div>
          <h2 className="text-sm font-semibold text-surface-700 dark:text-surface-300 mb-3">Your Repairs</h2>
          {tickets.length === 0 ? (
            <div className="rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-8 text-center text-sm text-surface-400 dark:text-surface-500">
              No repairs found
            </div>
          ) : (
            <div className="space-y-2">
              {tickets.map(ticket => (
                <button
                  key={ticket.id}
                  onClick={() => onViewTicket(ticket.id)}
                  className="w-full text-left rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-4 hover:border-primary-300 dark:hover:border-primary-500 hover:shadow-sm transition-all"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">{ticket.order_id}</span>
                        <StatusBadge name={ticket.status.name} color={ticket.status.color} />
                      </div>
                      <div className="text-sm text-surface-600 dark:text-surface-400">
                        {ticket.devices.map(d => d.name || d.type).join(', ') || 'Device'}
                      </div>
                      <div className="text-xs text-surface-400 dark:text-surface-500 mt-1">
                        {formatDate(ticket.created_at, locale)}
                        {ticket.due_on && ` — Due: ${formatDate(ticket.due_on, locale)}`}
                      </div>
                    </div>
                    <svg className="w-5 h-5 text-surface-300 dark:text-surface-600 flex-shrink-0 mt-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
                    </svg>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Quick Links */}
        <div className="flex gap-3">
          {/* WEB-UIUX-1465: always render Estimates CTA — primary amber when pending>0, secondary/muted when 0 so history remains accessible */}
          <button
            onClick={onViewEstimates}
            className={
              (dashboard?.pending_estimates ?? 0) > 0
                ? 'flex-1 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-700 hover:bg-amber-100 transition-colors'
                : 'flex-1 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-4 py-3 text-sm font-medium text-surface-500 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors'
            }
          >
            {(dashboard?.pending_estimates ?? 0) > 0
              ? `View Estimates (${dashboard?.pending_estimates} pending)`
              : 'View Estimates'}
          </button>
          {(dashboard?.outstanding_invoices ?? 0) > 0 && (
            <button
              onClick={onViewInvoices}
              className="flex-1 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-700 hover:bg-red-100 transition-colors"
            >
              View Invoices ({dashboard?.outstanding_invoices})
            </button>
          )}
        </div>

        {/* Store Info */}
        <div className="rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-4">
          <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-300 mb-2">Contact Us</h3>
          <div className="space-y-1 text-sm text-surface-600 dark:text-surface-400">
            {store.store_phone && (
              <a href={`tel:${store.store_phone}`} rel="noreferrer noopener" className="flex items-center gap-2 hover:text-primary-600">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                </svg>
                {store.store_phone}
              </a>
            )}
            {store.store_email && (
              <a href={`mailto:${store.store_email}`} rel="noreferrer noopener" className="flex items-center gap-2 hover:text-primary-600">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
                {store.store_email}
              </a>
            )}
            {store.store_address && (
              <div className="flex items-start gap-2">
                <svg className="w-4 h-4 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path strokeLinecap="round" strokeLinejoin="round" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                <span>{[store.store_address, store.store_city, store.store_state, store.store_zip].filter(Boolean).join(', ')}</span>
              </div>
            )}
            {store.store_hours && (
              <div className="flex items-start gap-2">
                <svg className="w-4 h-4 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>{store.store_hours}</span>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function SummaryCard({ label, value, color }: { label: string; value: number | string; color: string }) {
  const colorMap: Record<string, string> = {
    blue: 'bg-primary-50 border-primary-200 text-primary-700',
    gray: 'bg-surface-50 border-surface-200 text-surface-700 dark:bg-surface-800 dark:border-surface-700 dark:text-surface-300',
    amber: 'bg-amber-50 border-amber-200 text-amber-700',
    red: 'bg-red-50 border-red-200 text-red-700',
    green: 'bg-green-50 border-green-200 text-green-700',
  };
  return (
    <div className={`rounded-xl border p-4 ${colorMap[color] || colorMap.gray}`}>
      <div className="text-2xl font-bold">{value}</div>
      <div className="text-xs font-medium opacity-75">{label}</div>
    </div>
  );
}

function StatusBadge({ name, color }: { name: string; color: string }) {
  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium text-white"
      style={{ backgroundColor: safeColor(color) }}
    >
      {name}
    </span>
  );
}

interface MembershipCardProps {
  currency: string;
  locale: string;
}

function MembershipCard({ currency, locale }: MembershipCardProps) {
  const [membership, setMembership] = useState<api.PortalMembership | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [confirming, setConfirming] = useState<'cancel' | 'resume' | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    api.getPortalMembership()
      .then((m) => setMembership(m))
      .catch(() => { /* silently absent — non-fatal */ })
      .finally(() => setLoaded(true));
  }, []);

  if (!loaded || !membership) return null;

  const periodEnd = membership.current_period_end ? formatDate(membership.current_period_end, locale) : null;
  const pendingCancel = !!membership.cancel_at_period_end;

  async function commit(action: 'cancel' | 'resume') {
    setBusy(true);
    setErr(null);
    try {
      if (action === 'cancel') {
        await api.cancelPortalMembership();
      } else {
        await api.resumePortalMembership();
      }
      const fresh = await api.getPortalMembership();
      setMembership(fresh);
      setConfirming(null);
    } catch (e) {
      setErr((e as { response?: { data?: { message?: string } } })?.response?.data?.message
        ?? 'Could not update membership. Please try again.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-4 space-y-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
            {membership.tier_name || 'Membership'}
          </h2>
          {membership.monthly_price != null && (
            <p className="text-sm text-surface-600 dark:text-surface-400">
              {formatCurrency(membership.monthly_price, currency, locale)} / month
            </p>
          )}
        </div>
        <span
          className={
            'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ' +
            (membership.status === 'active'
              ? 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300'
              : membership.status === 'past_due'
              ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300'
              : 'bg-surface-100 text-surface-700 dark:bg-surface-700 dark:text-surface-300')
          }
        >
          {pendingCancel ? 'Cancels at period end' : membership.status}
        </span>
      </div>

      {periodEnd && (
        <p className="text-xs text-surface-500 dark:text-surface-400">
          {pendingCancel
            ? `Access continues through ${periodEnd}. No further charges.`
            : `Next billing on or after ${periodEnd}.`}
        </p>
      )}

      {err && (
        <div role="alert" className="text-xs text-red-600 dark:text-red-400">
          {err}
        </div>
      )}

      {!confirming && !pendingCancel && (
        <button
          type="button"
          onClick={() => setConfirming('cancel')}
          className="text-sm font-medium text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300"
        >
          Cancel membership
        </button>
      )}
      {!confirming && pendingCancel && (
        <button
          type="button"
          onClick={() => setConfirming('resume')}
          className="text-sm font-medium text-primary-600 hover:text-primary-700"
        >
          Keep my membership
        </button>
      )}

      {confirming === 'cancel' && (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm dark:border-red-500/30 dark:bg-red-500/10">
          <p className="font-medium text-red-700 dark:text-red-300">Cancel at period end?</p>
          <p className="mt-1 text-red-700/80 dark:text-red-300/80">
            You will keep access until {periodEnd ?? 'the end of the current period'} and will not be charged again. You can undo this any time before then.
          </p>
          <div className="mt-2 flex gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={() => commit('cancel')}
              className="rounded-md bg-red-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50"
            >
              {busy ? 'Cancelling…' : 'Yes, cancel'}
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => setConfirming(null)}
              className="rounded-md border border-surface-300 px-3 py-1.5 text-xs hover:bg-surface-100 disabled:opacity-50 dark:border-surface-600 dark:hover:bg-surface-700"
            >
              Keep it
            </button>
          </div>
        </div>
      )}

      {confirming === 'resume' && (
        <div className="rounded-md border border-primary-200 bg-primary-50 p-3 text-sm dark:border-primary-500/30 dark:bg-primary-500/10">
          <p className="font-medium text-primary-700 dark:text-primary-300">Keep your membership?</p>
          <p className="mt-1 text-primary-700/80 dark:text-primary-300/80">
            Your scheduled cancellation will be removed and auto-renew will turn back on.
          </p>
          <div className="mt-2 flex gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={() => commit('resume')}
              className="rounded-md bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 disabled:opacity-50"
            >
              {busy ? 'Saving…' : 'Yes, keep it'}
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => setConfirming(null)}
              className="rounded-md border border-surface-300 px-3 py-1.5 text-xs hover:bg-surface-100 disabled:opacity-50 dark:border-surface-600 dark:hover:bg-surface-700"
            >
              Back
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

