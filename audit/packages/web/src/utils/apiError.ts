/**
 * Small helpers for surfacing server error envelopes to the user.
 *
 * The server emits every 4xx/5xx JSON response in the shape:
 *   { success: false, code: 'ERR_*', message, request_id }
 *
 * These helpers pull `code` + `request_id` out of any axios / fetch error
 * shape our codebase actually throws, and produce either a human-readable
 * toast line or structured fields for UIs that want to render them
 * separately (e.g. inline error panels with a "copy ref" button).
 */

export interface ApiErrorFields {
  /** Stable ERR_* identifier from the server, if present. */
  code: string | null;
  /** Server-supplied correlation id — matches an X-Request-Id log entry. */
  requestId: string | null;
  /** Human-readable message. Fallback string when the server didn't set one. */
  message: string;
  /** Raw HTTP status (e.g. 403). `null` for network / client-side errors. */
  status: number | null;
}

interface AxiosLikeError {
  isAxiosError?: boolean;
  message?: string;
  response?: {
    status?: number;
    headers?: Record<string, string | undefined>;
    data?: unknown;
  };
  config?: unknown;
}

/**
 * Accepts any thrown error and returns the structured fields safe to render.
 * Unknown shapes fall back to a generic message — never throws.
 */
export function extractApiError(err: unknown): ApiErrorFields {
  if (!err) {
    return { code: null, requestId: null, message: 'Unknown error', status: null };
  }

  const axios = err as AxiosLikeError;
  const data = axios.response?.data as
    | { code?: unknown; request_id?: unknown; requestId?: unknown; message?: unknown }
    | undefined
    | null;

  const code = typeof data?.code === 'string' ? data.code : null;
  // Server uses snake_case; accept camelCase too as defence against a stray client path.
  const requestId =
    (typeof data?.request_id === 'string' && data.request_id) ||
    (typeof data?.requestId === 'string' && data.requestId) ||
    (typeof axios.response?.headers?.['x-request-id'] === 'string'
      ? (axios.response.headers['x-request-id'] as string)
      : null);
  const message =
    (typeof data?.message === 'string' && data.message) ||
    (err instanceof Error ? err.message : '') ||
    'Request failed';
  const status = typeof axios.response?.status === 'number' ? axios.response.status : null;

  return { code, requestId: requestId || null, message, status };
}

/**
 * WEB-FJ-019: redact email-shaped substrings from a string before it is
 * rendered to an unauthenticated surface (login / signup / portal). Server
 * validation messages occasionally echo the submitted email back ("An
 * account already exists for serega@example.com"), and on a public landing
 * page that's a shoulder-surfing / screenshot leak. We replace the local
 * part with `***` and keep the domain as a hint that the field was the
 * problem field. Conservative regex: only matches a "looks like a real
 * email" pattern with at least one dot in the domain.
 */
export function redactEmails(input: string): string {
  if (!input) return input;
  return input.replace(
    /([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/g,
    '***@$2',
  );
}

/**
 * Format an error for a single-line toast. Appends "(ERR_X · ref abc12…)"
 * when the server provided them so a support ticket can trace the exact
 * log line. Short request-id prefix keeps toasts readable without trimming
 * the underlying full id from `extractApiError()` if a UI needs it.
 *
 * WEB-FJ-019: callers rendering on unauthenticated surfaces should pass the
 * result through `redactEmails()` — this fn does NOT auto-redact because
 * the same helper is used for staff-side toasts where echoing the email
 * the user typed is helpful.
 */
export function formatApiError(err: unknown): string {
  const f = extractApiError(err);
  const suffixParts: string[] = [];
  if (f.code) suffixParts.push(f.code);
  if (f.requestId) suffixParts.push(`ref ${f.requestId.slice(0, 8)}`);
  if (suffixParts.length === 0) return f.message;
  return `${f.message} (${suffixParts.join(' · ')})`;
}
