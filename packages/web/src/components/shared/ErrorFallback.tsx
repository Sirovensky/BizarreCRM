import { useNavigate } from 'react-router-dom';
import { AlertCircle, LogOut, RotateCcw } from 'lucide-react';
import { Button } from './Button';
import type { ErrorBoundaryFallbackProps } from './PageErrorBoundary';

/**
 * Default fallback UI rendered by ErrorBoundary when no custom `fallback` prop
 * is provided. Extracted here so it can be imported and reused independently.
 */
export function ErrorFallback({
  variant,
  reset,
  reload,
  signOut,
}: ErrorBoundaryFallbackProps) {
  const navigate = useNavigate();
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
          <Button
            onClick={() => { reset(); navigate('/'); }}
            size="md"
            variant="secondary"
          >
            Dashboard
          </Button>
        </div>
      </div>
    </div>
  );
}
