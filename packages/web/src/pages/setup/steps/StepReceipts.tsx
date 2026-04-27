import type { JSX } from 'react';
import { ArrowLeft, ArrowRight } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { WizardBreadcrumb } from '../components/WizardBreadcrumb';

/**
 * Step 12 — Receipt Layout (linear flow rewrite).
 *
 * Mirrors `#screen-12` in `docs/setup-wizard-preview.html`. The owner sets the
 * header, footer, and an optional title that appear on every thermal/A4
 * receipt. A live preview pane on the right (md+) shows the result so the
 * shape of the printed slip is obvious before they continue.
 *
 * Persists `receipt_title`, `receipt_header`, and `receipt_footer` directly
 * onto the wizard's pending bundle via `onUpdate` — the bulk PUT at the end
 * of the wizard flushes them to `store_config`. Skip is allowed; receipts
 * just print with no header/footer/title until the owner edits them in
 * Settings → Receipts.
 */
export function StepReceipts({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const header = pending.receipt_header ?? '';
  const footer = pending.receipt_footer ?? '';
  const title = pending.receipt_title ?? '';

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
        <WizardBreadcrumb
          prevLabel="Step 11 · Tax"
          currentLabel="Step 12 · Receipts"
          nextLabel="Step 13 · Logo"
        />
      </div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Receipt header & footer
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Optional. Live preview on the right — change anytime in Settings.
        </p>
      </div>

      <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
          {/* Edit column */}
          <div className="space-y-4">
            <div>
              <label
                htmlFor="receipt-title"
                className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
              >
                Receipt title (optional)
              </label>
              <input
                id="receipt-title"
                type="text"
                value={title}
                onChange={(e) => onUpdate({ receipt_title: e.target.value })}
                placeholder="Joe's Phone Repair"
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>

            <div>
              <label
                htmlFor="receipt-header"
                className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
              >
                Header text
              </label>
              <textarea
                id="receipt-header"
                value={header}
                onChange={(e) => onUpdate({ receipt_header: e.target.value })}
                placeholder={'Thank you!\nBring this for warranty service.'}
                rows={4}
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>

            <div>
              <label
                htmlFor="receipt-footer"
                className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
              >
                Footer text
              </label>
              <textarea
                id="receipt-footer"
                value={footer}
                onChange={(e) => onUpdate({ receipt_footer: e.target.value })}
                placeholder={'90-day warranty.\nCall (555) 234-1090.'}
                rows={4}
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>
          </div>

          {/* Preview column */}
          <div className="rounded-2xl border border-surface-200 bg-surface-50 p-5 shadow-inner dark:border-surface-700 dark:bg-surface-900/50">
            <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-surface-500">
              Live preview
            </p>
            <div className="rounded-lg border-2 border-dashed border-surface-300 bg-white p-4 font-mono text-xs leading-relaxed text-surface-700 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100">
              {title ? (
                <p className="mb-2 text-center text-base font-bold uppercase">
                  {title}
                </p>
              ) : null}
              {header ? (
                <p className="mb-3 whitespace-pre-line text-center">{header}</p>
              ) : null}
              <hr className="my-2 border-surface-300 dark:border-surface-600" />
              <p>iPhone 12 Screen&nbsp;&nbsp;&nbsp;$189.00</p>
              <p>Tax (8.25%)&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$15.59</p>
              <p className="mt-1 font-bold">TOTAL&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$204.59</p>
              <hr className="my-2 border-surface-300 dark:border-surface-600" />
              {footer ? (
                <p className="mt-2 whitespace-pre-line text-center">{footer}</p>
              ) : null}
              {!title && !header && !footer ? (
                <p className="mt-2 text-center text-surface-400">
                  Fill in the form to preview.
                </p>
              ) : null}
            </div>
          </div>
        </div>

        <div className="flex items-center justify-between gap-3 pt-6">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip
            </button>
            <button
              type="button"
              onClick={onNext}
              className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
            >
              <ArrowRight className="h-4 w-4" />
              Continue
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepReceipts;
