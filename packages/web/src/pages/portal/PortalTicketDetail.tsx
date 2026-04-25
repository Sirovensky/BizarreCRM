import { useState, useEffect } from 'react';
import * as api from './portalApi';
import { safeColor } from '../../utils/safeColor';
import { usePortalI18n } from './i18n';
import { formatCurrency } from '../../utils/format';

interface PortalTicketDetailProps {
  ticketId: number;
  initialData?: api.TicketDetail | null;
  onBack: (() => void) | null;
  scope: 'ticket' | 'full' | null;
  hasAccount: boolean;
  onCreateAccount?: () => void;
}

const STATUS_PROGRESS: Record<string, number> = {
  'Open': 15, 'In Progress': 45, 'Waiting for Parts': 55,
  'Waiting on Customer': 55, 'Parts Arrived': 70, 'Warranty Repair': 35, 'On Hold': 35,
};

function getProgress(statusName: string, isClosed: boolean): number {
  if (isClosed) return 100;
  return STATUS_PROGRESS[statusName] ?? 25;
}

export function PortalTicketDetail({ ticketId, initialData, onBack, scope, hasAccount, onCreateAccount }: PortalTicketDetailProps) {
  const { locale } = usePortalI18n();
  const [ticket, setTicket] = useState<api.TicketDetail | null>(initialData || null);
  const [loading, setLoading] = useState(!initialData);
  useEffect(() => {
    if (initialData) return;
    api.getTicketDetail(ticketId)
      .then(setTicket)
      .catch(() => { /* handled by loading state */ })
      .finally(() => setLoading(false));
  }, [ticketId, initialData]);

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-surface-50 dark:bg-surface-950">
        <div className="h-8 w-8 border-4 border-blue-200 border-t-primary-600 rounded-full animate-spin" />
      </div>
    );
  }

  if (!ticket) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-surface-50 dark:bg-surface-950">
        <p className="text-surface-500 dark:text-surface-400">Ticket not found</p>
      </div>
    );
  }

  const progress = getProgress(ticket.status.name, ticket.status.is_closed);
  const currency = (ticket.store as Record<string, string>)?.store_currency || 'USD';

  // Build full timeline with check-in as first entry
  const fullTimeline: { type: string; description: string; detail?: string; created_at: string }[] = [
    {
      type: 'checkin',
      description: 'Device checked in',
      detail: ticket.checkin_notes || undefined,
      created_at: ticket.created_at,
    },
  ];
  if (ticket.due_on) {
    fullTimeline.push({
      type: 'info',
      description: `Estimated ready: ${formatDate(ticket.due_on, locale)}`,
      created_at: ticket.created_at,
    });
  }
  fullTimeline.push(...ticket.timeline);
  fullTimeline.reverse();

  return (
    <div className="min-h-screen bg-surface-50 dark:bg-surface-950">
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">

        {/* Header: ticket + customer info */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            {onBack && (
              <button aria-label="Go back" onClick={onBack} className="text-surface-400 dark:text-surface-500 hover:text-surface-600 dark:hover:text-surface-300 mt-0.5">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
                </svg>
              </button>
            )}
            <div>
              {ticket.customer_first_name && (
                <p className="text-sm text-surface-500 dark:text-surface-400">{ticket.customer_first_name}</p>
              )}
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold text-surface-900 dark:text-surface-100">{ticket.order_id}</p>
            <p className="text-xs text-surface-400 dark:text-surface-500">{formatDate(ticket.created_at, locale)}</p>
          </div>
        </div>

        {/* Status + progress */}
        <div className="rounded-xl bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium text-surface-700 dark:text-surface-200">Status</span>
            <span
              className="inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold text-white"
              style={{ backgroundColor: safeColor(ticket.status.color) }}
            >
              {ticket.status.name}
            </span>
          </div>
          <div className="h-2 rounded-full bg-surface-100 dark:bg-surface-800 overflow-hidden">
            <div
              className="h-full rounded-full transition-all duration-500"
              style={{
                width: `${progress}%`,
                backgroundColor: ticket.status.is_closed ? '#10b981' : safeColor(ticket.status.color, '#3b82f6'),
              }}
            />
          </div>
          <div className="flex justify-between mt-1.5 text-[10px] text-surface-400 dark:text-surface-500">
            <span>Received</span><span>In Progress</span><span>Ready</span><span>Complete</span>
          </div>
        </div>

        {/* Line Items (devices/services) */}
        {ticket.devices.length > 0 && (
          <div className="rounded-xl bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-surface-50 dark:bg-surface-800/60 text-xs text-surface-500 dark:text-surface-400 border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-2.5 font-medium">Line Item</th>
                  <th className="text-right px-4 py-2.5 font-medium w-20">Amount</th>
                  <th className="text-left px-4 py-2.5 font-medium hidden sm:table-cell">Notes</th>
                  <th className="text-right px-4 py-2.5 font-medium w-28">Status</th>
                </tr>
              </thead>
              <tbody>
                {ticket.devices.map((d, i) => (
                  <tr key={i} className={i > 0 ? 'border-t border-surface-50 dark:border-surface-700' : ''}>
                    <td className="px-4 py-3">
                      <div className="font-medium text-surface-900 dark:text-surface-100">{d.service || d.name || d.type || 'Repair'}</div>
                      {d.name && d.service && (
                        <div className="text-xs text-surface-400 dark:text-surface-500 mt-0.5">{d.name}</div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right text-surface-700 dark:text-surface-300">
                      {d.total != null ? formatCurrency(Number(d.total), currency, locale) : <span className="text-surface-300 dark:text-surface-600">&mdash;</span>}
                    </td>
                    <td className="px-4 py-3 text-surface-500 dark:text-surface-400 text-xs hidden sm:table-cell">
                      {d.notes || <span className="text-surface-300 dark:text-surface-600">&mdash;</span>}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {d.status ? (
                        <span className="text-xs text-surface-600 dark:text-surface-300">{d.status}</span>
                      ) : (
                        <span className="text-surface-300 dark:text-surface-600">&mdash;</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Invoice summary (if exists) */}
        {ticket.invoice && (
          <div className="rounded-xl bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 p-4">
            <div className="flex items-center justify-between mb-3">
              <span className="text-sm font-medium text-surface-700 dark:text-surface-200">Invoice {ticket.invoice.order_id}</span>
              <InvoiceStatusBadge status={ticket.invoice.status} />
            </div>
            <div className="space-y-1 text-sm">
              <div className="flex justify-between text-surface-500 dark:text-surface-400">
                <span>Subtotal</span><span>{formatCurrency(ticket.invoice.subtotal, currency, locale)}</span>
              </div>
              {ticket.invoice.discount > 0 && (
                <div className="flex justify-between text-green-600 dark:text-green-400">
                  <span>Discount</span><span>-{formatCurrency(ticket.invoice.discount, currency, locale)}</span>
                </div>
              )}
              {ticket.invoice.tax > 0 && (
                <div className="flex justify-between text-surface-500 dark:text-surface-400">
                  <span>Tax</span><span>{formatCurrency(ticket.invoice.tax, currency, locale)}</span>
                </div>
              )}
              <div className="flex justify-between font-semibold text-surface-900 dark:text-surface-100 pt-1 border-t border-surface-200 dark:border-surface-800">
                <span>Total</span><span>{formatCurrency(ticket.invoice.total, currency, locale)}</span>
              </div>
              {ticket.invoice.amount_paid > 0 && (
                <div className="flex justify-between text-green-600 dark:text-green-400">
                  <span>Paid</span><span>{formatCurrency(ticket.invoice.amount_paid, currency, locale)}</span>
                </div>
              )}
              {ticket.invoice.amount_due > 0 && (
                <div className="flex justify-between font-semibold text-red-600 dark:text-red-400 pt-1">
                  <span>Balance Due</span><span>{formatCurrency(ticket.invoice.amount_due, currency, locale)}</span>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Timeline: status changes + messages + SMS */}
        <div className="rounded-xl bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 p-4">
          <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200 mb-4">Timeline</h3>
          <div className="space-y-0">
            {fullTimeline.map((entry, i) => (
              <div key={i} className="flex gap-3">
                <div className="flex flex-col items-center">
                  <TimelineDot type={entry.type} />
                  {i < fullTimeline.length - 1 && <div className="w-px flex-1 bg-surface-200 dark:bg-surface-700" />}
                </div>
                <div className="pb-4 min-w-0 flex-1">
                  <p className="text-sm text-surface-800 dark:text-surface-200">{entry.description}</p>
                  {entry.detail && (
                    <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5 line-clamp-2">{entry.detail}</p>
                  )}
                  <p className="text-[10px] text-surface-400 dark:text-surface-500 mt-0.5">{formatDateTime(entry.created_at, locale)}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Text Us button — only show if store phone is a valid phone number */}
        {(() => {
          const rawPhone = ticket.store?.store_phone;
          if (!rawPhone) return null;
          const digits = rawPhone.replace(/\D/g, '');
          if (digits.length < 10) return null;
          const smsHref = rawPhone.startsWith('+') ? `+${digits}` : (digits.length === 10 ? `+1${digits}` : `+${digits}`);
          return (
            <a
              href={`sms:${smsHref}`}
              className="flex items-center justify-center gap-2 rounded-xl bg-green-600 px-4 py-3 text-sm font-medium text-white hover:bg-green-700 transition-colors"
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
              </svg>
              Text Us
            </a>
          );
        })()}

        {/* Account creation suggestion */}
        {scope === 'ticket' && !hasAccount && onCreateAccount && (
          <div className="rounded-lg bg-blue-50 dark:bg-blue-950/40 border border-blue-100 dark:border-blue-900 px-4 py-3 flex items-center justify-between">
            <span className="text-xs text-blue-600 dark:text-blue-300">Want to see all your repairs in one place?</span>
            <button onClick={onCreateAccount} className="text-xs font-medium text-blue-700 dark:text-blue-300 hover:underline">
              Create free account
            </button>
          </div>
        )}

        {/* Store info */}
        {ticket.store && (
          <div className="text-center text-xs text-surface-400 dark:text-surface-500 pb-4">
            {ticket.store.store_name && <span>{ticket.store.store_name}</span>}
            {ticket.store.store_phone && <span> &middot; <a href={`tel:${ticket.store.store_phone}`} className="hover:text-blue-600 dark:hover:text-blue-400">{ticket.store.store_phone}</a></span>}
          </div>
        )}
      </div>
    </div>
  );
}

function TimelineDot({ type }: { type: string }) {
  const colors: Record<string, string> = {
    checkin: 'bg-green-600',
    info: 'bg-surface-400',
    status: 'bg-blue-500',
    sms_out: 'bg-green-500',
    sms_in: 'bg-purple-500',
    customer_msg: 'bg-purple-400',
    diagnostic: 'bg-amber-500',
  };
  return <div className={`w-2.5 h-2.5 rounded-full mt-1.5 flex-shrink-0 ${colors[type] || 'bg-surface-400'}`} />;
}

function InvoiceStatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    paid: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300',
    partial: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300',
    unpaid: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300',
    draft: 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300',
    voided: 'bg-surface-100 text-surface-400 dark:bg-surface-800 dark:text-surface-500',
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${colors[status] || colors.draft}`}>
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
}

function formatDateTime(date: string, locale = 'en-US'): string {
  try {
    return new Date(date).toLocaleString(locale, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  } catch { return date; }
}

function formatDate(date: string, locale = 'en-US'): string {
  try {
    return new Date(date).toLocaleDateString(locale, { month: 'short', day: 'numeric', year: 'numeric' });
  } catch { return date; }
}
