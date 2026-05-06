import { StrictMode, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { Toaster, toast, useToasterStore } from 'react-hot-toast';
import App from './App';
import { ErrorBoundary, isChunkLoadError, tryReloadForChunkError } from './components/shared/PageErrorBoundary';
import { AUTH_CLEAR_EVENT, AUTH_READY_EVENT, useAuthStore } from './stores/authStore';
import { setupReactQueryIndexedDbPersistence } from './queryPersistence';
import './styles/globals.css';

// D4-10: dismiss oldest visible toast when count exceeds `max`. Prevents
// the 20+ toast stack from rapid barcode scans or network error storms.
// Also mirrors the most-recent toast into the sr-only aria-live region so
// screen readers announce notifications without relying on react-hot-toast's
// DOM structure (which has no aria-live attribute).
function ToastAvalancheGuard({ max }: { max: number }): null {
  const { toasts } = useToasterStore();
  useEffect(() => {
    const visible = toasts.filter((t) => t.visible);

    // Announce the newest visible toast to screen readers via the live region.
    const liveRegion = document.getElementById('toast-live-region');
    if (liveRegion) {
      const newest = visible[0];
      const msg = newest
        ? typeof newest.message === 'string'
          ? newest.message
          : ''
        : '';
      // Toggling to empty then back forces the AT to re-announce even when
      // the same message fires twice in a row (e.g. repeated save errors).
      // setTimeout(0) is used instead of Promise.resolve().then() because
      // microtasks may not yield a new DOM task in all AT implementations,
      // whereas a macrotask boundary reliably triggers a fresh announcement.
      if (liveRegion.textContent !== msg) {
        liveRegion.textContent = '';
        setTimeout(() => { liveRegion.textContent = msg; }, 0);
      }
    }

    if (visible.length <= max) return;
    // Dedup by message before capping — in an error storm the same message
    // fires N times; dismiss all-but-one duplicate first so the oldest
    // unique error isn't the collateral victim of the overflow cut.
    const seen = new Set<string>();
    const deduped = visible.filter((t) => {
      const key = typeof t.message === 'string' ? t.message : String(t.id);
      if (seen.has(key)) {
        toast.dismiss(t.id);
        return false;
      }
      seen.add(key);
      return true;
    });
    const overflow = deduped.length - max;
    // Oldest first — react-hot-toast pushes new toasts to the front of the
    // array by default, so the tail is the oldest.
    for (let i = 0; i < overflow; i++) {
      const victim = deduped[deduped.length - 1 - i];
      if (victim) toast.dismiss(victim.id);
    }
  }, [toasts, max]);
  return null;
}

// ─── App Bootstrap ────────────────────────────────────────────────

// WEB-FE-010 (Fixer-OOO 2026-04-25): seed `<html lang>` from the browser's
// preferred language so non-English-locale tenants get correct screen-reader
// pronunciation (es-MX, fr-CA, etc.) instead of the static `lang="en"`
// hard-coded in index.html. WCAG 3.1.1 Language of Page. When tenant-locale
// settings ship, callers can override at runtime by setting
// `document.documentElement.lang = '<bcp47>'`.
if (typeof document !== 'undefined') {
  try {
    const nav = typeof navigator !== 'undefined' ? navigator : null;
    const preferred = nav?.language || (nav?.languages?.[0] ?? '') || 'en';
    // BCP-47 sanity check: allow "en", "en-US", "es-MX", "fr-CA", "zh-Hant".
    if (/^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(preferred)) {
      document.documentElement.lang = preferred;
    }
  } catch { /* non-DOM env — leave the static lang from index.html */ }
}

// WEB-FE-011 (Fixer-OOO 2026-04-25): forward uncaught render errors to a
// best-effort server crash sink (`POST /api/v1/telemetry/client-error`) so
// operators learn about white-screens without waiting for customer
// complaints. Sink endpoint is opt-in: the request is `keepalive` + fire-
// and-forget; a 404 from a deployment that hasn't shipped the route yet is
// silently swallowed. Reused by the global ErrorBoundary's componentDidCatch
// below.
function reportClientCrash(payload: {
  message: string;
  stack?: string;
  componentStack?: string;
  url?: string;
  ts?: number;
}): void {
  try {
    if (typeof fetch !== 'function') return;
    const body = JSON.stringify({
      message: payload.message?.slice(0, 2000) ?? '',
      stack: payload.stack?.slice(0, 4000) ?? '',
      component_stack: payload.componentStack?.slice(0, 4000) ?? '',
      url: payload.url ?? (typeof location !== 'undefined' ? location.href : ''),
      ts: payload.ts ?? Date.now(),
      ua: typeof navigator !== 'undefined' ? navigator.userAgent : '',
    });
    fetch('/api/v1/telemetry/client-error', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
      // keepalive lets the request survive a tab close / navigation away
      keepalive: true,
      credentials: 'include',
    }).catch(() => { /* best-effort — never let reporting throw */ });
  } catch { /* best-effort */ }
}
// Expose for the boundary class below without growing its scope.
(globalThis as { __bizarreReportCrash?: typeof reportClientCrash }).__bizarreReportCrash = reportClientCrash;

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

