/**
 * CustomerPayPage — PUBLIC, NO AUTH. §52 idea 7.
 *
 * Route: /pay/:token
 * Reads the payment-link token via the public API and shows the amount and
 * invoice ref. It does not mark links paid from the browser; hosted checkout
 * must be wired through a provider before this page can collect cards.
 *
 * IMPORTANT: this page must never depend on the AppShell or auth store.
 * It's rendered as a standalone route in App.tsx outside the protected
 * tree so a logged-out customer can reach it.
 */
import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import axios from 'axios';
import { formatCents } from '@/utils/format';

interface PublicLink {
  id: number;
  token: string;
  invoice_id: number | null;
  amount_cents: number;
  description: string | null;
  status: 'active' | 'paid' | 'expired' | 'cancelled';
  invoice_order_id?: string | null;
  amount_due?: number | null;
}

type ViewState =
  | { kind: 'loading' }
  | { kind: 'error'; message: string }
  | { kind: 'expired' }
  | { kind: 'paid'; link: PublicLink }
  | { kind: 'ready'; link: PublicLink };

const PUBLIC_BASE = '/api/v1/public/payment-links';

export function CustomerPayPage() {
  const { token } = useParams<{ token: string }>();
  const [view, setView] = useState<ViewState>({ kind: 'loading' });

  const loadLink = useCallback(async () => {
    if (!token) {
      setView({ kind: 'error', message: 'Missing token' });
      return;
    }
    try {
      const res = await axios.get(`${PUBLIC_BASE}/${encodeURIComponent(token)}`);
      const link = res.data?.data as PublicLink | undefined;
      if (!link) {
        setView({ kind: 'error', message: 'Link not found' });
        return;
      }
      if (link.status === 'paid') { setView({ kind: 'paid', link }); return; }
      if (link.status === 'expired' || link.status === 'cancelled') {
        setView({ kind: 'expired' });
        return;
      }
      setView({ kind: 'ready', link });
      // §26 (LOW): best-effort click tracking — the payment flow must never
      // block on analytics. Swallow the error but log it in dev so a broken
      // tracker is still visible. Not elevated to logger.warn because this is
      // public-internet traffic where transient network errors are expected.
      axios.post(`${PUBLIC_BASE}/${encodeURIComponent(token)}/click`).catch((err) => {
        if (import.meta.env?.DEV) console.debug('[CustomerPayPage] click tracking failed (non-fatal)', err);
      });
    } catch (err) {
      setView({
        kind: 'error',
        message: axios.isAxiosError(err)
          ? err.response?.data?.message ?? 'Could not load payment link'
          : 'Could not load payment link',
      });
    }
  }, [token]);

  useEffect(() => {
    loadLink();
  }, [loadLink]);

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4">
      <div className="mx-auto max-w-md space-y-6">
        <header className="text-center">
          <h1 className="text-2xl font-bold text-gray-900">Payment Request</h1>
          <p className="mt-1 text-sm text-gray-500">Review your balance</p>
        </header>

        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          {view.kind === 'loading' ? (
            <p className="text-center text-gray-500">Loading…</p>
          ) : null}

          {view.kind === 'error' ? (
            <div className="space-y-3 text-center">
              <p className="text-red-600 font-medium">{view.message}</p>
              <p className="text-sm text-gray-600">Please call the shop to complete payment.</p>
              <button
                onClick={loadLink}
                className="rounded-md bg-gray-100 px-4 py-2 text-sm hover:bg-gray-200"
              >
                Try again
              </button>
            </div>
          ) : null}

          {view.kind === 'expired' ? (
            <div className="space-y-3 text-center">
              <p className="text-amber-600 font-medium">This link is no longer valid.</p>
              <p className="text-sm text-gray-600">
                Please contact the shop for an updated payment link.
              </p>
            </div>
          ) : null}

          {view.kind === 'paid' ? (
            <div className="space-y-3 text-center">
              <div className="text-4xl">✓</div>
              <p className="text-lg font-semibold text-green-700">Already paid</p>
              <p className="text-sm text-gray-600">
                This invoice has already been paid in full. Thank you!
              </p>
            </div>
          ) : null}

          {view.kind === 'ready' ? (
            <div className="space-y-4">
              <div className="text-center">
                <p className="text-sm text-gray-500">Amount due</p>
                <p className="text-4xl font-bold text-gray-900">
                  {formatCents(view.link.amount_cents)}
                </p>
                {view.link.invoice_order_id ? (
                  <p className="mt-1 text-xs text-gray-500">
                    Invoice {view.link.invoice_order_id}
                  </p>
                ) : null}
                {view.link.description ? (
                  <p className="mt-2 text-sm text-gray-600">{view.link.description}</p>
                ) : null}
              </div>

              <div className="rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
                Online card checkout is not available for this link yet. Please call the shop to complete payment.
              </div>
            </div>
          ) : null}
        </div>

        <p className="text-center text-xs text-gray-400">
          Having trouble? Call the shop and reference this page.
        </p>
      </div>
    </div>
  );
}

export default CustomerPayPage;
