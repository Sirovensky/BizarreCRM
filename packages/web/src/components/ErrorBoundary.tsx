import { Component, type ReactNode } from 'react';

interface Props { children: ReactNode; }
interface State { hasError: boolean; error: Error | null; }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex items-center justify-center min-h-screen p-8">
          <div className="text-center max-w-md">
            <h1 className="text-xl font-bold text-surface-900 dark:text-surface-100 mb-2">Something went wrong</h1>
            <p className="text-sm text-surface-500 mb-4">This page encountered an error. Your data is safe.</p>
            <button onClick={() => { this.setState({ hasError: false, error: null }); window.location.reload(); }}
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
