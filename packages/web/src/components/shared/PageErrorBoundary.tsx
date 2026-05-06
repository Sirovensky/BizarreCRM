import { Component, type ErrorInfo, type ReactNode } from 'react';
import { ErrorFallback } from './ErrorFallback';

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
        : <ErrorFallback {...fallbackProps} />;
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
