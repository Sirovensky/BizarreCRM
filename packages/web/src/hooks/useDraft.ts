import { useState, useEffect, useRef, useCallback } from 'react';
import toast from 'react-hot-toast';
import { useAuthStore } from '@/stores/authStore';

// WEB-UIUX-846: throttle the quota-toast so we only nag the cashier once per
// session even though useDraft persists on every keystroke debounce. Sticky
// reminder until the user closes it.
let _quotaToastShown = false;

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
// WEB-UIUX-908: also sweep persisted POS cart state (`pos-store-u*` /
// `pos-store-u*-r*` from unified-pos/store.ts), which previously survived
// logout and left a fired employee's pending cart in localStorage with
// customer name + items.
const POS_STORE_KEY_RE = /^pos-store-u\d+/;

function wipeAllDrafts(): void {
  if (typeof localStorage === 'undefined') return;
  try {
    // Walk localStorage; collect first, delete second (mutating during the
    // forward iterate would shift indices and skip keys).
    const toRemove: string[] = [];
    for (let i = 0; i < localStorage.length; i += 1) {
      const k = localStorage.key(i);
      if (!k) continue;
      if (DRAFT_NAMESPACE_LEGACY_RE.test(k) || POS_STORE_KEY_RE.test(k)) toRemove.push(k);
    }
    toRemove.forEach((k) => {
      try { localStorage.removeItem(k); } catch { /* best-effort */ }
    });
  } catch (err) {
    console.warn('[useDraft] failed to wipe drafts on auth-cleared', err);
  }
}

