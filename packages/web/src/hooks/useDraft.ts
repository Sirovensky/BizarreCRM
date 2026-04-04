import { useState, useEffect, useRef, useCallback } from 'react';

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

  // Restore draft on mount or key change
  useEffect(() => {
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
    clearTimeout(timerRef.current);
    if (!value) {
      // If empty, remove the draft
      localStorage.removeItem(keyRef.current);
      setHasDraft(false);
      return;
    }
    timerRef.current = setTimeout(() => {
      localStorage.setItem(keyRef.current, value);
      setHasDraft(true);
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
