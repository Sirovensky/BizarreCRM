/**
 * Page-level error boundary — catches errors in individual sections
 * so the rest of the dashboard keeps working.
 */
import { Component } from 'react';
import type { ReactNode, ErrorInfo } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

interface Props {
  children: ReactNode;
  fallbackTitle?: string;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class PageErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('[PageErrorBoundary]', error, info.componentStack);
  }

  handleRetry = (): void => {
    this.setState({ hasError: false, error: null });
  };

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <div className="flex flex-col items-center justify-center p-8 rounded-lg border border-red-900/50 bg-red-950/20">
          <AlertTriangle className="w-8 h-8 text-red-400 mb-3" />
          <h3 className="text-sm font-semibold text-surface-200 mb-1">
            {this.props.fallbackTitle ?? 'This section encountered an error'}
          </h3>
          <p className="text-xs text-surface-500 mb-4 max-w-sm text-center">
            The CRM server is not affected. Try reloading this section.
          </p>
          {this.state.error && (
            <pre className="text-xs text-red-400 bg-surface-900 p-2 rounded max-w-md overflow-auto mb-4 text-left">
              {/* Expose the message only in dev builds — production hides it
                  to avoid leaking TLS fingerprint details, Zod parse internals,
                  or other server-side state (DASH-ELEC-115). */}
              {import.meta.env.DEV
                ? this.state.error.message
                : 'An internal error occurred. Please reload and try again.'}
            </pre>
          )}
          <button
            onClick={this.handleRetry}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-200 bg-surface-800 border border-surface-700 rounded-md hover:bg-surface-700 transition-colors"
          >
            <RefreshCw className="w-3 h-3" />
            Retry
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
