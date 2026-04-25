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
  componentDidCatch(error: Error, info: ErrorInfo): void {
    // eslint-disable-next-line no-console
    console.error('ErrorBoundary caught:', error, info.componentStack);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex items-center justify-center min-h-screen p-8">
          <div className="text-center max-w-md">
            <h1 className="text-xl font-bold text-surface-900 dark:text-surface-100 mb-2">Something went wrong</h1>
            <p className="text-sm text-surface-500 mb-4">This page encountered an error. Your data is safe.</p>
            <button onClick={() => window.location.reload()}
              className="px-4 py-2 bg-primary-600 text-white rounded-lg text-sm font-medium hover:bg-primary-700">
              Reload Page
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
