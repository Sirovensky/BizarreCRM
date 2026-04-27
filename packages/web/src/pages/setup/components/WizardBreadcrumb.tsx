import { ChevronLeft, ChevronRight } from 'lucide-react';
import type { JSX } from 'react';

export interface WizardBreadcrumbProps {
  /** Label of the previous step, e.g. "Step 5 · Shop type". Undefined on the first step. */
  prevLabel?: string;
  /** Label of the current step, e.g. "Step 6 · Store info". */
  currentLabel: string;
  /** Label of the next step, e.g. "Step 7 · Import". Undefined on the last step. */
  nextLabel?: string;
}

/**
 * WizardBreadcrumb — pill-style breadcrumb for the setup wizard.
 *
 * Pure presentational component. Renders a centered, rounded-full pill
 * with the current step bolded in cream (`bg-primary-500`) and the
 * adjacent steps shown muted to either side. On viewports < 640px the
 * side pills hide and only the current step is shown.
 *
 * Mirrors the `.bc` / `.bc-prev` / `.bc-current` / `.bc-next` / `.bc-sep`
 * classes from `docs/setup-wizard-preview.html`.
 */
export function WizardBreadcrumb({
  prevLabel,
  currentLabel,
  nextLabel,
}: WizardBreadcrumbProps): JSX.Element {
  return (
    <div className="inline-flex flex-wrap items-center justify-center gap-3 rounded-full border border-surface-200 bg-white px-[18px] py-[10px] text-[13px] shadow-[0_2px_8px_-4px_rgba(0,0,0,0.08)] dark:border-surface-700 dark:bg-surface-800">
      {prevLabel ? (
        <>
          <span className="hidden items-center gap-1 font-medium text-surface-500 sm:inline-flex dark:text-surface-400">
            <ChevronLeft className="h-3 w-3" aria-hidden="true" />
            {prevLabel}
          </span>
          <span
            className="hidden text-surface-300 sm:inline dark:text-surface-600"
            aria-hidden="true"
          >
            ·
          </span>
        </>
      ) : null}

      <span className="inline-flex items-center gap-1.5 rounded-full bg-primary-500 px-3.5 py-1 text-[14px] font-bold text-primary-950">
        {currentLabel}
      </span>

      {nextLabel ? (
        <>
          <span
            className="hidden text-surface-300 sm:inline dark:text-surface-600"
            aria-hidden="true"
          >
            ·
          </span>
          <span className="hidden items-center gap-1 font-medium text-surface-500 sm:inline-flex dark:text-surface-400">
            {nextLabel}
            <ChevronRight className="h-3 w-3" aria-hidden="true" />
          </span>
        </>
      ) : null}
    </div>
  );
}

export default WizardBreadcrumb;
