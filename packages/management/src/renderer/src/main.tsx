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

// @audit-fixed: previously this used `document.getElementById('root')!` —
// the non-null assertion would have produced a confusing "createRoot(null)"
// React error if the root element ever went missing (e.g. a future build
// step that strips the placeholder div from `index.html`). The lookup now
// fails loudly with a dedicated error page injected directly into the
// document body so the user has *some* signal instead of a blank window.
const rootElement = document.getElementById('root');
if (!rootElement) {
  document.body.innerHTML =
    '<div style="font-family: system-ui, sans-serif; color: #fca5a5; ' +
    'background:#09090b; padding:32px; text-align:center;">' +
    '<h1 style="font-size:18px;">Dashboard failed to mount</h1>' +
    '<p style="margin-top:8px;font-size:12px;">' +
    'The root element was missing from index.html. Try reinstalling the ' +
    'BizarreCRM Management dashboard from setup.bat.' +
    '</p></div>';
  throw new Error('Dashboard root element not found');
}

createRoot(rootElement).render(
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
