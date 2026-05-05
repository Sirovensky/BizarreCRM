/**
 * FinancingButton — stub for Affirm / Klarna pay-over-time. §52 idea 15.
 *
 * Only renders when:
 *   (a) `billing_financing_enabled` store config is '1'
 *   (b) the order total >= `billing_financing_min_cents` (default $500)
 *
 * Real integration requires live API keys per provider, which aren't in
 * env yet. This button opens the stub dialog the shop can show a
 * customer so they understand the option exists without us shipping
 * broken production flows.
 *
 * TODO(LOW, §26, §52 follow-up): replace the click handler with a real
 * hosted redirect once API keys are provisioned in settings → payments.
 * SEVERITY=LOW: component is marketing-only today, behind a feature flag,
 * and the "coming soon" message is shown to the user directly.
 */
import { useEffect, useState } from 'react';
import { formatCents } from '@/utils/format';
import { ComingSoonBadge } from '@/pages/settings/components/ComingSoonBadge';

interface FinancingButtonProps {
  amountCents: number;
  minCents?: number;
  enabled?: boolean;
  providerKey?: string;
  provider?: 'affirm' | 'klarna';
  onFlowStart?: () => void;
}

export function FinancingButton({
  amountCents,
  minCents = 50_000,
  enabled = true,
  providerKey,
  provider = 'affirm',
  onFlowStart,
}: FinancingButtonProps) {
  const [showModal, setShowModal] = useState(false);

  // Hide entirely when the provider API key is missing, even if the toggle is on.
  const hasProviderKey = typeof providerKey === 'string' && providerKey.trim().length > 0;
  if (!hasProviderKey) {
    if (import.meta.env.DEV && enabled) {
      // eslint-disable-next-line no-console
      console.warn('[FinancingButton] billing_financing_provider_key is empty — button hidden');
    }
    return null;
  }

  if (!enabled || !Number.isFinite(amountCents) || amountCents < minCents) return null;

  const providerLabel = provider === 'affirm' ? 'Affirm' : 'Klarna';
  const formatted = formatCents(amountCents);

  const handleClick = () => {
    onFlowStart?.();
    setShowModal(true);
  };

  // WEB-FX-003: Esc-to-close for a11y dialog parity.
  useEffect(() => {
    if (!showModal) return;
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') setShowModal(false); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [showModal]);

  return (
    <>
      <button
        type="button"
        onClick={handleClick}
        className="inline-flex items-center gap-2 rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 shadow-sm hover:bg-primary-700"
      >
        Pay over time with {providerLabel}
        <ComingSoonBadge status="coming_soon" compact />
      </button>

      {showModal ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => setShowModal(false)}>
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="financing-stub-title"
            className="max-w-md rounded-lg bg-white p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 id="financing-stub-title" className="mb-2 text-lg font-semibold">
              {providerLabel} financing (stub)
            </h3>
            <p className="mb-4 text-sm text-gray-600">
              Customer would be redirected to {providerLabel}'s hosted flow to finance
              <strong> {formatted}</strong>. Live API keys need to be configured in
              Settings &rarr; Payments before this works end-to-end.
            </p>
            <div className="flex justify-end gap-2">
              <button
                type="button"
                className="rounded-md border border-gray-300 px-4 py-2 text-sm hover:bg-gray-50"
                onClick={() => setShowModal(false)}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
