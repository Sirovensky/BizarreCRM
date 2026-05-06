/**
 * CustomerPayPage — PUBLIC, NO AUTH. §52 idea 7.
 *
 * Route: /pay/:token
 * Reads the payment-link token via the public API and shows the amount and
 * invoice ref. "Pay now" asks the server for the tenant's hosted checkout URL
 * and redirects the customer to the provider. Falls back to "call shop" when
 * online checkout is not configured for this tenant.
 *
 * IMPORTANT: this page must never depend on the AppShell or auth store.
 * It's rendered as a standalone route in App.tsx outside the protected
 * tree so a logged-out customer can reach it.
 */
import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import axios from 'axios';
import { formatCents } from '@/utils/format';
import { Loader2 } from 'lucide-react';

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
  | { kind: 'ready'; link: PublicLink }
  | { kind: 'paying'; link: PublicLink }
  | { kind: 'checkout_unavailable'; link: PublicLink; reason?: string };

const PUBLIC_BASE = '/api/v1/public/payment-links';

export function CustomerPayPage() {
  const { token } = useParams<{ token: string }>();
  const [view, setView] = useState<ViewState>({ kind: 'loading' });
  const [paying, setPaying] = useState(false);

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
      // @audit-fixed (WEB-FJ-014 / Fixer-B11 2026-04-25): de-dupe via
      // sessionStorage so accidental refreshes + Slack/iMessage link unfurl
      // previewers don't pollute click-conversion analytics with non-user
      // activity. One POST per token per session — preview bots opening a
      // fresh sessionStorage on each fetch will still hit it once, but the
      // human user reloading 5x to "make sure" only fires once.
      const clickKey = `crm:pay-click:${token}`;
      let alreadyTracked = false;
      try { alreadyTracked = sessionStorage.getItem(clickKey) === '1'; } catch { /* storage disabled */ }
      if (!alreadyTracked) {
        try { sessionStorage.setItem(clickKey, '1'); } catch { /* storage disabled */ }
        axios.post(`${PUBLIC_BASE}/${encodeURIComponent(token)}/click`).catch((err) => {
          // @audit-fixed (WEB-FG-013 / Fixer-B1 2026-04-25): static `import.meta.env.DEV`
          // (no optional-chain) — Vite/Rollup statically replaces it at build time so the
          // entire branch (and the `console.debug` body) is dead-code-eliminated from
          // the production bundle. The previous `import.meta.env?.DEV` defeated that
          // replacement because the optional-chain is a runtime member access.
          if (import.meta.env.DEV) console.debug('[CustomerPayPage] click tracking failed (non-fatal)', err);
        });
      }
    } catch (err) {
      setView({
        kind: 'error',
        message: axios.isAxiosError(err)
          ? err.response?.data?.message ?? 'Could not load payment link'
          : 'Could not load payment link',
      });
    }
  }, [token]);

  // Post to server to get the tenant-hosted checkout URL, then redirect.
  const handlePay = useCallback(async () => {
    if (!token || view.kind !== 'ready') return;
    setPaying(true);
    try {
      const res = await axios.post(`${PUBLIC_BASE}/${encodeURIComponent(token)}/pay`);
      const result = res.data?.data as { checkout_available: boolean; checkout_url?: string; error?: string } | undefined;
      if (result?.checkout_available && result.checkout_url) {
        // Redirect the customer to the hosted card entry page.
        window.location.href = result.checkout_url;
      } else {
        // Checkout provider not configured for this tenant — show "call shop" message.
        setView({ kind: 'checkout_unavailable', link: view.link, reason: result?.error });
      }
    } catch (err) {
      const msg = axios.isAxiosError(err)
        ? err.response?.data?.message ?? 'Could not start checkout'
        : 'Could not start checkout';
      setView({ kind: 'checkout_unavailable', link: (view as any).link, reason: msg });
    } finally {
      setPaying(false);
    }
  }, [token, view]);

  useEffect(() => {
    loadLink();
  }, [loadLink]);

  return (
    <div className="min-h-screen bg-surface-50 px-4 py-12 text-surface-900 dark:bg-surface-950 dark:text-surface-100">
      <div className="mx-auto max-w-md space-y-6">
        <header className="text-center">
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-50">Payment Request</h1>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">Review your balance</p>
        </header>

        <div className="rounded-lg border border-surface-200 bg-white p-6 shadow-sm dark:border-surface-800 dark:bg-surface-900">
          {view.kind === 'loading' ? (
            <p className="text-center text-surface-500 dark:text-surface-400">Loading…</p>
          ) : null}

          {view.kind === 'error' ? (
            <div className="space-y-3 text-center">
              <p className="font-medium text-error-600 dark:text-error-400">{view.message}</p>
              <p className="text-sm text-surface-600 dark:text-surface-300">Please call the shop to complete payment.</p>
              <button
                onClick={loadLink}
                className="rounded-md border border-surface-300 bg-white px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
              >
                Try again
              </button>
            </div>
          ) : null}

          {view.kind === 'expired' ? (
            <div className="space-y-3 text-center">
              <p className="font-medium text-warning-700 dark:text-warning-300">This link is no longer valid.</p>
              <p className="text-sm text-surface-600 dark:text-surface-300">
                Please contact the shop for an updated payment link.
              </p>
            </div>
          ) : null}

          {view.kind === 'paid' ? (
            <div className="space-y-3 text-center">
              <div className="text-4xl text-success-600 dark:text-success-400">✓</div>
              <p className="text-lg font-semibold text-success-700 dark:text-success-300">Already paid</p>
              <p className="text-sm text-surface-600 dark:text-surface-300">
                This invoice has already been paid in full. Thank you!
              </p>
            </div>
          ) : null}

          {(view.kind === 'ready' || view.kind === 'checkout_unavailable') ? (
            <div className="space-y-4">
              <div className="text-center">
                <p className="text-sm text-surface-500 dark:text-surface-400">Amount due</p>
                <p className="text-4xl font-bold text-surface-900 dark:text-surface-50">
                  {formatCents(view.link.amount_cents)}
                </p>
                {view.link.invoice_order_id ? (
                  <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
                    Invoice {view.link.invoice_order_id}
                  </p>
                ) : null}
                {view.link.description ? (
                  <p className="mt-2 text-sm text-surface-600 dark:text-surface-300">{view.link.description}</p>
                ) : null}
              </div>

              {view.kind === 'ready' ? (
                /* "Pay now" triggers hosted checkout */
                <button
                  onClick={handlePay}
                  disabled={paying}
                  className="flex w-full items-center justify-center gap-2 rounded-md bg-primary-600 px-4 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:focus-visible:ring-offset-surface-900"
                >
                  {paying ? (
                    <><Loader2 className="h-4 w-4 animate-spin" />Preparing checkout…</>
                  ) : (
                    'Pay now'
                  )}
                </button>
              ) : (
                /* Checkout unavailable for this tenant */
                <div className="rounded-md border border-warning-200 bg-warning-50 px-4 py-3 text-sm text-warning-900 dark:border-warning-900 dark:bg-warning-950/40 dark:text-warning-200">
                  {view.reason
                    ? view.reason
                    : 'Online card checkout is not available for this payment. Please call the shop to complete payment.'}
                </div>
              )}
            </div>
          ) : null}
        </div>

        <p className="text-center text-xs text-surface-400 dark:text-surface-500">
          Having trouble? Call the shop and reference this page.
        </p>
      </div>
    </div>
  );
}

export default CustomerPayPage;
