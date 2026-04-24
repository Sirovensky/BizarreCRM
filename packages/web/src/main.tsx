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
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: '100vh', padding: '2rem', fontFamily: 'system-ui, sans-serif', textAlign: 'center', backgroundColor: '#f9fafb' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>&#9888;</div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700, color: '#111827', marginBottom: '0.5rem' }}>
            Something went wrong
          </h1>
          <p style={{ color: '#6b7280', maxWidth: '32rem', marginBottom: '1.5rem' }}>
            An unexpected error occurred. Please reload the page to try again.
          </p>
          <button
            onClick={() => window.location.reload()}
            style={{ padding: '0.625rem 1.5rem', fontSize: '0.875rem', fontWeight: 600, color: '#fff', backgroundColor: '#2563eb', border: 'none', borderRadius: '0.5rem', cursor: 'pointer' }}
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
  const looksLikeChunkError = (msg: string): boolean =>
    /Failed to fetch dynamically imported module/i.test(msg) ||
    /error loading dynamically imported module/i.test(msg) ||
    /Importing a module script failed/i.test(msg) ||
    /ChunkLoadError/i.test(msg);
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
    if (name === 'ChunkLoadError' || looksLikeChunkError(msg)) {
      handleChunkReload();
    }
  });
  window.addEventListener('error', (e) => {
    if (looksLikeChunkError(e.message || '')) {
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
