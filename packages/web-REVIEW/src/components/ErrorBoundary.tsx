import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props { children: ReactNode; }
interface State { hasError: boolean; error: Error | null; }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  // @audit-fixed: previously only `getDerivedStateFromError` was implemented,
  // so render errors were silently swallowed with no console output. Adding
  // `componentDidCatch` ensures we at least log the stack to dev tools.
  // WEB-FI-022: also forward to a global error-reporter hook if configured
  // (Sentry/Datadog/etc.) — wired via window.__bizarrecrm_reportError so the
  // boundary stays free of a hard SDK dependency. Production deploys can
  // assign this in main.tsx after `import * as Sentry`. Without a hook, prod
  // render crashes are invisible without a user-supplied screenshot.
  componentDidCatch(error: Error, info: ErrorInfo): void {
    // eslint-disable-next-line no-console
    console.error('ErrorBoundary caught:', error, info.componentStack);
    try {
      const w = window as unknown as { __bizarrecrm_reportError?: (e: Error, ctx: unknown) => void };
      w.__bizarrecrm_reportError?.(error, { boundary: 'ErrorBoundary', componentStack: info.componentStack });
    } catch {
      // reporter threw — swallow so the boundary still renders the fallback UI
    }
  }

  render() {
    if (this.state.hasError) {
      // WEB-FI-021 (Fixer-C8 2026-04-25): differentiate from the root
      // boundary in main.tsx by offering a "Sign out" affordance alongside
      // Reload — this boundary wraps the auth shell, so the user is logged
      // in by the time it can render. A render error caused by stale auth
      // state is escapable here without a manual cookie wipe.
      return (
        <div className="flex items-center justify-center min-h-screen p-8">
          <div className="text-center max-w-md">
            <h1 className="text-xl font-bold text-surface-900 dark:text-surface-100 mb-2">Something went wrong</h1>
            <p className="text-sm text-surface-500 mb-4">This page encountered an error. Your data is safe.</p>
            <div className="flex gap-2 justify-center">
              <button onClick={() => window.location.reload()}
                className="px-4 py-2 bg-primary-600 text-primary-950 rounded-lg text-sm font-medium hover:bg-primary-700">
                Reload Page
              </button>
              <button
                onClick={() => {
                  try { window.dispatchEvent(new Event('bizarre-crm:auth-cleared')); } catch { /* best-effort */ }
                  window.location.assign('/login');
                }}
                className="px-4 py-2 bg-surface-200 dark:bg-surface-800 text-surface-900 dark:text-surface-100 rounded-lg text-sm font-medium hover:bg-surface-300 dark:hover:bg-surface-700">
                Sign out
              </button>
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
