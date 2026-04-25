import { Link } from 'react-router-dom';
import { extractApiError } from '../../utils/apiError';

/**
 * WEB-FE-021 (Fixer-C12 2026-04-25): the four boot/route-fallback screens
 * (`LoadingScreen`, `PageLoader`, `NotFoundPage`, `SetupFailedScreen`) used to
 * live inside `App.tsx` as inline function declarations. That bloated the
 * non-lazy router root chunk and meant a typo in any of them re-rendered the
 * whole router tree. Hoisted to `components/shared/` so the chunk-split
 * boundary stays at App.tsx and these can evolve independently.
 */

export function LoadingScreen() {
  return (
    <div className="flex h-screen items-center justify-center bg-white dark:bg-surface-950">
      <div className="flex flex-col items-center gap-4">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
        <p className="text-sm text-surface-500">Loading...</p>
      </div>
    </div>
  );
}

export function PageLoader() {
  return (
    <div className="flex items-center justify-center h-[50vh]">
      <div className="h-8 w-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
    </div>
  );
}

export function NotFoundPage() {
  // Fixer-WW (WEB-FE-022): swap raw `text-gray-*` for surface tokens with dark
  // partners so the 404 doesn't render as a white-on-dark eyesore. Primary
  // button left as-is until brand-surface-ramp swap (FE-007) lands.
  return (
    <div className="flex flex-col items-center justify-center h-[60vh] text-center">
      <h1 className="text-4xl font-bold text-surface-800 dark:text-surface-100 mb-2">404</h1>
      <p className="text-lg text-surface-600 dark:text-surface-400 mb-6">Page not found</p>
      <Link
        to="/"
        className="px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors"
      >
        Back to Dashboard
      </Link>
    </div>
  );
}

/**
 * Shown when the mount-time /settings/setup-status query fails. Replaces the
 * old silent `<Navigate to="/login">` which caused an infinite login<->loading
 * loop when the failure was persistent (origin guard, tenant-context, rate
 * limit, offline server). Surface the exact server code + request id so the
 * user can send a support ticket with a traceable reference instead of a
 * screenshot of a blank loading spinner.
 */
export function SetupFailedScreen({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const { code, requestId, message, status } = extractApiError(error);
  return (
    <div className="flex h-screen items-center justify-center bg-white dark:bg-surface-950 px-4">
      <div className="max-w-md w-full flex flex-col items-start gap-4 p-6 rounded-lg border border-surface-200 dark:border-surface-800 bg-surface-50 dark:bg-surface-900">
        <div>
          <h1 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Unable to load the app</h1>
          <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">{message}</p>
        </div>
        <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs font-mono text-surface-500 dark:text-surface-400">
          {status !== null && (
            <>
              <dt className="text-surface-400">status</dt>
              <dd>{status}</dd>
            </>
          )}
          {code && (
            <>
              <dt className="text-surface-400">code</dt>
              <dd>{code}</dd>
            </>
          )}
          {requestId && (
            <>
              <dt className="text-surface-400">ref</dt>
              <dd className="break-all">{requestId}</dd>
            </>
          )}
        </dl>
        <div className="flex items-center gap-2 mt-2">
          <button
            onClick={onRetry}
            className="px-3 py-1.5 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded"
          >
            Retry
          </button>
          <button
            onClick={() => { window.location.href = '/login'; }}
            className="px-3 py-1.5 text-sm text-surface-700 dark:text-surface-300 border border-surface-300 dark:border-surface-700 rounded hover:bg-surface-100 dark:hover:bg-surface-800"
          >
            Sign out
          </button>
        </div>
      </div>
    </div>
  );
}
