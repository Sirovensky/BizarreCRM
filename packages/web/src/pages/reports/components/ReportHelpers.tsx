import type { ComponentType, ReactNode } from 'react';
import { Loader2, AlertCircle, Package } from 'lucide-react';

// WEB-UIUX-930: added optional tooltip prop so cards can disclose computation details
export function SummaryCard({ label, value, icon: Icon, color, bg, tooltip }: {
  label: string; value: string; icon: ComponentType<{ className?: string }>; color: string; bg: string; tooltip?: string;
}) {
  return (
    <div className="card flex items-center gap-4 p-5">
      <div className={`flex items-center justify-center h-12 w-12 rounded-xl ${bg}`}>
        <Icon className={`h-6 w-6 ${color}`} />
      </div>
      <div>
        <p className="text-sm text-surface-500 dark:text-surface-400">
          {label}
          {tooltip && (
            <span
              title={tooltip}
              aria-label={tooltip}
              className="ml-1 cursor-help text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 select-none"
            >
              &#9432;
            </span>
          )}
        </p>
        <p className="text-2xl font-bold text-surface-900 dark:text-surface-100">{value}</p>
      </div>
    </div>
  );
}

export function LoadingState() {
  return (
    <div className="flex items-center justify-center py-20">
      <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      <span className="ml-3 text-surface-500">Loading report data...</span>
    </div>
  );
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20">
      <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
      <p className="text-sm text-surface-500">{message}</p>
    </div>
  );
}

function getReportErrorMessage(error: unknown, fallback: string): string {
  const apiError = error as {
    response?: { data?: { message?: unknown; error?: unknown } };
    message?: unknown;
  };
  const message =
    apiError.response?.data?.message ??
    apiError.response?.data?.error ??
    apiError.message;

  return typeof message === 'string' && message.trim().length > 0 ? message : fallback;
}

export function getReportQueryState<TData>({
  data,
  error,
  isError,
  isLoading,
  fallbackError,
}: {
  data: TData | null | undefined;
  error: unknown;
  isError: boolean;
  isLoading: boolean;
  fallbackError: string;
}): { status: 'loading-or-error'; view: ReactNode } | { status: 'ready'; data: TData } {
  if (isLoading) return { status: 'loading-or-error', view: <LoadingState /> };
  if (isError || data == null) {
    return { status: 'loading-or-error', view: <ErrorState message={getReportErrorMessage(error, fallbackError)} /> };
  }

  return { status: 'ready', data };
}

export function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16">
      <Package className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-3" />
      <p className="text-sm text-surface-400 dark:text-surface-500">{message}</p>
    </div>
  );
}
