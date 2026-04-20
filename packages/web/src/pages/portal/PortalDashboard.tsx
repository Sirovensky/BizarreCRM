import { useState, useEffect } from 'react';
import * as api from './portalApi';
import { safeColor } from '../../utils/safeColor';
import { usePortalI18n } from './i18n';
import { formatCurrency } from '../../utils/formatCurrency';

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
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-50">
        <div className="h-8 w-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
      </div>
    );
  }

  const store = dashboard?.store || {};
  const currency = store.store_currency || 'USD';

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-lg font-bold text-gray-900">
              Welcome back{customerName ? `, ${customerName}` : ''}
            </h1>
            <p className="text-sm text-gray-500">{store.store_name || 'Repair Shop'}</p>
          </div>
          <button onClick={onLogout} className="text-sm text-gray-400 hover:text-gray-600">
            Sign Out
          </button>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
        {error && (
          <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">{error}</div>
        )}
        {/* Summary Cards */}
        <div className="grid grid-cols-2 gap-3">
          <SummaryCard label="Open Repairs" value={dashboard?.open_tickets ?? 0} color="blue" />
          <SummaryCard label="Total Repairs" value={dashboard?.total_tickets ?? 0} color="gray" />
          {(dashboard?.pending_estimates ?? 0) > 0 && (
            <button onClick={onViewEstimates} className="text-left">
              <SummaryCard label="Pending Estimates" value={dashboard?.pending_estimates ?? 0} color="amber" />
            </button>
          )}
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

        {/* Ticket List */}
        <div>
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Your Repairs</h2>
          {tickets.length === 0 ? (
            <div className="rounded-xl bg-white border border-gray-200 p-8 text-center text-sm text-gray-400">
              No repairs found
            </div>
          ) : (
            <div className="space-y-2">
              {tickets.map(ticket => (
                <button
                  key={ticket.id}
                  onClick={() => onViewTicket(ticket.id)}
                  className="w-full text-left rounded-xl bg-white border border-gray-200 p-4 hover:border-primary-300 hover:shadow-sm transition-all"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-semibold text-gray-900">{ticket.order_id}</span>
                        <StatusBadge name={ticket.status.name} color={ticket.status.color} />
                      </div>
                      <div className="text-sm text-gray-600">
                        {ticket.devices.map(d => d.name || d.type).join(', ') || 'Device'}
                      </div>
                      <div className="text-xs text-gray-400 mt-1">
                        {formatDate(ticket.created_at, locale)}
                        {ticket.due_on && ` — Due: ${formatDate(ticket.due_on, locale)}`}
                      </div>
                    </div>
                    <svg className="w-5 h-5 text-gray-300 flex-shrink-0 mt-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
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
          {(dashboard?.pending_estimates ?? 0) > 0 && (
            <button
              onClick={onViewEstimates}
              className="flex-1 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-700 hover:bg-amber-100 transition-colors"
            >
              View Estimates ({dashboard?.pending_estimates})
            </button>
          )}
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
        <div className="rounded-xl bg-white border border-gray-200 p-4">
          <h3 className="text-sm font-semibold text-gray-700 mb-2">Contact Us</h3>
          <div className="space-y-1 text-sm text-gray-600">
            {store.store_phone && (
              <a href={`tel:${store.store_phone}`} className="flex items-center gap-2 hover:text-primary-600">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                </svg>
                {store.store_phone}
              </a>
            )}
            {store.store_email && (
              <a href={`mailto:${store.store_email}`} className="flex items-center gap-2 hover:text-primary-600">
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
    gray: 'bg-gray-50 border-gray-200 text-gray-700',
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

function formatDate(date: string, locale = 'en-US'): string {
  try {
    return new Date(date).toLocaleDateString(locale, { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return date;
  }
}
