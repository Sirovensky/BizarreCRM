import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { AlertCircle, RotateCcw } from 'lucide-react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

/**
 * Detect "stale lazy-chunk after deploy" — Vite hashes every chunk
 * filename, so a tab holding pre-deploy HTML will 404 when React.lazy
 * tries to fetch an old chunk URL. Signatures vary across browsers:
 *   Chrome/Firefox:  "Failed to fetch dynamically imported module"
 *   Safari / newer:  "Importing a module script failed"
 *   Webpack legacy:  error.name === 'ChunkLoadError'
 */
export function isChunkLoadError(err: unknown): boolean {
  if (!err) return false;
  const name = (err as { name?: string }).name ?? '';
  const msg = (err as { message?: string }).message ?? '';
  return (
    name === 'ChunkLoadError' ||
    /Failed to fetch dynamically imported module/i.test(msg) ||
    /error loading dynamically imported module/i.test(msg) ||
    /Importing a module script failed/i.test(msg)
  );
}

const CHUNK_RELOAD_SENTINEL = 'bizarre:chunk-reload-attempted';

/**
 * Page-level error boundary that catches render errors in route subtrees
 * and shows a friendly recovery card instead of a blank screen. Also
 * auto-reloads once per session on stale-chunk errors (deploy rotation).
 */
export class PageErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  // @audit-fixed: previously the boundary swallowed render errors with no log
  // at all, making prod debugging impossible. componentDidCatch fires after
  // getDerivedStateFromError and is the React-recommended hook for reporting.
  componentDidCatch(error: Error, info: ErrorInfo): void {
    // eslint-disable-next-line no-console
    console.error('PageErrorBoundary caught:', error, info.componentStack);
    // WEB-FI-022: forward to global error reporter (Sentry/Datadog) when
    // production deploys assign window.__bizarrecrm_reportError in main.tsx.
    // Skip for chunk-load errors since those are deploy-rotation false alarms
    // and the auto-reload below handles them.
    if (!isChunkLoadError(error)) {
      try {
        const w = window as unknown as { __bizarrecrm_reportError?: (e: Error, ctx: unknown) => void };
        w.__bizarrecrm_reportError?.(error, { boundary: 'PageErrorBoundary', componentStack: info.componentStack });
      } catch {
        // reporter threw — swallow so the auto-reload path below still runs
      }
    }

    // Stale lazy-chunk after deploy: auto-reload ONCE per (url, recent
    // window). Sentinel stores `{ ts, url }` so two independent conditions
    // must be true to block a retry: same URL AND recent timestamp.
    //
    // SCAN-1184: the previous implementation cleared the sentinel on
    // every `componentDidMount`, which defeated the loop guard — the
    // root shell's boundary mounts OK after every reload, wiping the
    // sentinel, so a genuinely-404'd chunk would loop forever. Now we
    // don't clear on mount at all; the sentinel ages out by timestamp
    // (30s grace window) so a stale-deploy retry has room to succeed
    // but a chunk that's still 404 after the reload falls through to
    // the manual card as intended.
    if (isChunkLoadError(error)) {
      try {
        const raw = sessionStorage.getItem(CHUNK_RELOAD_SENTINEL);
        const now = Date.now();
        // WEB-FD-023: previously keyed on `window.location.href`, which
        // includes the search/hash fragments. A page that errors at
        // `/tickets?status=open` then redirects to `/tickets?status=closed`
        // (or just toggles a hash) would each get a fresh "first reload"
        // pass and could loop indefinitely. Strip query+hash so the loop
        // guard is by pathname only — chunk URLs do not depend on them.
        const url = window.location.pathname;
        let alreadyTriedForThisUrl = false;
        if (raw) {
          try {
            const parsed = JSON.parse(raw) as { ts?: number; url?: string };
            if (
              parsed &&
              typeof parsed.ts === 'number' &&
              parsed.url === url &&
              now - parsed.ts < 30_000
            ) {
              alreadyTriedForThisUrl = true;
            }
          } catch {
            // Old format — pretend no prior attempt, will overwrite below.
          }
        }
        if (!alreadyTriedForThisUrl) {
          sessionStorage.setItem(
            CHUNK_RELOAD_SENTINEL,
            JSON.stringify({ ts: now, url }),
          );
          // eslint-disable-next-line no-console
          console.warn('[PageErrorBoundary] stale chunk detected — auto-reloading once');
          window.location.reload();
        }
      } catch {
        // sessionStorage disabled / privacy mode — fall through to manual card.
      }
    }
  }

  private handleReload = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex items-center justify-center min-h-[50vh] p-6">
          <div className="w-full max-w-md rounded-2xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-8 text-center shadow-lg">
            <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/30">
              <AlertCircle className="h-7 w-7 text-red-600 dark:text-red-400" />
            </div>
            <h2 className="text-lg font-bold text-surface-900 dark:text-surface-100 mb-2">
              Something went wrong
            </h2>
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-6">
              An unexpected error occurred while rendering this page. You can try
              reloading the section or go back to the dashboard.
            </p>
            <div className="flex items-center justify-center gap-3">
              <button
                onClick={this.handleReload}
                className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 hover:bg-primary-700 transition-colors"
              >
                <RotateCcw className="h-4 w-4" />
                Reload
              </button>
              {/* @audit-fixed: was a plain `<a href="/">` which forces a full
                  page reload (drops React state, re-runs auth bootstrap, kills
                  any in-flight queries). Use react-router Link to keep SPA
                  navigation and let the boundary reset cleanly. */}
              <Link
                to="/"
                onClick={this.handleReload}
                className="inline-flex items-center gap-2 rounded-lg border border-surface-200 dark:border-surface-700 px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
              >
                Dashboard
              </Link>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