if (typeof window !== 'undefined') {
  // WEB-UIUX-744: skip draft wipe when auth-cleared fires for a cross-tab
  // silent refresh on the SAME user. The event carries prevUserId in detail;
  // if it matches the currently authenticated user, no user change occurred
  // and drafts must not be wiped.
  window.addEventListener('bizarre-crm:auth-cleared', (e: Event) => {
    const detail = (e as CustomEvent<{ prevUserId?: string | number | null }>).detail;
    const currentUserId = useAuthStore.getState().user?.id ?? null;
    if (detail?.prevUserId != null && detail.prevUserId === currentUserId) return;
    wipeAllDrafts();
  });
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

export interface DraftStatus {
  /** True when the current value has been successfully persisted to localStorage. */
  saved: boolean;
  /**
   * True when the draft exceeds DRAFT_MAX_BYTES and was NOT written to
   * localStorage. The caller should display a visible warning so the user
   * knows their content will not survive a reload.
   */
  oversize?: boolean;
  /**
   * Timestamp of the last successful localStorage write, or null if no
   * successful write has occurred in the current mount (e.g. value is empty,
   * never crossed a debounce boundary yet, or every write attempt overflowed).
   */
  lastSavedAt: Date | null;
}

/**
 * Hook for localStorage-based draft saving with debounce.
 * Returns [value, setValue, clearDraft, status] where status is a
 * {@link DraftStatus} object that replaces the old plain `hasDraft` boolean.
 *
 * - `status.saved`     — true when localStorage holds the current value.
 * - `status.oversize`  — true when the value exceeds 100 KB and was NOT
 *                        persisted to localStorage. Callers MUST surface this
 *                        to the user (toast / banner) so they are not surprised
 *                        by lost work on reload. To prevent reaching this cap
 *                        via paste, set `maxLength={100_000}` on the underlying
 *                        `<textarea>` (or equivalent rich-text constraint).
 *                        A `console.warn` is also emitted so engineers see the
 *                        drop in DevTools when testing large-paste scenarios.
 * - `status.lastSavedAt` — wall-clock time of the last successful write.
 *
 * The `key` is the caller's per-form/per-record identifier (e.g.
 * `'ticket-1234-notes'`). Internally it is prefixed with
 * `bizarrecrm:draft:<userId>:` so drafts cannot leak across tenants/users
 * on a shared browser, and so logout can wipe them in a single sweep.
 */
export function useDraft(
  key: string,
  debounceMs = 2000,
): [string, (v: string) => void, () => void, DraftStatus] {
  const [value, setValue] = useState('');
  const [hasDraft, setHasDraft] = useState(false);
  const [oversize, setOversize] = useState<boolean | undefined>(undefined);
  const [lastSavedAt, setLastSavedAt] = useState<Date | null>(null);
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
    // Reset oversize/lastSavedAt on key change — they belong to the previous key.
    setOversize(undefined);
    setLastSavedAt(null);
    if (saved) {
      setValue(saved);
      setHasDraft(true);
    } else {
      setValue('');
      setHasDraft(false);
    }
  }, [key]);

  // WEB-UIUX-739: cross-tab sync via the `storage` event. Without this, two
  // tabs editing the same form clobber each other on the next debounce tick
  // — last writer wins and the other tab silently loses the in-progress
  // edit. We listen for storage events keyed to the active scopedKey and
  // pull the freshest value in. We don't override an actively-edited local
  // state from a stale storage event by checking the timestamp window: if
  // the local valueRef differs and was updated recently, we keep local and
  // let our own debounce win.
  useEffect(() => {
    function onStorage(e: StorageEvent) {
      if (!e.key || e.key !== scopedKeyRef.current) return;
      // Another tab cleared this key — adopt the empty state if we're idle.
      if (e.newValue == null) {
        if (!valueRef.current) return;
        // Local has content; don't blindly wipe. Surface as "hasDraft" still
        // until the user saves over it.
        return;
      }
      // Another tab wrote a value — adopt only when our local state matches
      // the previous remote value or is empty (i.e. we have nothing to lose).
      if (!valueRef.current || valueRef.current === e.oldValue) {
        if (mountedRef.current) {
          setValue(e.newValue);
          setHasDraft(true);
        }
      }
    }
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

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
      // WEB-UIUX-318: surface this as `oversize: true` in DraftStatus so the
      // caller can show a warning — previously this was a silent data loss.
      if (value.length > DRAFT_MAX_BYTES) {
        localStorage.removeItem(currentKey);
        // WEB-UIUX-845: warn engineers that oversized content was dropped so
        // the omission is visible in DevTools / CI logs. The `oversize` status
        // flag is the caller-facing signal; this warn is the dev-facing one.
        console.warn(
          `[useDraft] draft key "${currentKey}" is ${value.length} bytes — ` +
          `exceeds ${DRAFT_MAX_BYTES}-byte cap and was NOT persisted to ` +
          'localStorage. Content survives only for the current session. ' +
          'Consider adding a textarea maxLength or splitting into smaller fields.',
        );
        if (mountedRef.current) {
          setHasDraft(false);
          setOversize(true);
          // lastSavedAt intentionally left unchanged — it still reflects the
          // last moment the draft was successfully stored so the caller can
          // show "last saved at <time>, current content too large to save".
        }
        return;
      }
      try {
        localStorage.setItem(currentKey, value);
        if (mountedRef.current) {
          setHasDraft(true);
          setOversize(false);
          setLastSavedAt(new Date());
        }
      } catch (err) {
        // QuotaExceededError or storage disabled — best-effort fallback.
        console.warn('[useDraft] failed to persist draft', err);
        if (mountedRef.current) setHasDraft(false);
        // WEB-UIUX-846: surface to the operator so a kiosk with saturated
        // localStorage doesn't silently lose draft data on submit.
        const isQuota =
          (err instanceof Error && /quota/i.test(err.name)) ||
          (typeof err === 'object' && err !== null && /quota/i.test((err as { name?: string }).name ?? ''));
        if (isQuota && !_quotaToastShown) {
          _quotaToastShown = true;
          toast.error(
            'Browser storage is full — drafts cannot be saved. Clear browser data or sign out and back in.',
            { duration: 8000, id: 'usedraft-quota' },
          );
        }
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
    setOversize(undefined);
    setLastSavedAt(null);
  }, []);

  const status: DraftStatus = {
    saved: hasDraft,
    ...(oversize !== undefined && { oversize }),
    lastSavedAt,
  };

  return [value, setValue, clearDraft, status];
}
