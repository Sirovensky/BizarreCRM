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

    // Stale lazy-chunk after deploy: auto-reload once. sessionStorage
    // sentinel prevents an infinite loop when chunks genuinely 404 (CDN
    // down, misconfigured hosting) — second hit falls through to the
    // manual card so the user can diagnose.
    if (isChunkLoadError(error)) {
      try {
        if (!sessionStorage.getItem(CHUNK_RELOAD_SENTINEL)) {
          sessionStorage.setItem(CHUNK_RELOAD_SENTINEL, String(Date.now()));
          // eslint-disable-next-line no-console
          console.warn('[PageErrorBoundary] stale chunk detected — auto-reloading once');
          window.location.reload();
        }
      } catch {
        // sessionStorage disabled / privacy mode — fall through to manual card.
      }
    }
  }

  componentDidMount(): void {
    // Clear the reload sentinel on successful mount. If the boundary
    // children rendered without error, the stale-chunk situation has
    // resolved and a future deploy is eligible to auto-reload again.
    try {
      sessionStorage.removeItem(CHUNK_RELOAD_SENTINEL);
    } catch {
      /* ignore */
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
                className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 transition-colors"
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
