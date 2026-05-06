/**
 * useMilestoneToasts — Phase E1
 *
 * Fires a toast (and confetti for the payment milestone) the first time a
 * milestone transitions from null to non-null between renders.
 *
 * Deduplication strategy (WEB-UIUX-576):
 *   - Both this hook and SuccessCelebration now use localStorage (not
 *     sessionStorage) so the fired-flag is shared across browser tabs.
 *   - Before firing, we also check SuccessCelebration's own localStorage key
 *     (`onboarding_celebrated_v1`). If it already recorded the milestone, we
 *     skip the toast+confetti entirely to avoid a duplicate celebration.
 *   - SuccessCelebration writes its key before this hook's effect runs (it
 *     mounts earlier in the tree), so the check is reliable within the same tab.
 */
import { useEffect, useRef } from 'react';
import toast from 'react-hot-toast';
import type { OnboardingState } from '@/api/endpoints';

const SESSION_KEY = 'milestone_toasts_v1';
// Key written by SuccessCelebration — used to check if it already fired for a milestone.
const CELEBRATION_KEY = 'onboarding_celebrated_v1';

interface ToastSnapshot {
  first_ticket_at_toasted: boolean;
  first_payment_at_toasted: boolean;
}

function readToastSnapshot(): ToastSnapshot {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return { first_ticket_at_toasted: false, first_payment_at_toasted: false };
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') {
      return { first_ticket_at_toasted: false, first_payment_at_toasted: false };
    }
    return parsed as ToastSnapshot;
  } catch {
    return { first_ticket_at_toasted: false, first_payment_at_toasted: false };
  }
}

function writeToastSnapshot(snap: ToastSnapshot): void {
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify(snap));
  } catch {
    // Storage quota or disabled — degrade silently.
  }
}

/**
 * Returns true if SuccessCelebration has already recorded this milestone key.
 * Prevents useMilestoneToasts from firing a duplicate toast+confetti.
 */
function celebrationAlreadyFired(key: string): boolean {
  try {
    const raw = localStorage.getItem(CELEBRATION_KEY);
    if (!raw) return false;
    const parsed = JSON.parse(raw);
    return !!(parsed && typeof parsed === 'object' && parsed[key]);
  } catch {
    return false;
  }
}

/**
 * Inject confetti via the same DOM-injection pattern used in SuccessCelebration.
 * Kept inline so this hook has no import-time side-effects.
 */
function fireConfetti(): void {
  if (typeof window === 'undefined') return;
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;

  const host = document.createElement('div');
  host.setAttribute('aria-hidden', 'true');
  host.style.cssText =
    'position:fixed;inset:0;pointer-events:none;overflow:hidden;z-index:9999';
  const colors = ['#f43f5e', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6'];
  for (let i = 0; i < 40; i++) {
    const piece = document.createElement('div');
    const left = Math.random() * 100;
    const delay = Math.random() * 0.5;
    const dur = 2.5 + Math.random() * 1.5;
    const rot = Math.random() * 360;
    const bg = colors[Math.floor(Math.random() * colors.length)];
    piece.style.cssText =
      `position:absolute;top:-10px;left:${left}%;width:8px;height:12px;background:${bg};` +
      `transform:rotate(${rot}deg);border-radius:2px;` +
      `animation:onboarding-confetti-fall ${dur}s linear ${delay}s forwards`;
    host.appendChild(piece);
  }
  // WEB-FD-015: keyframes live in globals.css; no per-burst <style> injection.
  document.body.appendChild(host);
  window.setTimeout(() => host.remove(), 4000);
}

export function useMilestoneToasts(state: OnboardingState | null): void {
  const prevStateRef = useRef<OnboardingState | null>(null);
  const initializedRef = useRef(false);

  useEffect(() => {
    if (!state) return;

    const snap = readToastSnapshot();

    // On first render, seed the snapshot so we don't fire for already-set
    // milestones the user has had for days.
    if (!initializedRef.current) {
      initializedRef.current = true;
      const next = { ...snap };
      if (state.first_ticket_at) next.first_ticket_at_toasted = true;
      if (state.first_payment_at) next.first_payment_at_toasted = true;
      writeToastSnapshot(next);
      prevStateRef.current = state;
      return;
    }

    const prev = prevStateRef.current;
    prevStateRef.current = state;

    // NOTE: read-modify-write on localStorage has a theoretical cross-tab race (two tabs may both read before either writes),
    // but the celebrationAlreadyFired() check provides a second dedup layer that catches most practical cases.
    const next = { ...snap };
    let changed = false;

    // first_ticket_at: null → non-null
    // Skip if SuccessCelebration already fired for this milestone (shared localStorage).
    if (
      !prev?.first_ticket_at &&
      state.first_ticket_at &&
      !snap.first_ticket_at_toasted &&
      !celebrationAlreadyFired('first_ticket_at')
    ) {
      toast.success('First ticket saved — nice');
      next.first_ticket_at_toasted = true;
      changed = true;
    }

    // first_payment_at: null → non-null
    // Skip if SuccessCelebration already fired for this milestone (shared localStorage).
    if (
      !prev?.first_payment_at &&
      state.first_payment_at &&
      !snap.first_payment_at_toasted &&
      !celebrationAlreadyFired('first_payment_at')
    ) {
      toast.success('First payment received');
      fireConfetti();
      next.first_payment_at_toasted = true;
      changed = true;
    }

    if (changed) writeToastSnapshot(next);
  }, [state]);
}
