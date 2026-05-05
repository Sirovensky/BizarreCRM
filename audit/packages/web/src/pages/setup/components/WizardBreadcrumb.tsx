import { ChevronLeft, ChevronRight } from 'lucide-react';
import type { JSX } from 'react';
import { WIZARD_BODY_ORDER, WIZARD_PHASE_LABELS } from '../wizardTypes';
import type { WizardPhase } from '../wizardTypes';

export interface WizardBreadcrumbProps {
  /**
   * Phase-driven mode (preferred). Pass the current WizardPhase and the
   * component computes prev/current/next labels + step numbers from
   * WIZARD_BODY_ORDER. This keeps breadcrumb numbering consistent across
   * all 23 wizard body steps without hard-coding step numbers per file.
   */
  currentPhase?: WizardPhase;

  /**
   * @deprecated Manual override mode. Pass explicit labels — kept for
   *   backwards compatibility with the old call sites that used hard-coded
   *   "Step N · ..." strings. New code should use `currentPhase` instead.
   */
  prevLabel?: string;
  /** @deprecated — use `currentPhase`. */
  currentLabel?: string;
  /** @deprecated — use `currentPhase`. */
  nextLabel?: string;
}

function labelFor(phase: WizardPhase): string {
  const idx = WIZARD_BODY_ORDER.indexOf(phase);
  if (idx < 0) return WIZARD_PHASE_LABELS[phase];
  return `Step ${idx + 1} · ${WIZARD_PHASE_LABELS[phase]}`;
}

/**
 * WizardBreadcrumb — pill-style breadcrumb for the setup wizard.
 *
 * Phase-driven mode (preferred): pass `currentPhase`, the component reads
 * WIZARD_BODY_ORDER to compute prev/current/next labels with consistent
 * step numbering.
 *
 * Manual mode (legacy): pass explicit `prevLabel` / `currentLabel` /
 * `nextLabel` strings. Used by step files written before the phase-driven
 * API existed; all of them have been migrated.
 *
 * Renders a centered, rounded-full pill with the current step bolded in
 * cream (`bg-primary-500`) and adjacent steps shown muted. On viewports
 * < 640px the side pills hide and only the current step is shown.
 */
export function WizardBreadcrumb(props: WizardBreadcrumbProps): JSX.Element {
  let resolvedPrev: string | undefined;
  let resolvedCurrent: string;
  let resolvedNext: string | undefined;

  if (props.currentPhase) {
    const idx = WIZARD_BODY_ORDER.indexOf(props.currentPhase);
    resolvedCurrent = labelFor(props.currentPhase);
    resolvedPrev = idx > 0 ? labelFor(WIZARD_BODY_ORDER[idx - 1]) : undefined;
    resolvedNext =
      idx >= 0 && idx < WIZARD_BODY_ORDER.length - 1
        ? labelFor(WIZARD_BODY_ORDER[idx + 1])
        : undefined;
  } else {
    resolvedPrev = props.prevLabel;
    resolvedCurrent = props.currentLabel ?? '';
    resolvedNext = props.nextLabel;
  }

  return (
    <div className="inline-flex flex-wrap items-center justify-center gap-3 rounded-full border border-surface-200 bg-white px-[18px] py-[10px] text-[13px] shadow-[0_2px_8px_-4px_rgba(0,0,0,0.08)] dark:border-surface-700 dark:bg-surface-800">
      {resolvedPrev ? (
        <>
          <span className="hidden items-center gap-1 font-medium text-surface-500 sm:inline-flex dark:text-surface-400">
            <ChevronLeft className="h-3 w-3" aria-hidden="true" />
            {resolvedPrev}
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
        {resolvedCurrent}
      </span>

      {resolvedNext ? (
        <>
          <span
            className="hidden text-surface-300 sm:inline dark:text-surface-600"
            aria-hidden="true"
          >
            ·
          </span>
          <span className="hidden items-center gap-1 font-medium text-surface-500 sm:inline-flex dark:text-surface-400">
            {resolvedNext}
            <ChevronRight className="h-3 w-3" aria-hidden="true" />
          </span>
        </>
      ) : null}
    </div>
  );
}

export default WizardBreadcrumb;
