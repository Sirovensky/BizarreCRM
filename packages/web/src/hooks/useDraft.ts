import { useState, useEffect, useRef, useCallback } from 'react';
import { useAuthStore } from '@/stores/authStore';

// Hard cap to stop a pathologically long draft from blowing the localStorage
// quota (typically 5–10 MB total, shared across the whole app). 100 KB is
// ~50 pages of text — well above any realistic hand-typed form value.
const DRAFT_MAX_BYTES = 100_000;

// WEB-FI-013/014 fix: every draft key is namespaced under this prefix so
// (a) we can wipe ALL drafts in one sweep on `auth-cleared` (logout, force-
// logout, switch-user) without touching unrelated localStorage keys, and
// (b) we can prefix the user/tenant id between the namespace and the
// caller-supplied key so drafts written by tenant A are NEVER read back by
// tenant B on the same browser. This closes a cross-tenant leak: a kiosk
// browser shared between two stores no longer surfaces customer-note drafts
// across logins.
const DRAFT_NAMESPACE = 'bizarrecrm:draft:';
const DRAFT_NAMESPACE_LEGACY_RE = /^bizarrecrm:draft:/;

/**
 * Build the localStorage key for a given caller-supplied draft id.
 * Format: `bizarrecrm:draft:<userId>:<key>` (or `bizarrecrm:draft:anon:<key>`
 * if the auth store has not yet hydrated). The `anon` bucket means a draft
 * written by a logged-out form (rare — most drafts are inside protected
 * routes) still gets wiped on the next `auth-cleared` event because it
 * shares the same `bizarrecrm:draft:` namespace prefix.
 */
function buildScopedKey(rawKey: string): string {
  const user = useAuthStore.getState().user;
  const scope = user?.id != null ? String(user.id) : 'anon';
  return `${DRAFT_NAMESPACE}${scope}:${rawKey}`;
}

/**
 * Wipe every draft key in localStorage on logout. Called from a single
 * module-level `auth-cleared` listener so every mounted (or unmounted)
 * useDraft instance behaves consistently — even the ones that already
 * unmounted before the user clicked Logout.
 */
function wipeAllDrafts(): void {
  if (typeof localStorage === 'undefined') return;
  try {
    // Walk localStorage; collect first, delete second (mutating during the
    // forward iterate would shift indices and skip keys).
    const toRemove: string[] = [];
    for (let i = 0; i < localStorage.length; i += 1) {
      const k = localStorage.key(i);
      if (k && DRAFT_NAMESPACE_LEGACY_RE.test(k)) toRemove.push(k);
    }
    toRemove.forEach((k) => {
      try { localStorage.removeItem(k); } catch { /* best-effort */ }
    });
  } catch (err) {
    console.warn('[useDraft] failed to wipe drafts on auth-cleared', err);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => wipeAllDrafts());
}

// WEB-FO-021 (Fixer-C9 2026-04-25): module-level Set tracking every active
// useDraft instance's pending-write payload. On `beforeunload` we synchronously
// flush each pending draft to localStorage so a tab close mid-debounce-window
// does not lose work. Each entry is `{ key, value }`; entries are added when
// a debounce timer is scheduled and removed when it fires (or on unmount /
// when value clears). localStorage.setItem is synchronous so this is safe to
// run inside the `beforeunload` handler — no async work, no quota retry.
type PendingDraft = { key: string; getValue: () => string };
const pendingDrafts = new Set<PendingDraft>();

if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    if (pendingDrafts.size === 0) return;
    pendingDrafts.forEach((p) => {
      try {
        const v = p.getValue();
        if (!v) {
          localStorage.removeItem(p.key);
          return;
        }
        if (v.length > DRAFT_MAX_BYTES) {
          localStorage.removeItem(p.key);
          return;
        }
        localStorage.setItem(p.key, v);
      } catch { /* best-effort — quota / storage disabled */ }
    });
  });
}

/**
 * Hook for localStorage-based draft saving with debounce.
 * Returns [value, setValue, clearDraft, hasDraft] where hasDraft indicates
 * whether the initial value was restored from a saved draft.
 *
 * The `key` is the caller's per-form/per-record identifier (e.g.
 * `'ticket-1234-notes'`). Internally it is prefixed with
 * `bizarrecrm:draft:<userId>:` so drafts cannot leak across tenants/users
 * on a shared browser, and so logout can wipe them in a single sweep.
 */
