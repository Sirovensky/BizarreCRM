import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { AlertCircle, LogOut, RotateCcw } from 'lucide-react';
import { Button } from './Button';

export type ErrorBoundaryVariant = 'root' | 'app' | 'page' | 'section';

export interface ErrorBoundaryFallbackProps {
  error: Error | null;
  variant: ErrorBoundaryVariant;
  reset: () => void;
  reload: () => void;
  signOut: () => void;
}

interface Props {
  children: ReactNode;
  variant?: ErrorBoundaryVariant;
  boundaryName?: string;
  autoReloadChunks?: boolean;
  fallback?: (props: ErrorBoundaryFallbackProps) => ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

/**
 * Detect "stale lazy-chunk after deploy" — Vite hashes every chunk filename,
 * so a tab holding pre-deploy HTML will 404 when React.lazy tries to fetch an
 * old chunk URL. The name gate avoids reloads on user-authored strings that
 * merely contain a matching phrase.
 */
export function isChunkLoadError(err: unknown): boolean {
  if (!err) return false;
  const name = (err as { name?: string }).name ?? '';
  const msg = (err as { message?: string }).message ?? '';
  const looksLikeChunkMessage =
    /Failed to fetch dynamically imported module/i.test(msg) ||
    /error loading dynamically imported module/i.test(msg) ||
    /Importing a module script failed/i.test(msg) ||
    /ChunkLoadError/i.test(msg);

  if (name === 'ChunkLoadError') return true;
  if (name === 'TypeError' && looksLikeChunkMessage) return true;
  return false;
}

export const CHUNK_RELOAD_SENTINEL = 'bizarre:chunk-reload-attempted';

export function clearChunkReloadSentinel(): void {
  try { sessionStorage.removeItem(CHUNK_RELOAD_SENTINEL); } catch { /* best-effort */ }
}

export function tryReloadForChunkError(logPrefix = '[ErrorBoundary]'): boolean {
  try {
    const raw = sessionStorage.getItem(CHUNK_RELOAD_SENTINEL);
    const now = Date.now();
    const url = window.location.pathname;
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as { ts?: number; url?: string };
        if (
          parsed &&
          typeof parsed.ts === 'number' &&
          parsed.url === url &&
          now - parsed.ts < 30_000
        ) {
          return false;
        }
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn(`${logPrefix} chunk-reload sentinel payload corrupt - overwriting`, err);
      }
    }
    sessionStorage.setItem(CHUNK_RELOAD_SENTINEL, JSON.stringify({ ts: now, url }));
    // eslint-disable-next-line no-console
    console.warn(`${logPrefix} stale chunk detected - auto-reloading once`);
    window.location.reload();
    return true;
  } catch (err) {
    // eslint-disable-next-line no-console
    console.warn(`${logPrefix} sessionStorage unavailable - chunk-reload sentinel skipped`, err);
    return false;
  }
}

function reportBoundaryError(
  error: Error,
  info: ErrorInfo,
  boundaryName: string,
  skipCrashSink: boolean,
): void {
  // eslint-disable-next-line no-console
  console.error(`${boundaryName} caught:`, error, info.componentStack);
  if (skipCrashSink) return;

  try {
    const w = window as unknown as { __bizarrecrm_reportError?: (e: Error, ctx: unknown) => void };
    w.__bizarrecrm_reportError?.(error, { boundary: boundaryName, componentStack: info.componentStack });
  } catch {
    // reporter threw - swallow so the boundary still renders fallback UI
  }

  try {
    const g = globalThis as {
      __bizarreReportCrash?: (p: { message: string; stack?: string; componentStack?: string }) => void;
    };
    g.__bizarreReportCrash?.({
      message: error?.message ?? 'unknown render error',
      stack: error?.stack,
      componentStack: info?.componentStack ?? undefined,
    });
  } catch {
    // best-effort
  }
}

