/**
 * Dashboard mirror of the web SPA's apiError helper. Extracts ERR_* + request_id
 * from the ApiResponse envelope (and any caught thrown error) so dashboard
 * toasts show "Failed to load (ERR_AUTH_SESSION_EXPIRED · ref abc12…)" instead
 * of a bare "Failed to load". The short request-id prefix keeps toasts
 * readable; full id is available via `extractApiError().requestId` for UIs
 * that expose a "copy ref" button.
 */
import type { ApiResponse } from '@/api/bridge';

export interface ApiErrorFields {
  code: string | null;
  requestId: string | null;
  message: string;
  /** HTTP status code from the IPC envelope (DASH-ELEC-060), if available. */
  status: number | null;
}

type ApiOrError = ApiResponse<unknown> | { message?: unknown; errorCode?: unknown; requestId?: unknown } | Error | unknown;

export function extractApiError(input: ApiOrError): ApiErrorFields {
  if (!input) return { code: null, requestId: null, status: null, message: 'Unknown error' };

  if (typeof input === 'object') {
    // ApiResponse envelope path.
    const env = input as ApiResponse<unknown>;
    if (env && typeof env.success === 'boolean') {
      return {
        code: typeof env.code === 'string' ? env.code : null,
        requestId: typeof env.request_id === 'string' ? env.request_id : null,
        status: typeof env.status === 'number' ? env.status : null,
        message: typeof env.message === 'string' && env.message ? env.message : 'Request failed',
      };
    }
    // Thrown-Error path.
    const e = input as { message?: unknown; errorCode?: unknown; requestId?: unknown };
    return {
      code: typeof e.errorCode === 'string' ? e.errorCode : null,
      requestId: typeof e.requestId === 'string' ? e.requestId : null,
      status: null,
      message: typeof e.message === 'string' && e.message ? e.message : 'Request failed',
    };
  }
  return { code: null, requestId: null, status: null, message: String(input) };
}

export function formatApiError(input: ApiOrError): string {
  const f = extractApiError(input);
  const parts: string[] = [];
  // DASH-ELEC-277: include the HTTP status so operators can distinguish 4xx
  // client errors from 5xx server errors at a glance.
  if (f.status !== null) parts.push(`[${f.status}]`);
  if (f.code) parts.push(f.code);
  if (f.requestId) parts.push(`ref ${f.requestId.slice(0, 8)}`);
  if (parts.length === 0) return f.message;
  return `${f.message} (${parts.join(' · ')})`;
}
