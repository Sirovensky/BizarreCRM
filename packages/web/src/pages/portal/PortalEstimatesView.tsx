import { useState, useEffect } from 'react';
import * as api from './portalApi';

interface PortalEstimatesViewProps {
  onBack: () => void;
}

export function PortalEstimatesView({ onBack }: PortalEstimatesViewProps) {
  const [estimates, setEstimates] = useState<api.EstimateSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [approvingId, setApprovingId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.getEstimates()
      .then(setEstimates)
      .catch(() => setError('Failed to load estimates. Please try again later.'))
      .finally(() => setLoading(false));
  }, []);

  async function handleApprove(id: number) {
    setApprovingId(id);
    setError(null);
    // Snapshot the current row so we can roll back on server failure — without
    // the snapshot, an optimistic flip to "approved" lingers forever even when
    // the server rejects, leaving the customer convinced they approved while
    // the shop has no record. Capture-then-update inside a setter so we read
    // the latest state without depending on stale closure.
    let previous: api.EstimateSummary | undefined;
    setEstimates(prev => {
      previous = prev.find(e => e.id === id);
      return prev.map(e =>
        e.id === id ? { ...e, status: 'approved', approved_at: new Date().toISOString() } : e
      );
    });
    try {
      await api.approveEstimate(id);
      // success — keep the optimistic state.
    } catch {
      // Roll back to the captured snapshot so the row reverts to its prior
      // (typically "sent") status and the Approve button reappears.
      if (previous) {
        const snapshot = previous;
        setEstimates(prev => prev.map(e => (e.id === id ? snapshot : e)));
      }
      setError('Failed to approve estimate. Please try again.');
    } finally {
      setApprovingId(null);
    }
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
          <h1 className="text-lg font-bold text-gray-900">Your Estimates</h1>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        {error && (
          <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">{error}</div>
        )}
        {estimates.length === 0 && !error ? (
          <div className="rounded-xl bg-white border border-gray-200 p-8 text-center text-sm text-gray-400">
            No estimates found
          </div>
        ) : (
          estimates.map(est => (
            <div key={est.id} className="rounded-xl bg-white border border-gray-200 overflow-hidden">
              <div className="p-4 border-b border-gray-100">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm font-semibold text-gray-900">{est.order_id}</span>
                  <EstimateStatusBadge status={est.status} />
                </div>
                <div className="text-xs text-gray-400">{formatDate(est.created_at)}</div>
              </div>

              {est.line_items.length > 0 && (
                <div className="border-b border-gray-100 overflow-x-auto">
                  <table className="w-full text-sm">
                    <tbody>
                      {est.line_items.map((item, i) => (
                        <tr key={i} className={i > 0 ? 'border-t border-gray-50' : ''}>
                          <td className="px-4 py-2 text-gray-700">{item.description}</td>
                          <td className="px-4 py-2 text-right text-gray-500">x{item.quantity}</td>
                          <td className="px-4 py-2 text-right text-gray-700">${item.total.toFixed(2)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              <div className="p-4">
                <div className="flex justify-between text-sm font-semibold text-gray-900 mb-3">
                  <span>Total</span>
                  <span>${est.total.toFixed(2)}</span>
                </div>
                {est.notes && (
                  <p className="text-xs text-gray-500 mb-3">{est.notes}</p>
                )}
                {est.valid_until && (
                  <p className="text-xs text-gray-400 mb-3">Valid until: {formatDate(est.valid_until)}</p>
                )}

                {est.status === 'sent' && (
                  <button
                    onClick={() => handleApprove(est.id)}
                    disabled={approvingId === est.id}
                    className="w-full rounded-lg bg-green-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50 transition-colors"
                  >
                    {approvingId === est.id ? 'Approving...' : 'Approve Estimate'}
                  </button>
                )}
                {est.status === 'approved' && (
                  <div className="text-sm text-green-600 text-center flex items-center justify-center gap-1">
                    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                    Approved{est.approved_at ? ` on ${formatDate(est.approved_at)}` : ''}
                  </div>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

function EstimateStatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    sent: 'bg-amber-100 text-amber-700',
    approved: 'bg-green-100 text-green-700',
    draft: 'bg-gray-100 text-gray-600',
    converted: 'bg-primary-100 text-primary-700',
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${colors[status] || colors.draft}`}>
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
}

function formatDate(date: string): string {
  try {
    return new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return date;
  }
}
