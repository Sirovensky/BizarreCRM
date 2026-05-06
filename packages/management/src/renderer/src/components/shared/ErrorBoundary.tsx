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
        // DASH-ELEC-274: role="alert" ensures AT immediately announces the
        // section error without waiting for polling — mirrors the global
        // ErrorBoundary in main.tsx which was already patched.
        <div role="alert" className="flex flex-col items-center justify-center p-8 rounded-lg border border-red-900/50 bg-red-950/20">
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

type ShellSection = 'banner' | 'header' | 'sidebar' | 'main' | 'footer';

interface ShellSectionProps {
  children: ReactNode;
  section: ShellSection;
  fallbackTitle?: string;
  fallbackId?: string;
  fallbackTabIndex?: number;
  resetKey?: string | number | boolean | null;
}

const SHELL_SECTION_TITLES: Record<ShellSection, string> = {
  banner: 'Dashboard banner unavailable',
  header: 'Header unavailable',
  sidebar: 'Sidebar unavailable',
  main: 'Main content unavailable',
  footer: 'Status footer unavailable',
};

const SHELL_SECTION_CLASSES: Record<ShellSection, string> = {
  banner: 'flex items-center justify-between gap-3 px-4 py-2 border-b border-red-900/50 bg-red-950/30 text-xs',
  header: 'h-[var(--header-height)] flex items-center justify-between gap-3 px-4 border-b border-red-900/50 bg-surface-950 text-xs',
  sidebar: 'flex flex-col gap-3 w-[var(--sidebar-width)] border-r border-red-900/50 bg-surface-950 p-3 text-xs',
  main: 'flex-1 overflow-y-auto p-3 lg:p-5 xl:p-6 outline-none',
  footer: 'flex items-center justify-between gap-3 px-3 py-1 border-t border-red-900/50 bg-surface-950 text-[10px]',
};

export class ShellSectionErrorBoundary extends Component<ShellSectionProps, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error(`[ShellSectionErrorBoundary:${this.props.section}]`, error, info.componentStack);
  }

  componentDidUpdate(prevProps: ShellSectionProps): void {
    if (this.state.hasError && prevProps.resetKey !== this.props.resetKey) {
      this.setState({ hasError: false, error: null });
    }
  }

  handleRetry = (): void => {
    this.setState({ hasError: false, error: null });
  };

  render(): ReactNode {
    if (!this.state.hasError) {
      return this.props.children;
    }

    const title = this.props.fallbackTitle ?? SHELL_SECTION_TITLES[this.props.section];
    const message = import.meta.env.DEV && this.state.error
      ? this.state.error.message
      : 'Try retrying this section.';

    return (
      <div
        id={this.props.fallbackId}
        role="alert"
        tabIndex={this.props.fallbackTabIndex}
        className={SHELL_SECTION_CLASSES[this.props.section]}
      >
        <div className="flex min-w-0 items-center gap-2 text-red-300">
          <AlertTriangle className="w-4 h-4 flex-shrink-0 text-red-400" />
          <span className="font-semibold">{title}</span>
          <span className="truncate text-red-400">{message}</span>
        </div>
        <button
          onClick={this.handleRetry}
          className="flex flex-shrink-0 items-center gap-1 rounded border border-red-900/60 bg-red-950/30 px-2 py-1 font-medium text-red-200 transition-colors hover:bg-red-900/30"
        >
          <RefreshCw className="w-3 h-3" />
          Retry
        </button>
      </div>
    );
  }
}
