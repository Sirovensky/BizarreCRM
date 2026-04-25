import { Component, StrictMode, useEffect } from 'react';
import type { ReactNode, ErrorInfo } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { Toaster, toast, useToasterStore } from 'react-hot-toast';
import App from './App';
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
      if (liveRegion.textContent !== msg) {
        liveRegion.textContent = '';
        // Micro-task flush so the empty update is processed first.
        Promise.resolve().then(() => { liveRegion.textContent = msg; });
      }
    }

    if (visible.length <= max) return;
    const overflow = visible.length - max;
    // Oldest first — react-hot-toast pushes new toasts to the front of the
    // array by default, so the tail is the oldest.
    for (let i = 0; i < overflow; i++) {
      const victim = visible[visible.length - 1 - i];
      if (victim) toast.dismiss(victim.id);
    }
  }, [toasts, max]);
  return null;
}

// ─── Global Error Boundary ────────────────────────────────────────

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<{ children: ReactNode }, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // eslint-disable-next-line no-console
    console.error('Uncaught render error:', error, info.componentStack);
    // WEB-FE-011 (Fixer-OOO 2026-04-25): forward to the server crash sink
    // so this isn't a console-only signal. Best-effort; a missing endpoint
    // or offline tab silently degrades back to the previous behaviour.
    try {
      const reporter = (globalThis as {
        __bizarreReportCrash?: (p: {
          message: string;
          stack?: string;
          componentStack?: string;
        }) => void;
      }).__bizarreReportCrash;
      reporter?.({
        message: error?.message ?? 'unknown render error',
        stack: error?.stack,
        componentStack: info?.componentStack ?? undefined,
      });
    } catch { /* never throw out of componentDidCatch */ }
  }

  render() {
    if (this.state.hasError) {
      // WEB-FE-023: Tailwind classes (with `dark:` variants) so the root
      // boundary at least respects prefers-color-scheme. Tailwind has run
      // before React mounts, so utility classes are available even when
      // every page chunk failed to render.
      return (
        <div className="flex min-h-screen flex-col items-center justify-center bg-surface-50 p-8 text-center font-sans dark:bg-surface-950">
          <div className="mb-4 text-5xl" aria-hidden="true">&#9888;</div>
          <h1 className="mb-2 text-2xl font-bold text-surface-900 dark:text-surface-50">
            Something went wrong
          </h1>
          <p className="mb-6 max-w-lg text-surface-500 dark:text-surface-400">
            An unexpected error occurred. Please reload the page to try again.
          </p>
          <button
            onClick={() => window.location.reload()}
            className="rounded-lg bg-primary-600 px-6 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700"
          >
            Reload Page
          </button>
        </div>
      );
    }
    return this.props.children;
  }
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

// @audit-fixed: clear React Query cache on logout / forced session-clear so the
// next sign-in does not display the previous user's tickets, customers, etc.
// authStore dispatches this event in `logout()` and on the LOGOUT_REQUIRED path.
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => {
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
    } catch { /* quota / privacy mode — best-effort only */ }
  });

  // Stale lazy-chunk auto-reload (belt + suspenders with PageErrorBoundary).
  // React.lazy() rejections surface as render errors that boundaries catch,
  // but a dynamic `import()` triggered outside the Suspense tree (e.g. from
  // an event handler or a timer) rejects as an unhandled Promise and never
  // reaches any boundary. Catch that path here. Sentinel format + logic
  // must stay in sync with PageErrorBoundary — a prior (url, ts) pair
  // within 30 s blocks a second retry so genuine 404s fall through to
  // the manual card instead of looping (SCAN-1184).
  const CHUNK_RELOAD_SENTINEL = 'bizarre:chunk-reload-attempted';
  // WEB-FI-009 (Fixer-SSS 2026-04-25): pair the message regex with a name
  // gate so a user-authored error that happens to contain phrases like
  // "Importing a module script failed" (e.g. a string baked into a server
  // response or an i18n catalog entry) cannot trigger an infinite reload
  // loop limited only by the 30s sentinel. Genuine dynamic-import failures
  // surface either as `name === 'TypeError'` (Chrome/Safari/Firefox path
  // for Failed to fetch dynamically imported module) or as `name ===
  // 'ChunkLoadError'` (legacy bundler / explicit class). Anything else
  // that merely shares a substring is treated as user error and bubbles
  // to the boundary card instead of nuking the page.
  const looksLikeChunkMessage = (msg: string): boolean =>
    /Failed to fetch dynamically imported module/i.test(msg) ||
    /error loading dynamically imported module/i.test(msg) ||
    /Importing a module script failed/i.test(msg) ||
    /ChunkLoadError/i.test(msg);
  const isChunkError = (name: string, msg: string): boolean => {
    if (name === 'ChunkLoadError') return true;
    if (name === 'TypeError' && looksLikeChunkMessage(msg)) return true;
    return false;
  };
  const handleChunkReload = (): void => {
    try {
      const raw = sessionStorage.getItem(CHUNK_RELOAD_SENTINEL);
      const now = Date.now();
      const url = window.location.href;
      if (raw) {
        try {
          const parsed = JSON.parse(raw) as { ts?: number; url?: string };
          if (
            parsed &&
            typeof parsed.ts === 'number' &&
            parsed.url === url &&
            now - parsed.ts < 30_000
          ) {
            return; // already tried for this URL within the grace window
          }
        } catch {
          /* old-format or corrupt — fall through and overwrite */
        }
      }
      sessionStorage.setItem(
        CHUNK_RELOAD_SENTINEL,
        JSON.stringify({ ts: now, url }),
      );
      // eslint-disable-next-line no-console
      console.warn('[main] stale chunk detected outside React tree — auto-reloading once');
      window.location.reload();
    } catch {
      /* storage blocked — user will see the manual boundary card */
    }
  };
  window.addEventListener('unhandledrejection', (e) => {
    const reason = e.reason as { message?: string; name?: string } | undefined;
    const msg = reason?.message ?? String(reason ?? '');
    const name = reason?.name ?? '';
    if (isChunkError(name, msg)) {
      handleChunkReload();
    }
  });
  window.addEventListener('error', (e) => {
    // ErrorEvent carries the original Error on `e.error` — read its name so
    // the TypeError / ChunkLoadError gate matches the unhandledrejection
    // path. If `e.error` is missing (some browsers null it for cross-origin
    // script errors) we conservatively skip the reload rather than reload
    // on a substring-only match.
    const errName = (e.error as Error | undefined)?.name ?? '';
    if (errName && isChunkError(errName, e.message || '')) {
      handleChunkReload();
    }
  });
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
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
          <Toaster
            position="top-right"
            toastOptions={{
              className: '!bg-white !text-surface-900 dark:!bg-surface-800 dark:!text-surface-100 !shadow-lg !border !border-surface-200 dark:!border-surface-700',
              duration: 4000,
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
