import { Component, StrictMode } from 'react';
import type { ReactNode, ErrorInfo } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { HashRouter } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import App from './App';
import './styles/globals.css';

// ─── Global Error Boundary ─────────────��──────────────────────────
// Catches render errors at the top level so the whole app doesn't white-screen.

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<{ children: ReactNode }, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('[ErrorBoundary] Uncaught render error:', error, info.componentStack);
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <div className="flex flex-col items-center justify-center min-h-screen p-8 text-center bg-surface-950">
          <div className="text-5xl mb-4">&#9888;</div>
          <h1 className="text-xl font-bold text-surface-100 mb-2">
            Something went wrong
          </h1>
          <p className="text-surface-400 max-w-md mb-6">
            The dashboard encountered an unexpected error. The CRM server is NOT affected.
          </p>
          {this.state.error && (
            <pre className="text-xs text-red-400 bg-red-950/50 p-3 rounded-lg max-w-lg overflow-auto mb-6 text-left border border-red-900/50">
              {this.state.error.message}
            </pre>
          )}
          <button
            onClick={() => window.location.reload()}
            className="px-6 py-2.5 text-sm font-semibold text-white bg-accent-600 rounded-lg hover:bg-accent-700 transition-colors"
          >
            Reload Dashboard
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

// ─── App Bootstrap ───────��────────────────────────────────────────

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 10_000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <HashRouter>
          <App />
          <Toaster
            position="top-right"
            toastOptions={{
              className: '!bg-surface-800 !text-surface-100 !shadow-lg !border !border-surface-700',
              duration: 4000,
            }}
          />
        </HashRouter>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>
);
