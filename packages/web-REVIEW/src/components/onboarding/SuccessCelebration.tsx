/**
 * SuccessCelebration — Day-1 Onboarding (audit section 42, idea 9)
 *
 * Fires a confetti burst + toast whenever a new milestone is reached:
 *   - first_ticket_at    -> "First ticket created!"
 *   - first_invoice_at   -> "First invoice sent!"
 *   - first_payment_at   -> "First payment collected!"
 *   - first_review_at    -> "First review collected!"
 *
 * How it knows what to celebrate:
 *   The component reads the current onboarding state and stores the
 *   last-seen milestone timestamps in sessionStorage under the key
 *   `onboarding_celebrated_v1`. On every render it diffs the current
 *   state against the stored set — any milestone that is present now
 *   but wasn't last time triggers a celebration. This means:
 *     - Refreshing the page after a celebration does NOT re-trigger it.
 *     - Logging out + back in on the same browser re-triggers it (harmless).
 *     - A different browser / device is its own celebration universe.
 *   sessionStorage (not localStorage) is deliberate — we want celebrations
 *   to fire once per session, not literally one time forever, so the shop
 *   owner sees them when they come back the next morning.
 *
 * Confetti implementation:
 *   Pure CSS + DOM injection so we don't pull in a ~40kb confetti library
 *   for a 3-second animation. The keyframes are scoped with an ID prefix
 *   so they don't collide with anything else on the page.
 */
import { useEffect, useRef } from 'react';
import toast from 'react-hot-toast';
import type { OnboardingState } from '@/api/endpoints';

type MilestoneKey =
  | 'first_ticket_at'
  | 'first_invoice_at'
  | 'first_payment_at'
  | 'first_review_at';

const MILESTONES: ReadonlyArray<{ key: MilestoneKey; message: string; emoji: string }> = [
  { key: 'first_ticket_at',  message: 'First ticket created!',  emoji: '🎫' },
  { key: 'first_invoice_at', message: 'First invoice generated!', emoji: '📄' },
  { key: 'first_payment_at', message: 'First payment collected!',  emoji: '💰' },
  { key: 'first_review_at',  message: 'First review collected!',   emoji: '⭐' },
];

const STORAGE_KEY = 'onboarding_celebrated_v1';

interface CelebratedSnapshot {
  first_ticket_at?: string | null;
  first_invoice_at?: string | null;
  first_payment_at?: string | null;
  first_review_at?: string | null;
}

function readSnapshot(): CelebratedSnapshot {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return {};
    return parsed as CelebratedSnapshot;
  } catch {
    return {};
  }
}

function writeSnapshot(snap: CelebratedSnapshot): void {
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(snap));
  } catch {
    // Quota exceeded or storage disabled — silently degrade.
  }
}

/**
 * Inject a short confetti burst into the DOM. Self-cleaning after 3.5s.
 * Disabled if prefers-reduced-motion is set.
 */
function fireConfetti(): void {
  if (typeof window === 'undefined') return;
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;

  const host = document.createElement('div');
  host.setAttribute('aria-hidden', 'true');
  host.style.cssText =
    'position:fixed;inset:0;pointer-events:none;overflow:hidden;z-index:9999';
  const colors = ['#f43f5e', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6'];
  for (let i = 0; i < 30; i++) {
    const piece = document.createElement('div');
    const left = Math.random() * 100;
    const delay = Math.random() * 0.3;
    const dur = 2 + Math.random() * 1.5;
    const rot = Math.random() * 360;
    const bg = colors[Math.floor(Math.random() * colors.length)];
    piece.style.cssText =
      `position:absolute;top:-10px;left:${left}%;width:8px;height:12px;background:${bg};` +
      `transform:rotate(${rot}deg);border-radius:2px;` +
      `animation:onboarding-confetti-fall ${dur}s linear ${delay}s forwards`;
    host.appendChild(piece);
  }

  // WEB-FD-015: keyframes live in globals.css under
  // `@keyframes onboarding-confetti-fall` and are reused by useMilestoneToasts +
  // GettingStartedWidget so concurrent milestones never stack <style> nodes.
  document.body.appendChild(host);
  window.setTimeout(() => {
    host.remove();
  }, 3500);
}

interface SuccessCelebrationProps {
  state: OnboardingState | null;
}

export function SuccessCelebration({ state }: SuccessCelebrationProps) {
  const initializedRef = useRef(false);

  useEffect(() => {
    if (!state) return;
    const snapshot = readSnapshot();

    // First render: seed the snapshot with whatever is already done. This
    // prevents a confetti avalanche for a user who logs in after the
    // feature ships — they already closed tickets, but we don't want to
    // re-celebrate.
    if (!initializedRef.current) {
      initializedRef.current = true;
      const nextSnap: CelebratedSnapshot = { ...snapshot };
      let changed = false;
      for (const m of MILESTONES) {
        if (state[m.key] && !snapshot[m.key]) {
          nextSnap[m.key] = state[m.key] ?? null;
          changed = true;
        }
      }
      if (changed) writeSnapshot(nextSnap);
      return;
    }

    // Subsequent renders: fire celebrations for new milestones.
    const nextSnap: CelebratedSnapshot = { ...snapshot };
    let anyFired = false;
    for (const m of MILESTONES) {
      const current = state[m.key];
      if (current && !snapshot[m.key]) {
        toast.success(`${m.emoji}  ${m.message}`, { duration: 5000 });
        anyFired = true;
        nextSnap[m.key] = current;
      }
    }
    if (anyFired) {
      fireConfetti();
      writeSnapshot(nextSnap);
    }
  }, [state]);

  // Renders nothing visually — it's purely an effect host.
  return null;
}
