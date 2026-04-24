import { useState, useEffect, useRef, useCallback } from 'react';

// Hard cap to stop a pathologically long draft from blowing the localStorage
// quota (typically 5–10 MB total, shared across the whole app). 100 KB is
// ~50 pages of text — well above any realistic hand-typed form value.
const DRAFT_MAX_BYTES = 100_000;

/**
 * Hook for localStorage-based draft saving with debounce.
 * Returns [value, setValue, clearDraft, hasDraft] where hasDraft indicates
 * whether the initial value was restored from a saved draft.
 */
export function useDraft(
  key: string,
  debounceMs = 2000,
): [string, (v: string) => void, () => void, boolean] {
  const [value, setValue] = useState('');
  const [hasDraft, setHasDraft] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const keyRef = useRef(key);

  // Restore draft on mount or key change, clearing pending timer from previous key
  useEffect(() => {
    clearTimeout(timerRef.current);
    timerRef.current = undefined;
    keyRef.current = key;
    const saved = localStorage.getItem(key);
    if (saved) {
      setValue(saved);
      setHasDraft(true);
    } else {
      setValue('');
      setHasDraft(false);
    }
  }, [key]);

  // Debounced save to localStorage
  useEffect(() => {
    // Capture key at schedule time so a key change between schedule and fire
    // doesn't write the old value under the new key (SCAN-601).
    const currentKey = keyRef.current;
    clearTimeout(timerRef.current);
    if (!value) {
      // If empty, remove the draft
      localStorage.removeItem(currentKey);
      setHasDraft(false);
      return;
    }
    timerRef.current = setTimeout(() => {
      // Skip persist if the draft exceeds the quota cap. The in-memory value
      // stays live for the active editing session; we just don't survive a
      // reload if the user typed >100 KB of text into one field.
      if (value.length > DRAFT_MAX_BYTES) {
        localStorage.removeItem(currentKey);
        setHasDraft(false);
        return;
      }
      try {
        localStorage.setItem(currentKey, value);
        setHasDraft(true);
      } catch (err) {
        // QuotaExceededError or storage disabled — best-effort fallback.
        console.warn('[useDraft] failed to persist draft', err);
        setHasDraft(false);
      }
    }, debounceMs);
    return () => clearTimeout(timerRef.current);
  }, [value, debounceMs]);

  const clearDraft = useCallback(() => {
    localStorage.removeItem(keyRef.current);
    setValue('');
    setHasDraft(false);
  }, []);

  return [value, setValue, clearDraft, hasDraft];
}
