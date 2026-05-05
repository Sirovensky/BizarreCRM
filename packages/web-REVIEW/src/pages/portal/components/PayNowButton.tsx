/**
 * PayNowButton - sends the customer to the payment request page.
 *
 * This creates or reuses a tokenized request link for the ticket invoice. The
 * public payment page currently fails closed until hosted checkout is wired.
 *
 * Amount is passed through so the button also doubles as a status card
 * ("$0 — paid in full") when the ticket has nothing owed.
 */
import React, { useState } from 'react';
import { usePortalI18n } from '../i18n';
import { createTicketPayLink } from '../portalApi';

interface PayNowButtonProps {
  ticketId: number;
  amountDue: number;
}

export function PayNowButton({
  ticketId,
  amountDue,
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

  // WEB-S4-025: BlockChyp Hosted Checkout URLs are external by design — allow
  // them alongside our own origin. Anchored to *.blockchyp.com so subdomains
  // (checkout.blockchyp.com, etc.) are accepted without wildcarding all hosts.
  function isAllowedPaymentUrl(parsed: URL): boolean {
    if (parsed.origin === window.location.origin) return true;
    if (/^https:\/\/([a-z0-9-]+\.)*blockchyp\.com$/i.test(parsed.origin)) return true;
    return false;
  }

  const handlePay = async (): Promise<void> => {
    setLoading(true);
    setError(null);
    try {
      const { url } = await createTicketPayLink(ticketId);
      if (typeof url === 'string' && url.length > 0) {
        let parsed: URL;
        try {
          parsed = new URL(url, window.location.origin);
        } catch {
          setError('Payment request not available. Please call the shop.');
          return;
        }
        if (!isAllowedPaymentUrl(parsed)) {
          setError('Payment request not available. Please call the shop.');
          return;
        }
        window.location.href = parsed.href;
        return;
      }
      setError('Payment request not available. Please call the shop.');
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } }).response?.status;
      if (status === 404) {
        setError('No invoice is available to pay. Please call the shop.');
      } else if (status === 403) {
        setError('Your session expired. Please sign in again.');
      } else {
        setError('Could not open the payment request. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <section
      aria-label={t('pay.title')}
      className="rounded-lg bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-4"
    >
      <div className="text-sm text-surface-700 dark:text-surface-200 mb-2">
        {t('pay.amount_due', { amount: amountDue.toFixed(2) })}
      </div>
      <button
        type="button"
        onClick={handlePay}
        disabled={loading}
        className="w-full rounded-md bg-primary-600 hover:bg-primary-700 text-primary-950 font-medium py-2.5 text-sm disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
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
