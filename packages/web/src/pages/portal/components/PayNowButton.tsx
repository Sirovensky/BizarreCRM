/**
 * PayNowButton — "Pay securely" button that sends the customer to
 * Stripe-hosted checkout.
 *
 * If the billing-enhancement agent has exposed a payment-link generator,
 * this button POSTs to `/api/v1/portal/tickets/:id/pay-link` and redirects
 * the browser to the returned URL. Otherwise it falls back to a disabled
 * state with a "Call the shop" prompt. Apple Pay / Google Pay is handled
 * by Stripe's hosted checkout — no extra client work needed.
 *
 * Amount is passed through so the button also doubles as a status card
 * ("$0 — paid in full") when the ticket has nothing owed.
 */
import React, { useState } from 'react';
import axios from 'axios';
import { usePortalI18n } from '../i18n';

interface PayNowButtonProps {
  ticketId: number;
  amountDue: number;
  onPaid?: () => void;
}

export function PayNowButton({
  ticketId,
  amountDue,
  onPaid,
}: PayNowButtonProps): React.ReactElement {
  const { t } = usePortalI18n();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (amountDue <= 0) {
    return (
      <div className="rounded-lg bg-green-50 dark:bg-green-900/30 border border-green-200 dark:border-green-800 p-3 text-center">
        <div className="text-sm font-medium text-green-800 dark:text-green-200">
          {t('pay.paid')}
        </div>
      </div>
    );
  }

  const handlePay = async (): Promise<void> => {
    setLoading(true);
    setError(null);
    try {
      const token = sessionStorage.getItem('portal_token');
      const headers: Record<string, string> = {};
      if (token) headers.Authorization = `Bearer ${token}`;
      const res = await axios.post(
        `/api/v1/portal/tickets/${ticketId}/pay-link`,
        {},
        { headers },
      );
      const url = res?.data?.data?.url;
      if (typeof url === 'string' && url.length > 0) {
        if (onPaid) onPaid();
        window.location.href = url;
        return;
      }
      setError('Online payment not available. Please call the shop.');
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } }).response?.status;
      if (status === 404) {
        setError('Online payment not set up. Please call the shop.');
      } else {
        setError('Could not start payment. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <section
      aria-label={t('pay.title')}
      className="rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4"
    >
      <div className="text-sm text-gray-700 dark:text-gray-200 mb-2">
        {t('pay.amount_due', { amount: amountDue.toFixed(2) })}
      </div>
      <button
        type="button"
        onClick={handlePay}
        disabled={loading}
        className="w-full rounded-md bg-blue-600 hover:bg-blue-700 text-white font-medium py-2.5 text-sm disabled:opacity-60 focus:outline-none focus:ring-2 focus:ring-blue-400"
      >
        {loading ? '...' : t('pay.button')}
      </button>
      {error ? (
        <div role="alert" className="mt-2 text-xs text-red-600 dark:text-red-400">
          {error}
        </div>
      ) : null}
    </section>
  );
}
