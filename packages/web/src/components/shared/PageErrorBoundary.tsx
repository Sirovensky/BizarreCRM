import { Component, type ReactNode } from 'react';
import { AlertCircle, RotateCcw } from 'lucide-react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

/**
 * Page-level error boundary that catches render errors in route subtrees
 * and shows a friendly recovery card instead of a blank screen.
 */
export class PageErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
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
            {this.state.error && (
              <pre className="mb-4 max-h-24 overflow-auto rounded-lg bg-surface-100 dark:bg-surface-800 px-3 py-2 text-left text-xs text-surface-600 dark:text-surface-400">
                {this.state.error.message}
              </pre>
            )}
            <div className="flex items-center justify-center gap-3">
              <button
                onClick={this.handleReload}
                className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 transition-colors"
              >
                <RotateCcw className="h-4 w-4" />
                Reload
              </button>
              <a
                href="/"
                className="inline-flex items-center gap-2 rounded-lg border border-surface-200 dark:border-surface-700 px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
              >
                Dashboard
              </a>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
