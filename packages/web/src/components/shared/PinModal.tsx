import { useState, useRef, useEffect, useCallback } from 'react';
import { X, Lock, Loader2 } from 'lucide-react';
import { authApi } from '@/api/endpoints';

// WEB-FC-005: focusable selector for in-modal Tab cycle
const FOCUSABLE_SELECTOR = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

interface PinModalProps {
  title?: string;
  onSuccess: () => void;
  onCancel: () => void;
}

const MAX_ATTEMPTS = 5;
const LOCKOUT_SECONDS = 30;
// SCAN-1168: persist the lockout across full page reloads — previously the
// counter lived in useState only, so a user who hit the 5-attempt cap could
// just refresh the page and get 5 fresh attempts. sessionStorage scopes per
// tab, which matches the UX intent (closing the tab = ending the kiosk
// session). Server-side `authApi.verifyPin` has its own rate limit, but
// that surfaces as "too many attempts" AFTER a dozen hits — the UI-level
// cap is load-bearing for the "N remaining" message.
const LOCKOUT_STORAGE_KEY = 'bizarre:pin-modal-lockout';

interface PersistedLockout {
  failCount: number;
  lockedUntil: number | null;
}

function readPersistedLockout(): PersistedLockout {
  try {
    const raw = sessionStorage.getItem(LOCKOUT_STORAGE_KEY);
    if (!raw) return { failCount: 0, lockedUntil: null };
    const parsed = JSON.parse(raw) as Partial<PersistedLockout>;
    return {
      failCount: typeof parsed.failCount === 'number' && parsed.failCount >= 0 ? parsed.failCount : 0,
      lockedUntil: typeof parsed.lockedUntil === 'number' && parsed.lockedUntil > 0 ? parsed.lockedUntil : null,
    };
  } catch {
    return { failCount: 0, lockedUntil: null };
  }
}

function writePersistedLockout(next: PersistedLockout): void {
  try { sessionStorage.setItem(LOCKOUT_STORAGE_KEY, JSON.stringify(next)); }
  catch (err) {
    // quota / sandboxed — best effort; lockout still tracked in component state.
    console.warn('[PinModal] persisting lockout state failed', err);
  }
}

function clearPersistedLockout(): void {
  try { sessionStorage.removeItem(LOCKOUT_STORAGE_KEY); }
  catch { /* ignore */ }
}

export function PinModal({ title = 'Enter PIN to continue', onSuccess, onCancel }: PinModalProps) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [verifying, setVerifying] = useState(false);
  const initialLockout = (() => {
    const persisted = readPersistedLockout();
    // Drop stale lockouts whose expiry has passed.
    if (persisted.lockedUntil !== null && persisted.lockedUntil <= Date.now()) {
      clearPersistedLockout();
      return { failCount: 0, lockedUntil: null };
    }
    return persisted;
  })();
  const [failCount, setFailCount] = useState(initialLockout.failCount);
  const [lockedUntil, setLockedUntil] = useState<number | null>(initialLockout.lockedUntil);
  const [lockCountdown, setLockCountdown] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  // WEB-FC-005: dialog ref drives the Tab focus trap below
  const dialogRef = useRef<HTMLDivElement>(null);

  const isLocked = lockedUntil !== null && Date.now() < lockedUntil;

  // WEB-FC-005: keyboard handler — Esc closes the modal, Tab/Shift+Tab is
  // trapped inside the dialog so keyboard users can't focus chrome behind
  // the overlay.
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      onCancel();
      return;
    }
    if (e.key !== 'Tab') return;
    const dialog = dialogRef.current;
    if (!dialog) return;
    const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR));
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (e.shiftKey) {
      if (document.activeElement === first) {
        e.preventDefault();
        last.focus();
      }
    } else {
      if (document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
  }, [onCancel]);

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  // Countdown timer while locked out
  useEffect(() => {
    if (!lockedUntil) return;
    const tick = () => {
      const remaining = Math.ceil((lockedUntil - Date.now()) / 1000);
      if (remaining <= 0) {
        setLockedUntil(null);
        setLockCountdown(0);
        setError('');
        setFailCount(0);
        // SCAN-1168: lockout expired naturally — scrub persisted state so
        // the next tab load starts fresh.
        clearPersistedLockout();
        inputRef.current?.focus();
      } else {
        setLockCountdown(remaining);
      }
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [lockedUntil]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pin.trim() || verifying || isLocked) return;

    setVerifying(true);
    setError('');

    try {
      await authApi.verifyPin(pin);
      // SCAN-1168: on success, reset persisted counters so the next gated
      // action doesn't inherit a stale failCount on this tab.
      clearPersistedLockout();
      onSuccess();
    } catch {
      const newCount = failCount + 1;
      setFailCount(newCount);
      if (newCount >= MAX_ATTEMPTS) {
        const lockTs = Date.now() + LOCKOUT_SECONDS * 1000;
        setLockedUntil(lockTs);
        writePersistedLockout({ failCount: newCount, lockedUntil: lockTs });
        setError(`Too many attempts. Please wait ${LOCKOUT_SECONDS}s.`);
      } else {
        writePersistedLockout({ failCount: newCount, lockedUntil: null });
        setError(`Invalid PIN (${MAX_ATTEMPTS - newCount} attempts remaining)`);
      }
      setPin('');
      inputRef.current?.focus();
    } finally {
      setVerifying(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="pin-modal-title"
        className="relative w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <div className="flex items-center gap-2">
            <Lock aria-hidden="true" className="h-4 w-4 text-surface-500" />
            <h2 id="pin-modal-title" className="text-base font-semibold text-surface-900 dark:text-surface-50">{title}</h2>
          </div>
          <button
            type="button"
            aria-label="Close"
            onClick={onCancel}
            className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800"
          >
            <X aria-hidden="true" className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="px-5 py-4 space-y-4">
          {/* SCAN-1163: stop browser password managers (Chrome, 1Password,
              Bitwarden) from offering to save the clock-in PIN as a credential
              for the app origin — a 4-6 digit kiosk PIN is explicitly NOT a
              per-user password and shouldn't live in the user's password
              vault. `autoComplete="off"` is the standard knob; `data-lpignore`
              + `data-form-type="other"` cover LastPass and 1Password's
              heuristic-driven suggestions. */}
          <input
            ref={inputRef}
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={6}
            value={pin}
            disabled={isLocked}
            autoComplete="off"
            data-lpignore="true"
            data-form-type="other"
            onChange={(e) => {
              setPin(e.target.value.replace(/\D/g, ''));
              if (!isLocked) setError('');
            }}
            placeholder={isLocked ? `Wait ${lockCountdown}s` : 'PIN'}
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl tracking-[0.5em] focus-visible:border-primary-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-600 disabled:opacity-50 disabled:cursor-not-allowed dark:border-surface-600 dark:bg-surface-800 dark:text-surface-50"
          />

          {error && (
            <p className="text-center text-sm text-red-500">{error}</p>
          )}

          <div className="flex gap-3">
            <button
              type="button"
              onClick={onCancel}
              className="flex-1 rounded-lg border border-surface-300 px-4 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!pin.trim() || verifying || isLocked}
              className="flex flex-1 items-center justify-center gap-2 rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-primary-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-600 focus-visible:ring-offset-2 disabled:opacity-50"
            >
              {verifying ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Verify'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
