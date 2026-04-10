import { useState, useRef, useEffect } from 'react';
import { X, Lock, Loader2 } from 'lucide-react';
import { authApi } from '@/api/endpoints';

interface PinModalProps {
  title?: string;
  onSuccess: () => void;
  onCancel: () => void;
}

const MAX_ATTEMPTS = 5;
const LOCKOUT_SECONDS = 30;

export function PinModal({ title = 'Enter PIN to continue', onSuccess, onCancel }: PinModalProps) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [verifying, setVerifying] = useState(false);
  const [failCount, setFailCount] = useState(0);
  const [lockedUntil, setLockedUntil] = useState<number | null>(null);
  const [lockCountdown, setLockCountdown] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const isLocked = lockedUntil !== null && Date.now() < lockedUntil;

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
      onSuccess();
    } catch {
      const newCount = failCount + 1;
      setFailCount(newCount);
      if (newCount >= MAX_ATTEMPTS) {
        setLockedUntil(Date.now() + LOCKOUT_SECONDS * 1000);
        setError(`Too many attempts. Please wait ${LOCKOUT_SECONDS}s.`);
      } else {
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
      <div className="relative w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <div className="flex items-center gap-2">
            <Lock className="h-4 w-4 text-surface-500" />
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-50">{title}</h2>
          </div>
          <button
            aria-label="Close"
            onClick={onCancel}
            className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="px-5 py-4 space-y-4">
          <input
            ref={inputRef}
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={6}
            value={pin}
            disabled={isLocked}
            onChange={(e) => {
              setPin(e.target.value.replace(/\D/g, ''));
              if (!isLocked) setError('');
            }}
            placeholder={isLocked ? `Wait ${lockCountdown}s` : 'PIN'}
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl tracking-[0.5em] focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 disabled:opacity-50 disabled:cursor-not-allowed dark:border-surface-600 dark:bg-surface-800 dark:text-surface-50"
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
              className="flex flex-1 items-center justify-center gap-2 rounded-lg bg-teal-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-teal-700 disabled:opacity-50"
            >
              {verifying ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Verify'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
