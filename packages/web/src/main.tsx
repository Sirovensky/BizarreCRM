import { StrictMode, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { Toaster, toast, useToasterStore } from 'react-hot-toast';
import App from './App';
import { ErrorBoundary, isChunkLoadError, tryReloadForChunkError } from './components/shared/PageErrorBoundary';
import { AUTH_CLEAR_EVENT, AUTH_READY_EVENT, useAuthStore } from './stores/authStore';
import { setupReactQueryIndexedDbPersistence } from './queryPersistence';
import { applyDocumentLanguage, getBrowserDocumentLanguage } from './utils/documentLanguage';
import './styles/globals.css';

// D4-10: collapse duplicate visible toasts from rapid barcode scans or
// network error storms. WEB-UIUX-223: do not cap distinct messages; dropping
// the 6th unique toast can hide important errors.
// Also mirrors the most-recent toast into the sr-only aria-live region so
// screen readers announce notifications without relying on react-hot-toast's
// DOM structure (which has no aria-live attribute).
function ToastDeduplicationGuard(): null {
  const { toasts } = useToasterStore();

  // WEB-UIUX-913: keyboard-dismiss for toasts. react-hot-toast renders no
  // dismiss button and no Esc handler — the 599 toast() call sites have no
  // way to clear a stale alert without the mouse. A single window-level Esc
  // listener calls toast.dismiss() (no id = dismiss all visible) so keyboard
  // users get parity. Skipped when an interactive form/dialog is in focus
  // since their own Esc handlers (modals, search clears) take precedence.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== 'Escape') return;
      // Don't steal Esc from open dialogs / inputs that consume it themselves.
      const ae = document.activeElement as HTMLElement | null;
      if (ae?.closest('[role="dialog"]')) return;
      if (ae?.tagName === 'INPUT' || ae?.tagName === 'TEXTAREA' || ae?.isContentEditable) return;
      // Only dismiss if at least one toast is currently visible — otherwise
      // we'd intercept a no-op Esc that some other handler should have seen.
      // The Toaster renders each visible toast with role="status" so a DOM
      // probe is enough; we don't need the toaster store here (its hook isn't
      // a zustand store with getState()).
      const anyVisible = !!document.querySelector('[role="status"][aria-live="polite"]');
      if (!anyVisible) return;
      toast.dismiss();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

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

    const seen = new Set<string>();
    visible.forEach((t) => {
      const key = typeof t.message === 'string' && t.message.trim()
        ? `${t.type}:${t.message}`
        : String(t.id);
      if (seen.has(key)) {
        toast.dismiss(t.id);
        return;
      }
      seen.add(key);
    });
  }, [toasts]);
  return null;
}

// ─── App Bootstrap ────────────────────────────────────────────────

// Seed `<html lang>` from the browser before React mounts. Authenticated CRM
// pages refine this from the existing per-user `language` preference.
if (typeof document !== 'undefined') {
  applyDocumentLanguage(getBrowserDocumentLanguage());
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

  // WEB-FAE-009 / WEB-UIUX-816: cross-tenant token detected by authStore's
  // storage/broadcast handler. When this tab is logged out (oldSlug null) and a
  // sibling writes a tenant-B token, authStore dispatches this event instead of
  // silently calling checkAuth(). We surface a persistent toast so the user must
  // explicitly reload before adopting the new tenant session.
  window.addEventListener('bizarre-crm:cross-tenant-token', (e: Event) => {
    try {
      const msg = (e as CustomEvent<{ message: string }>).detail?.message
        || 'A sign-in occurred in another tab. Reload this page to sign in.';
      // duration: Infinity keeps the toast visible until the user acts (reload or dismiss).
      // This is the explicit-action gate required by WEB-UIUX-816: the tab will NOT
      // silently re-hydrate — the user must reload intentionally.
      toast.error(msg, { id: 'cross-tenant-swap', duration: Infinity });
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
            toastOptions={{
              className: '!bg-white !text-surface-900 dark:!bg-surface-800 dark:!text-surface-100 !shadow-lg !border !border-surface-200 dark:!border-surface-700',
              // Default; overridden per-type below.
              duration: 5000,
              success: { duration: 4000 },
              error: { duration: 6000 },
              loading: { duration: Infinity },
              // WEB-UIUX-913: react-hot-toast's ariaProps type only allows
              // role/aria-live, not tabIndex — keyboard reachability is handled
              // by the global Esc handler in ToastDeduplicationGuard above (which
              // calls toast.dismiss() while any toast is visible). role=status
              // + aria-live=polite still drives assistive announcement.
              ariaProps: { role: 'status', 'aria-live': 'polite' },
            }}
          />
          {/* D4-10 / WEB-UIUX-223: dedupe rapid-fire toast storms without
              dropping distinct notifications. */}
          <ToastDeduplicationGuard />
        </BrowserRouter>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>
);
