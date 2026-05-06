import { useState } from 'react';
import { ArrowRight } from 'lucide-react';
import { useEscClose } from '@/hooks/useEscClose';
import { useFocusTrap } from '@/hooks/useFocusTrap';

/**
 * "Skip wizard" button available at every wizard phase. Shows a confirm dialog
 * before calling onSkip so users don't accidentally abandon setup with a stray
 * click. The parent is responsible for actually flushing any pending writes and
 * setting wizard_completed='skipped' before navigating away — this component
 * just asks for confirmation and calls back.
 */
interface SkipToDashboardProps {
  onSkip: () => void;
  disabled?: boolean;
  /** Label override. Defaults to "Skip wizard". */
  label?: string;
}

export function SkipToDashboard({ onSkip, disabled, label = 'Skip wizard' }: SkipToDashboardProps) {
  const [confirming, setConfirming] = useState(false);

  useEscClose(() => setConfirming(false), confirming);
  const dialogRef = useFocusTrap(confirming);

  if (confirming) {
    return (
      <div
        ref={dialogRef as React.RefObject<HTMLDivElement>}
        role="dialog"
        aria-modal="true"
        aria-labelledby="skip-dialog-title"
        className="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-500/30 dark:bg-amber-500/5"
      >
        <p id="skip-dialog-title" className="text-sm text-amber-900 dark:text-amber-200">
          Are you sure? You can always finish setup later from <strong>Settings &rarr; Store</strong>, but
          some features won't work their best until you do (SMS notifications, tax calculations, receipts).
        </p>
        <div className="mt-3 flex gap-2">
          <button
            type="button"
            onClick={onSkip}
            disabled={disabled}
            className="btn btn-md rounded-lg bg-amber-600 px-4 py-2 text-xs font-semibold text-white hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            Yes, skip to dashboard
          </button>
          <button
            type="button"
            onClick={() => setConfirming(false)}
            className="btn btn-md rounded-lg border border-surface-300 px-4 py-2 text-xs font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
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
      className="btn btn-xs flex items-center gap-1 text-xs font-medium text-surface-500 hover:text-surface-900 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:text-surface-400 dark:hover:text-surface-100"
    >
      {label}
      <ArrowRight className="h-3 w-3" />
    </button>
  );
}