export function useDraft(
  key: string,
  debounceMs = 2000,
): [string, (v: string) => void, () => void, boolean] {
  const [value, setValue] = useState('');
  const [hasDraft, setHasDraft] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  // Cache the resolved scoped key so the debounced timer + clearDraft do not
  // re-derive it on every fire (and so a mid-flight logout/login race can't
  // accidentally write under the new user's prefix — the timer captured the
  // prefix at schedule time, just as the legacy code captured the raw key).
  const scopedKeyRef = useRef(buildScopedKey(key));
  // SCAN-1085: guard setState calls in the delayed timer callback so a
  // timer that fires after the host component unmounts doesn't try to
  // update an unmounted component (React logs a warning) and doesn't
  // leak the pending timer reference beyond unmount.
  const mountedRef = useRef(true);
  // WEB-FO-021: a stable ref holding the latest value so the module-level
  // `beforeunload` handler can read whatever this instance is currently
  // editing without depending on React re-renders.
  const valueRef = useRef('');
  // WEB-FO-021: pending-flush registration token — same identity for the
  // lifetime of this hook instance so we can reliably remove on unmount.
  const pendingRef = useRef<PendingDraft | null>(null);
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      clearTimeout(timerRef.current);
      timerRef.current = undefined;
      if (pendingRef.current) {
        pendingDrafts.delete(pendingRef.current);
        pendingRef.current = null;
      }
    };
  }, []);

  // Restore draft on mount or key change, clearing pending timer from previous key
  useEffect(() => {
    clearTimeout(timerRef.current);
    timerRef.current = undefined;
    const scopedKey = buildScopedKey(key);
    scopedKeyRef.current = scopedKey;
    const saved = localStorage.getItem(scopedKey);
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
    const currentKey = scopedKeyRef.current;
    valueRef.current = value;
    clearTimeout(timerRef.current);
    if (!value) {
      // If empty, remove the draft
      localStorage.removeItem(currentKey);
      if (mountedRef.current) setHasDraft(false);
      // WEB-FO-021: nothing to flush on unload anymore for this instance.
      if (pendingRef.current) {
        pendingDrafts.delete(pendingRef.current);
        pendingRef.current = null;
      }
      return;
    }
    // WEB-FO-021: register a pending-flush entry pointing at the LATEST value
    // ref so a `beforeunload` between schedule and fire still persists the
    // current text. Re-uses the same registration object on subsequent
    // keystrokes — Set semantics dedupe.
    if (!pendingRef.current) {
      pendingRef.current = { key: currentKey, getValue: () => valueRef.current };
      pendingDrafts.add(pendingRef.current);
    } else {
      // Key may have changed (re-mount under new tenant prefix).
      pendingRef.current.key = currentKey;
    }
    timerRef.current = setTimeout(() => {
      timerRef.current = undefined;
      // Timer fired — drop pending registration; localStorage now has the
      // latest value, so unload no longer needs us.
      if (pendingRef.current) {
        pendingDrafts.delete(pendingRef.current);
        pendingRef.current = null;
      }
      // Skip persist if the draft exceeds the quota cap. The in-memory value
      // stays live for the active editing session; we just don't survive a
      // reload if the user typed >100 KB of text into one field.
      if (value.length > DRAFT_MAX_BYTES) {
        localStorage.removeItem(currentKey);
        if (mountedRef.current) setHasDraft(false);
        return;
      }
      try {
        localStorage.setItem(currentKey, value);
        if (mountedRef.current) setHasDraft(true);
      } catch (err) {
        // QuotaExceededError or storage disabled — best-effort fallback.
        console.warn('[useDraft] failed to persist draft', err);
        if (mountedRef.current) setHasDraft(false);
      }
    }, debounceMs);
    return () => {
      clearTimeout(timerRef.current);
      timerRef.current = undefined;
    };
  }, [value, debounceMs]);

  const clearDraft = useCallback(() => {
    localStorage.removeItem(scopedKeyRef.current);
    setValue('');
    setHasDraft(false);
  }, []);

  return [value, setValue, clearDraft, hasDraft];
}
