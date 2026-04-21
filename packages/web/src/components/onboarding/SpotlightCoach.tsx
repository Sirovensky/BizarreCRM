/**
 * SpotlightCoach — DOM-anchored tutorial overlay that replaces TutorialCoach.
 *
 * Reads `?tutorial=<flowId>&step=<key>` from the URL. For each step it:
 *  - Finds `[data-tutorial-target="<flowId>:<key>"]` in the DOM
 *  - Renders a semi-transparent backdrop with a transparent cutout over the target
 *  - Shows a tooltip card positioned below (or above if space is limited)
 *  - Advances automatically when the declared event fires on the target
 *
 * Falls back to a compact floating card if the target element is missing.
 *
 * Skip hierarchy:
 *  - "Skip step"    — advances to next step without firing the real action
 *  - "Skip tutorial"  — dismisses this flow (localStorage flag)
 *  - "Skip all tutorials" — sets `tutorial.all.dismissed=1`, patches onboarding
 *                           state, and navigates to `/`
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { X } from 'lucide-react';
import { cn } from '@/utils/cn';
import {
  SPOTLIGHT_FLOWS,
  dismissAllTutorials,
  handleTutorialComplete,
} from './tutorialFlows';
import type { SpotlightStep, TutorialFlowId } from './tutorialFlows';

// ─── Constants ────────────────────────────────────────────────────────────────

const ALL_DISMISSED_KEY = 'tutorial.all.dismissed';
const FLOW_DISMISSED_PREFIX = 'tutorial.';
const TARGET_FIND_TIMEOUT_MS = 300;

// ─── Helpers ─────────────────────────────────────────────────────────────────

function flowDismissedKey(flowId: string): string {
  return `${FLOW_DISMISSED_PREFIX}${flowId}.dismissed`;
}

function isAllDismissed(): boolean {
  try {
    return localStorage.getItem(ALL_DISMISSED_KEY) === '1';
  } catch {
    return false;
  }
}

function isFlowDismissed(flowId: string): boolean {
  try {
    return localStorage.getItem(flowDismissedKey(flowId)) === '1';
  } catch {
    return false;
  }
}

function setFlowDismissed(flowId: string): void {
  try {
    localStorage.setItem(flowDismissedKey(flowId), '1');
  } catch { /* ignore */ }
}

// ─── Types ────────────────────────────────────────────────────────────────────

interface TargetRect {
  top: number;
  left: number;
  width: number;
  height: number;
}

// ─── Spotlight overlay ────────────────────────────────────────────────────────

interface SpotlightOverlayProps {
  rect: TargetRect;
}

function SpotlightOverlay({ rect }: SpotlightOverlayProps) {
  const padding = 6;
  const borderRadius = 8;

  return (
    <div
      className="pointer-events-none fixed inset-0 z-[9998]"
      aria-hidden="true"
      style={{
        background: 'rgba(0,0,0,0.5)',
        // Cutout via clip-path polygon with a hole.
        // We paint 4 rectangles around the target using box-shadow instead,
        // because clip-path holes require complex polygon math.
        // Use the box-shadow trick: an inner element sized to the target
        // casts a shadow that covers the entire viewport.
      }}
    >
      {/* Invisible element positioned over the target — its shadow IS the overlay */}
      <div
        style={{
          position: 'absolute',
          top: rect.top - padding,
          left: rect.left - padding,
          width: rect.width + padding * 2,
          height: rect.height + padding * 2,
          borderRadius,
          boxShadow: '0 0 0 9999px rgba(0,0,0,0.5)',
          background: 'transparent',
        }}
      />
    </div>
  );
}

// ─── Tooltip card ─────────────────────────────────────────────────────────────

interface TooltipProps {
  step: SpotlightStep;
  stepIndex: number;
  totalSteps: number;
  targetRect: TargetRect | null;
  onSkipStep: () => void;
  onSkipFlow: () => void;
  onSkipAll: () => void;
  isFallback: boolean;
}