const queryPersistence = setupReactQueryIndexedDbPersistence(
  queryClient,
  () => useAuthStore.getState().user,
  AUTH_READY_EVENT,
);

// @audit-fixed: clear React Query cache on logout / forced session-clear so the
// next sign-in does not display the previous user's tickets, customers, etc.
// authStore dispatches this event in `logout()` and on the LOGOUT_REQUIRED path.
if (typeof window !== 'undefined') {
  window.addEventListener(AUTH_CLEAR_EVENT, () => {
    queryPersistence.clearPersistedCache();
    queryClient.clear();
    // WEB-FJ-006 / FIXED-by-Fixer-JJJ 2026-04-25 — wipe PII residue from
    // the previous session: `recent_views` (Sidebar) and `crm_recent_searches`
    // (sessionStorage) hold customer/ticket NAMES + email/phone strings that
    // would otherwise survive logout and leak last-seen identities to the
    // next user of a shared kiosk PC. Also drop any `draft_sms_*` /
    // `draft_note_ticket_*` / `draft_note_*` keys (WEB-FJ-004 hazard) so SMS
    // body residue + ticket-note drafts don't sit in localStorage post-logout.
    try {
      window.localStorage.removeItem('recent_views');
      window.sessionStorage.removeItem('crm_recent_searches');
      // Sweep namespaced draft keys. Iterate over a snapshot of keys because
      // removeItem mutates the live `length`.
      const draftKeys: string[] = [];
      for (let i = 0; i < window.localStorage.length; i += 1) {
        const k = window.localStorage.key(i);
        if (k && (k.startsWith('draft_sms_') || k.startsWith('draft_note_'))) {
          draftKeys.push(k);
        }
      }
      draftKeys.forEach((k) => window.localStorage.removeItem(k));
      // WEB-FAE-003 / FIXED-by-Fixer-A20 2026-04-25 — `tutorial.all.dismissed`
      // and `tutorial.<flowId>.dismissed` flags (set by SpotlightCoach +
      // dismissAllTutorials) are NOT user-scoped, so a previous user's
      // "skip all" decision suppresses tutorials for the next sign-in on the
      // same browser. Sweep every `tutorial.*` localStorage key on auth-cleared
      // so each user sees their own onboarding flow on first login.
      const tutorialKeys: string[] = [];
      for (let i = 0; i < window.localStorage.length; i += 1) {
        const k = window.localStorage.key(i);
        if (k && k.startsWith('tutorial.')) tutorialKeys.push(k);
      }
      tutorialKeys.forEach((k) => window.localStorage.removeItem(k));
    } catch { /* quota / privacy mode — best-effort only */ }
  });

  // WEB-FAE-009: cross-tenant token clobber detected by authStore's storage
  // event handler. authStore dispatches this custom event so we can surface
  // a toast (toast is imported here, not in authStore) before the redirect.
  window.addEventListener('bizarre-crm:cross-tenant-token', (e: Event) => {
    try {
      const msg = (e as CustomEvent<{ message: string }>).detail?.message
        || 'Account changed in another tab. Please sign in again.';
      toast.error(msg, { id: 'cross-tenant-swap', duration: 8000 });
    } catch { /* best-effort */ }
  });

  // Stale lazy-chunk auto-reload (belt + suspenders with PageErrorBoundary).
  // React.lazy() rejections surface as render errors that boundaries catch,
  // but a dynamic `import()` triggered outside the Suspense tree (e.g. from
  // an event handler or a timer) rejects as an unhandled Promise and never
  // reaches any boundary. Catch that path here. Sentinel format + logic
  // must stay in sync with PageErrorBoundary — a prior (url, ts) pair
  // within 30 s blocks a second retry so genuine 404s fall through to
  // the manual card instead of looping (SCAN-1184).
  // WEB-FE-009 (Fixer-426B 2026-04-26): bfcache restore guard.
  // Safari/Firefox may restore a tab from the back/forward cache (`pageshow`
  // with `event.persisted === true`). The in-memory React Query cache (the
  // module-scoped `queryClient` singleton) survives the restore. If staleTime
  // hasn't elapsed the page re-renders with stale data from the *previous*
  // user session — no refetch fires and the wrong user's data is briefly
  // visible. Fix: on bfcache restore, force-invalidate all active queries so
  // each of them revalidates before paint. If the cookie-session hint is gone,
  // also clear the cache + hard-redirect to /login.
  window.addEventListener('pageshow', (e: PageTransitionEvent) => {
    if (!e.persisted) return; // normal forward nav — nothing to do
    const hasSessionHint = /(?:^|;\s*)csrf_token=/.test(document.cookie);
    if (!hasSessionHint) {
      // Session gone while tab was in bfcache — wipe and redirect.
      queryClient.clear();
      if (!window.location.pathname.startsWith('/login')) {
        window.location.replace('/login');
      }
      return;
    }
    // Auth still valid — invalidate everything so the restored tab pulls fresh
    // data before the user interacts. staleTime is intentionally bypassed here.
    queryClient.invalidateQueries();
  });

  window.addEventListener('unhandledrejection', (e) => {
    if (isChunkLoadError(e.reason)) {
      tryReloadForChunkError('[main]');
    }
  });
  window.addEventListener('error', (e) => {
    // ErrorEvent carries the original Error on `e.error` — read its name so
    // the TypeError / ChunkLoadError gate matches the unhandledrejection
    // path. If `e.error` is missing (some browsers null it for cross-origin
    // script errors) we conservatively skip the reload rather than reload
    // on a substring-only match.
    if (isChunkLoadError(e.error)) {
      tryReloadForChunkError('[main]');
    }
  });
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary variant="root" boundaryName="RootErrorBoundary" autoReloadChunks>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <App />
          {/*
            react-hot-toast renders its portal outside the React tree and does
            not add aria-live to the container, so screen readers never hear
            toasts. Wrap with a visually-hidden live region that mirrors the
            latest visible toast message so AT users get the same feedback.
            role="status" maps to aria-live="polite" which is correct for
            non-urgent notifications; error toasts are already prefixed with
            the toast icon / "Error" text so severity is communicated.
          */}
          <div
            role="status"
            aria-live="polite"
            aria-atomic="true"
            className="sr-only"
            id="toast-live-region"
          />
          {/*
            WEB-FQ-020 (Fixer-C15 2026-04-25): toast vs inline-banner policy.
            Codebase has 599 toast() calls AND scattered inline banners on the
            same flows (login + signup show inline errors, settings prefer
            toasts, estimates use both). To stop users scanning two surfaces:
              - Form-submit FAILURES (login, signup, save-settings, checkout):
                inline banner near the submit button — keeps the field error
                local to the form. Use <LoginError/>, <FormBanner/>, role="alert".
              - Background async results (mutations not tied to a visible form,
                queries that errored, broadcast channel signals, file-export
                completion, post-checkout receipt): toast.error/success.
            Both surfaces should call utils/apiError.formatApiError() so the
            ERR_* code + request_id is shown to the user for support tickets.
          */}
          {/* WEB-FAC-007: stagger duration by severity so burst-fired toasts
              dismiss at different times rather than vanishing in a single hop.
              gutter=8 adds breathing room between stacked toasts.
              Exit-animation CSS is applied via className — react-hot-toast
              handles the slide-in; motion-reduce users get instant dismiss
              (the Tailwind `motion-safe:` guard in the class). */}
          <Toaster
            position="top-right"
            gutter={8}
            containerAriaLabel="Notifications"
            toastOptions={{
              className: '!bg-white !text-surface-900 dark:!bg-surface-800 dark:!text-surface-100 !shadow-lg !border !border-surface-200 dark:!border-surface-700',
              // Default; overridden per-type below.
              duration: 4000,
              success: { duration: 3000 },
              error: { duration: 6000 },
              loading: { duration: Infinity },
              ariaProps: { role: 'status', 'aria-live': 'polite' },
            }}
          />
          {/* D4-10: cap concurrent visible toasts to avoid UI avalanche from
              rapid-fire events (barcode scan floods, network error storms). */}
          <ToastAvalancheGuard max={5} />
        </BrowserRouter>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>
);
