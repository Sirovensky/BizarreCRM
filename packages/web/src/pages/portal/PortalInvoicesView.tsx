import { useState, useEffect } from 'react';
import * as api from './portalApi';
import { usePortalI18n } from './i18n';
import { formatCurrency } from '../../utils/formatCurrency';

interface PortalInvoicesViewProps {
  onBack: () => void;
}

export function PortalInvoicesView({ onBack }: PortalInvoicesViewProps) {
  const { locale } = usePortalI18n();
  const currency = 'USD'; // portal session does not expose store currency at list level; USD fallback
  const [invoices, setInvoices] = useState<api.InvoiceSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [detailData, setDetailData] = useState<api.InvoiceDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandError, setExpandError] = useState<string | null>(null);

  useEffect(() => {
    api.getInvoices()
      .then(setInvoices)
      .catch(() => setError('Failed to load invoices. Please try again later.'))
      .finally(() => setLoading(false));
  }, []);

  async function fetchDetail(id: number) {
    setDetailLoading(true);
    setExpandError(null);
    try {
      const detail = await api.getInvoiceDetail(id);
      setDetailData(detail);
    } catch {
      setExpandError('Failed to load invoice details. Tap to retry.');
      setDetailData(null);
    } finally {
      setDetailLoading(false);
    }
  }

  function toggleExpand(id: number) {
    if (expandedId === id) {
      setExpandedId(null);
      setDetailData(null);
      setExpandError(null);
      return;
    }
    setExpandedId(id);
    fetchDetail(id);
  }

  function retryDetail(id: number) {
    fetchDetail(id);
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-50">
        <div className="h-8 w-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="bg-white border-b border-gray-200 px-4 py-4">
        <div className="max-w-2xl mx-auto flex items-center gap-3">
          <button aria-label="Go back" onClick={onBack} className="text-gray-400 hover:text-gray-600">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <h1 className="text-lg font-bold text-gray-900">Your Invoices</h1>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-3">
        {error && (
          <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">{error}</div>
        )}
        {invoices.length === 0 && !error ? (
          <div className="rounded-xl bg-white border border-gray-200 p-8 text-center text-sm text-gray-400">
            No invoices found
          </div>
        ) : (
          invoices.map(inv => (
            <div key={inv.id} className="rounded-xl bg-white border border-gray-200 overflow-hidden">
              <button
                onClick={() => toggleExpand(inv.id)}
                className="w-full text-left p-4 hover:bg-gray-50 transition-colors"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <div className="flex items-center gap-2 mb-0.5">
                      <span className="text-sm font-semibold text-gray-900">{inv.order_id}</span>
                      <StatusBadge status={inv.status} />
                    </div>
                    <div className="text-xs text-gray-400">
                      {formatDate(inv.created_at, locale)}
                      {inv.ticket_order_id && ` — Ticket ${inv.ticket_order_id}`}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm font-semibold text-gray-900">{formatCurrency(inv.total, currency, locale)}</div>
                    {inv.amount_due > 0 && (
                      <div className="text-xs text-red-600">Due: {formatCurrency(inv.amount_due, currency, locale)}</div>
                    )}
                  </div>
                </div>
              </button>

              {expandedId === inv.id && (
                <div className="border-t border-gray-100">
                  {detailLoading ? (
                    <div className="p-4 flex justify-center">
                      <div className="h-5 w-5 border-2 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
                    </div>
                  ) : expandError ? (
                    <button
                      onClick={() => retryDetail(inv.id)}
                      className="w-full p-4 text-center text-sm text-red-600 hover:bg-red-50 transition-colors"
                    >
                      {expandError}
                    </button>
                  ) : detailData ? (
                    <div>
                      {detailData.line_items.length > 0 && (
                        <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                          <tbody>
                            {detailData.line_items.map((item, i) => (
                              <tr key={i} className={i > 0 ? 'border-t border-gray-50' : ''}>
                                <td className="px-4 py-2 text-gray-700">{item.description}</td>
                                <td className="px-4 py-2 text-right text-gray-500">x{item.quantity}</td>
                                <td className="px-4 py-2 text-right text-gray-700">{formatCurrency(item.total, currency, locale)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                        </div>
                      )}

                      <div className="p-4 border-t border-gray-100 space-y-1 text-sm">
                        <div className="flex justify-between text-gray-500">
                          <span>Subtotal</span><span>{formatCurrency(detailData.subtotal, currency, locale)}</span>
                        </div>
                        {detailData.discount > 0 && (
                          <div className="flex justify-between text-green-600">
                            <span>Discount</span><span>-{formatCurrency(detailData.discount, currency, locale)}</span>
                          </div>
                        )}
                        <div className="flex justify-between text-gray-500">
                          <span>Tax</span><span>{formatCurrency(detailData.tax, currency, locale)}</span>
                        </div>
                        <div className="flex justify-between font-semibold text-gray-900 pt-1 border-t border-gray-200">
                          <span>Total</span><span>{formatCurrency(detailData.total, currency, locale)}</span>
                        </div>
                      </div>

                      {detailData.payments.length > 0 && (
                        <div className="p-4 border-t border-gray-100">
                          <h4 className="text-xs font-semibold text-gray-500 mb-2">PAYMENTS</h4>
                          {detailData.payments.map((p, i) => (
                            <div key={i} className="flex justify-between text-sm text-gray-600">
                              <span>{p.method} — {formatDate(p.date, locale)}</span>
                              <span>{formatCurrency(p.amount, currency, locale)}</span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  ) : null}
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    paid: 'bg-green-100 text-green-700',
    partial: 'bg-amber-100 text-amber-700',
    unpaid: 'bg-red-100 text-red-700',
    draft: 'bg-gray-100 text-gray-600',
    voided: 'bg-gray-100 text-gray-400',
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${colors[status] || colors.draft}`}>
      {status.charAt(0).toUpperCase() + status.slice(1)}
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