function DefaultFallback({
  variant,
  reset,
  reload,
  signOut,
}: ErrorBoundaryFallbackProps) {
  if (variant === 'section') {
    return (
      <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm dark:border-red-900/50 dark:bg-red-950/30">
        <div className="flex items-start gap-3">
          <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-red-600 dark:text-red-400" />
          <div className="min-w-0 flex-1">
            <h2 className="font-semibold text-red-900 dark:text-red-100">This section could not render</h2>
            <p className="mt-1 text-red-700 dark:text-red-300">
              The rest of the page is still available.
            </p>
            <Button
              onClick={reset}
              size="sm"
              variant="secondary"
              className="mt-3"
              leadingIcon={<RotateCcw className="h-4 w-4" />}
            >
              Retry
            </Button>
          </div>
        </div>
      </div>
    );
  }

  if (variant === 'root') {
    return (
      <div role="alert" className="flex min-h-screen flex-col items-center justify-center bg-surface-50 p-8 text-center font-sans dark:bg-surface-950">
        <div className="mb-4 text-5xl" aria-hidden="true">&#9888;</div>
        <h1 className="mb-2 text-2xl font-bold text-surface-900 dark:text-surface-50">
          Something went wrong
        </h1>
        <p className="mb-6 max-w-lg text-surface-500 dark:text-surface-400">
          An unexpected error occurred. Please reload the page to try again.
        </p>
        <Button onClick={reload} size="md">Reload Page</Button>
      </div>
    );
  }

  if (variant === 'app') {
    return (
      <div role="alert" className="flex min-h-screen items-center justify-center p-8">
        <div className="max-w-md text-center">
          <h1 className="mb-2 text-xl font-bold text-surface-900 dark:text-surface-100">
            Something went wrong
          </h1>
          <p className="mb-4 text-sm text-surface-500">
            This page encountered an error. Your data is safe.
          </p>
          <div className="flex justify-center gap-2">
            <Button onClick={reload} size="md" leadingIcon={<RotateCcw className="h-4 w-4" />}>
              Reload Page
            </Button>
            <Button onClick={signOut} size="md" variant="secondary" leadingIcon={<LogOut className="h-4 w-4" />}>
              Sign out
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div role="alert" className="flex min-h-[50vh] items-center justify-center p-6">
      <div className="w-full max-w-md rounded-2xl border border-surface-200 bg-white p-8 text-center shadow-lg dark:border-surface-700 dark:bg-surface-900">
        <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/30">
          <AlertCircle className="h-7 w-7 text-red-600 dark:text-red-400" />
        </div>
        <h2 className="mb-2 text-lg font-bold text-surface-900 dark:text-surface-100">
          Something went wrong
        </h2>
        <p className="mb-6 text-sm text-surface-500 dark:text-surface-400">
          An unexpected error occurred while rendering this page. You can try
          reloading the section or go back to the dashboard.
        </p>
        <div className="flex items-center justify-center gap-3">
          <Button
            onClick={reset}
            size="md"
            leadingIcon={<RotateCcw className="h-4 w-4" />}
          >
            Reload
          </Button>
          <Link to="/" onClick={reset} className="btn btn-md btn-secondary">
            Dashboard
          </Link>
        </div>
      </div>
    </div>
  );
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    const boundaryName = this.props.boundaryName ?? 'ErrorBoundary';
    const chunkError = isChunkLoadError(error);
    reportBoundaryError(error, info, boundaryName, chunkError);

    if (this.props.autoReloadChunks && chunkError) {
      tryReloadForChunkError(`[${boundaryName}]`);
    }
  }

  private reset = () => {
    clearChunkReloadSentinel();
    this.setState({ hasError: false, error: null });
  };

  private reload = () => {
    clearChunkReloadSentinel();
    window.location.reload();
  };

  private signOut = () => {
    try { window.dispatchEvent(new Event('bizarre-crm:auth-cleared')); } catch { /* best-effort */ }
    window.location.assign('/login');
  };

  render() {
    if (this.state.hasError) {
      const variant = this.props.variant ?? 'section';
      const fallbackProps: ErrorBoundaryFallbackProps = {
        error: this.state.error,
        variant,
        reset: this.reset,
        reload: this.reload,
        signOut: this.signOut,
      };
      return this.props.fallback
        ? this.props.fallback(fallbackProps)
        : <DefaultFallback {...fallbackProps} />;
    }

    return this.props.children;
  }
}

export function PageErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary variant="page" boundaryName="PageErrorBoundary" autoReloadChunks>
      {children}
    </ErrorBoundary>
  );
}