function TooltipCard({
  step,
  stepIndex,
  totalSteps,
  targetRect,
  onSkipStep,
  onSkipFlow,
  onSkipAll,
  isFallback,
}: TooltipProps) {
  const CARD_WIDTH = 320;
  const CARD_EST_HEIGHT = 240;
  const PADDING = 12;

  let style: React.CSSProperties;

  if (isFallback || !targetRect) {
    // Floating fallback — bottom right
    style = { position: 'fixed', bottom: 24, right: 24, width: CARD_WIDTH };
  } else {
    // Prefer below the target; flip above if too close to bottom
    const viewportHeight = window.innerHeight;
    const viewportWidth = window.innerWidth;
    const spaceBelow = viewportHeight - (targetRect.top + targetRect.height);
    const showBelow = spaceBelow >= CARD_EST_HEIGHT + PADDING;

    const top = showBelow
      ? targetRect.top + targetRect.height + PADDING
      : targetRect.top - CARD_EST_HEIGHT - PADDING;

    // Align left edge with target, but clamp to viewport
    const idealLeft = targetRect.left;
    const left = Math.min(
      Math.max(PADDING, idealLeft),
      viewportWidth - CARD_WIDTH - PADDING,
    );

    style = { position: 'fixed', top, left, width: CARD_WIDTH };
  }

  return (
    <div
      className="z-[9999] rounded-2xl border border-primary-200 bg-white shadow-2xl dark:border-primary-500/40 dark:bg-surface-900"
      style={style}
      role="dialog"
      aria-live="polite"
      aria-label={`Tutorial: ${step.title}`}
      data-testid={`spotlight-coach-card`}
    >
      {/* Header */}
      <div className="flex items-start justify-between gap-2 border-b border-surface-100 p-4 dark:border-surface-800">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-wide text-primary-600 dark:text-primary-400">
            Step {stepIndex + 1} of {totalSteps}
            {isFallback && (
              <span className="ml-2 rounded bg-surface-100 dark:bg-surface-800 px-1.5 py-0.5 text-[10px] font-normal normal-case text-surface-500 dark:text-surface-400">
                hint
              </span>
            )}
          </p>
          <h3 className="mt-1 text-sm font-semibold text-surface-900 dark:text-surface-100">
            {step.title}
          </h3>
        </div>
        <button
          type="button"
          onClick={onSkipFlow}
          className="rounded-md p-1 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          title="Skip tutorial"
          aria-label="Skip tutorial"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Body */}
      <div className="p-4 text-sm text-surface-600 dark:text-surface-300">
        <p>{step.body}</p>
        {step.hint && (
          <p className="mt-2 rounded-md bg-primary-50 px-3 py-2 text-xs text-primary-700 dark:bg-primary-500/10 dark:text-primary-300">
            {step.hint}
          </p>
        )}
      </div>

      {/* Progress + actions */}
      <div className="flex items-center justify-between gap-2 border-t border-surface-100 px-4 py-3 dark:border-surface-800">
        {/* Dots */}
        <div className="flex gap-1" aria-hidden="true">
          {Array.from({ length: totalSteps }, (_, i) => (
            <span
              key={i}
              className={cn(
                'h-1.5 w-5 rounded-full transition-colors',
                i < stepIndex
                  ? 'bg-primary-500'
                  : i === stepIndex
                    ? 'bg-primary-400'
                    : 'bg-surface-200 dark:bg-surface-700',
              )}
            />
          ))}
        </div>

        {/* Buttons — tab order: skip-step → skip-tutorial → skip-all */}
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={onSkipStep}
            tabIndex={0}
            className="rounded-md px-2 py-1 text-xs font-medium text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          >
            Skip step
          </button>
          <button
            type="button"
            onClick={onSkipFlow}
            tabIndex={0}
            className="rounded-md px-2 py-1 text-xs font-medium text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          >
            Skip tutorial
          </button>
          <button
            type="button"
            onClick={onSkipAll}
            tabIndex={0}
            className="rounded-md bg-surface-100 px-2 py-1 text-xs font-semibold text-surface-600 transition-colors hover:bg-red-50 hover:text-red-600 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-red-900/20 dark:hover:text-red-400"
          >
            Skip all tutorials
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Main component ───────────────────────────────────────────────────────────

export function SpotlightCoach() {
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();

  const flowId = searchParams.get('tutorial') as TutorialFlowId | null;
  const stepKey = searchParams.get('step');

  // ── Guard: dismissed flags ──────────────────────────────────────────────────
  const [dismissed, setDismissed] = useState<boolean>(() => {
    if (!flowId) return false;
    return isAllDismissed() || isFlowDismissed(flowId);
  });

  // Re-check when flowId changes (e.g. navigating from one flow to another)
  useEffect(() => {
    if (!flowId) return;
    setDismissed(isAllDismissed() || isFlowDismissed(flowId));
  }, [flowId]);

  // ── Resolve flow + step ─────────────────────────────────────────────────────
  const flow = flowId ? SPOTLIGHT_FLOWS[flowId] : null;
  const steps = flow?.steps ?? [];
  const stepIndex = steps.findIndex((s) => s.key === stepKey);
  const step: SpotlightStep | undefined = stepIndex >= 0 ? steps[stepIndex] : steps[0];

  // ── Target element tracking ─────────────────────────────────────────────────
  const [targetRect, setTargetRect] = useState<TargetRect | null>(null);
  const [isFallback, setIsFallback] = useState(false);
  const observerRef = useRef<ResizeObserver | null>(null);
  const targetElRef = useRef<Element | null>(null);

  const updateRect = useCallback(() => {
    const el = targetElRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    setTargetRect({ top: r.top, left: r.left, width: r.width, height: r.height });
  }, []);

  useEffect(() => {
    // Cleanup previous observer
    observerRef.current?.disconnect();
    targetElRef.current = null;
    setTargetRect(null);
    setIsFallback(false);

    if (!step || !flowId || dismissed) return;

    // If the step requests float-only mode, skip DOM lookup entirely.
    if (step.floatOnly) {
      setIsFallback(true);
      return;
    }

    const selector = `[data-tutorial-target="${step.target}"]`;

    // Immediate attempt
    const el = document.querySelector(selector);
    if (el) {
      targetElRef.current = el;
      updateRect();
      const ro = new ResizeObserver(updateRect);
      ro.observe(el);
      observerRef.current = ro;
      return;
    }

    // Retry after TARGET_FIND_TIMEOUT_MS
    const timer = setTimeout(() => {
      const retried = document.querySelector(selector);
      if (retried) {
        targetElRef.current = retried;
        updateRect();
        const ro = new ResizeObserver(updateRect);
        ro.observe(retried);
        observerRef.current = ro;
      } else {
        // Element not found — switch to floating fallback
        setIsFallback(true);
      }
    }, TARGET_FIND_TIMEOUT_MS);

    return () => {
      clearTimeout(timer);
      observerRef.current?.disconnect();
    };
  }, [step, flowId, dismissed, updateRect]);

  // ── Reposition on scroll/resize ─────────────────────────────────────────────
  // Depend on `targetRect` (not just `targetElRef.current`) so this re-runs
  // when the target transitions from null to non-null after the 300ms retry.
  useEffect(() => {
    if (dismissed || !targetElRef.current) return;
    window.addEventListener('scroll', updateRect, { passive: true });
    window.addEventListener('resize', updateRect, { passive: true });
    return () => {
      window.removeEventListener('scroll', updateRect);
      window.removeEventListener('resize', updateRect);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dismissed, updateRect, targetRect]);

  // ── Action gating ────────────────────────────────────────────────────────────
  const advance = useCallback(() => {
    if (!flowId || !step) return;
    const nextIndex = stepIndex + 1;
    if (nextIndex >= steps.length) {
      // Last step — flow complete
      Promise.resolve(handleTutorialComplete(flowId as TutorialFlowId, 'done', navigate))
        .catch((err) => { console.error('[SpotlightCoach] handleTutorialComplete failed:', err); });
      return;
    }
    const nextStep = steps[nextIndex];
    const next = new URLSearchParams(searchParams);
    next.set('step', nextStep.key);
    setSearchParams(next, { replace: true });
  }, [flowId, step, stepIndex, steps, navigate, searchParams, setSearchParams]);

  useEffect(() => {
    if (!step || dismissed) return;
    const el = targetElRef.current;

    if (step.advanceOn === 'custom-event' && step.customEventName) {
      const name = step.customEventName;
      const handler = () => advance();
      window.addEventListener(name, handler);
      return () => window.removeEventListener(name, handler);
    }

    if (!el) return;

    const eventName = step.advanceOn; // 'click' | 'change' | 'blur'
    const handler = () => advance();
    el.addEventListener(eventName, handler);
    return () => el.removeEventListener(eventName, handler);
  }, [step, dismissed, advance]);

  // ── Action handlers ──────────────────────────────────────────────────────────
  const handleSkipStep = useCallback(() => {
    advance();
  }, [advance]);

  const handleSkipFlow = useCallback(() => {
    if (!flowId) return;
    setFlowDismissed(flowId);
    setDismissed(true);
    Promise.resolve(handleTutorialComplete(flowId as TutorialFlowId, 'skip', navigate))
      .catch((err) => { console.error('[SpotlightCoach] handleTutorialComplete failed:', err); });
  }, [flowId, navigate]);

  const handleSkipAll = useCallback(() => {
    setDismissed(true);
    Promise.resolve(dismissAllTutorials(navigate))
      .catch((err) => { console.error('[SpotlightCoach] dismissAllTutorials failed:', err); });
  }, [navigate]);

  // ── Keyboard: Escape = skip flow ─────────────────────────────────────────────
  useEffect(() => {
    if (!flow || dismissed) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleSkipFlow();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [flow, dismissed, handleSkipFlow]);

  // ── Guard: render nothing ─────────────────────────────────────────────────────
  if (!flow || !step || dismissed) return null;
  if (isAllDismissed()) return null; // double-check after render

  const effectiveRect = targetRect;
  const showOverlay = !isFallback && effectiveRect !== null;

  return (
    <>
      {showOverlay && effectiveRect && (
        <SpotlightOverlay rect={effectiveRect} />
      )}
      <TooltipCard
        step={step}
        stepIndex={stepIndex >= 0 ? stepIndex : 0}
        totalSteps={steps.length}
        targetRect={effectiveRect}
        onSkipStep={handleSkipStep}
        onSkipFlow={handleSkipFlow}
        onSkipAll={handleSkipAll}
        isFallback={isFallback}
      />
    </>
  );
}
