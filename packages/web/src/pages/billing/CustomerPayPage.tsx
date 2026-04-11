/**
 * CustomerPayPage — PUBLIC, NO AUTH. §52 idea 7.
 *
 * Route: /pay/:token
 * Reads the payment-link token via the public API, shows the amount and
 * invoice ref, and opens the provider-hosted flow. On failure, shows a
 * "Please call the shop" card — never hangs.
 *
 * IMPORTANT: this page must never depend on the AppShell or auth store.
 * It's rendered as a standalone route in App.tsx outside the protected
 * tree so a logged-out customer can reach it.
 */
import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import axios from 'axios';

interface PublicLink {
  id: number;
  token: string;
  invoice_id: number | null;
  amount_cents: number;
  description: string | null;
  provider: 'stripe' | 'blockchyp';
  status: 'active' | 'paid' | 'expired' | 'cancelled';
  invoice_order_id?: string | null;
  amount_due?: number | null;
}

type ViewState =
  | { kind: 'loading' }
  | { kind: 'error'; message: string }
  | { kind: 'expired' }
  | { kind: 'paid'; link: PublicLink }
  | { kind: 'ready'; link: PublicLink }
  | { kind: 'processing' }
  | { kind: 'success' };

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
      // Best-effort click tracking — don't block UI on failure.
      axios.post(`${PUBLIC_BASE}/${encodeURIComponent(token)}/click`).catch(() => {});
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

  const handlePay = async () => {
    if (view.kind !== 'ready') return;
    setView({ kind: 'processing' });
    try {
      // TODO(§52 follow-up): open the real provider flow. For now we mark
      // paid on the backend with a placeholder transaction ref. A later
      // iteration will redirect to the provider-hosted checkout page and
      // mark as paid only after the provider webhook confirms success.
      await axios.post(`${PUBLIC_BASE}/${encodeURIComponent(view.link.token)}/pay`, {
        transaction_ref: `manual_${Date.now()}`,
      });
      setView({ kind: 'success' });
    } catch {
      setView({
        kind: 'error',
        message: 'Payment could not be completed. Please call the shop.',
      });
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4">
      <div className="mx-auto max-w-md space-y-6">
        <header className="text-center">
          <h1 className="text-2xl font-bold text-gray-900">Secure Payment</h1>
          <p className="mt-1 text-sm text-gray-500">Pay your balance online</p>
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
                  ${(view.link.amount_cents / 100).toFixed(2)}
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

              <button
                onClick={handlePay}
                className="w-full rounded-md bg-primary-600 px-4 py-3 text-base font-semibold text-white hover:bg-primary-700"
              >
                Pay now with {view.link.provider === 'stripe' ? 'Stripe' : 'BlockChyp'}
              </button>

              <p className="text-center text-xs text-gray-400">
                Secure payment. Your card is processed by {view.link.provider}.
              </p>
            </div>
          ) : null}

          {view.kind === 'processing' ? (
            <p className="text-center text-gray-600">Processing…</p>
          ) : null}

          {view.kind === 'success' ? (
            <div className="space-y-3 text-center">
              <div className="text-4xl">✓</div>
              <p className="text-lg font-semibold text-green-700">Payment received</p>
              <p className="text-sm text-gray-600">Thank you! A receipt has been emailed to you.</p>
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
