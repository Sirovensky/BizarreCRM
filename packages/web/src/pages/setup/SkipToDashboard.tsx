import { useState } from 'react';
import { ArrowRight } from 'lucide-react';

/**
 * "Skip for now" button available at every wizard phase. Shows a confirm dialog
 * before calling onSkip so users don't accidentally abandon setup with a stray
 * click. The parent is responsible for actually flushing any pending writes and
 * setting wizard_completed='skipped' before navigating away — this component
 * just asks for confirmation and calls back.
 */
interface SkipToDashboardProps {
  onSkip: () => void;
  disabled?: boolean;
  /** Label override. Defaults to "Skip for now". Use "Skip setup and go to dashboard" on the first screen. */
  label?: string;
}

export function SkipToDashboard({ onSkip, disabled, label = 'Skip for now' }: SkipToDashboardProps) {
  const [confirming, setConfirming] = useState(false);

  if (confirming) {
    return (
      <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-500/30 dark:bg-amber-500/5">
        <p className="text-sm text-amber-900 dark:text-amber-200">
          Are you sure? You can always finish setup later from <strong>Settings &rarr; Store</strong>, but
          some features won't work their best until you do (SMS notifications, tax calculations, receipts).
        </p>
        <div className="mt-3 flex gap-2">
          <button
            type="button"
            onClick={onSkip}
            disabled={disabled}
            className="rounded-lg bg-amber-600 px-4 py-2 text-xs font-semibold text-white hover:bg-amber-700 disabled:opacity-50"
          >
            Yes, skip to dashboard
          </button>
          <button
            type="button"
            onClick={() => setConfirming(false)}
            className="rounded-lg border border-surface-300 px-4 py-2 text-xs font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            Keep setting up
          </button>
        </div>
      </div>
    );
  }

  return (
    <button
      type="button"
      onClick={() => setConfirming(true)}
      disabled={disabled}
      className="flex items-center gap-1 text-xs font-medium text-surface-500 hover:text-surface-900 disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-100"
    >
      {label}
      <ArrowRight className="h-3 w-3" />
    </button>
  );
}
