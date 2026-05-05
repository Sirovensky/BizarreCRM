/**
 * Centralised error-code registry for traceable API failures.
 *
 * Every 4xx / 5xx JSON response in the CRM should carry one of these codes
 * in the body as `{ success: false, code, message, request_id }`. Codes are
 * stable identifiers safe to surface in client-side logs, support tickets,
 * or user-visible "error: ERR_XXX (ref: req-abc123)" hints — much easier to
 * trace than free-form messages that vary between middlewares.
 *
 * Format: `ERR_<AREA>_<REASON>`, SCREAMING_SNAKE_CASE, under 64 chars.
 * Keep codes grep-friendly — each one should appear in exactly one call site
 * so the log aggregator can pinpoint the source by code alone.
 *
 * Grouping convention:
 *   AUTH_*   — authentication / token / session errors (401)
 *   PERM_*   — authorisation / role / feature-gate errors (403)
 *   ORIGIN_* — CORS / Origin / CSRF guard rejects (403)
 *   INPUT_*  — request body / query / param validation failures (400)
 *   RATE_*   — rate limiter rejects (429)
 *   TENANT_* — tenant resolver / subdomain / status errors (404 / 503)
 *   ROUTE_*  — route-disabled / service-down rejects (503)
 *   INT_*    — internal server errors (500)
 */
export const ERROR_CODES = {
  // ── Origin / CSRF ────────────────────────────────────────────────
  /** Missing Origin header on state-changing API request. */
  ERR_ORIGIN_MISSING: 'ERR_ORIGIN_MISSING',
  /** Origin header present but not on the CORS allow-list. */
  ERR_ORIGIN_NOT_ALLOWED: 'ERR_ORIGIN_NOT_ALLOWED',
  /** CSRF double-submit cookie/header mismatch on /auth/refresh. */
  ERR_CSRF_MISMATCH: 'ERR_CSRF_MISMATCH',
  /** Non-JSON content-type on state-changing request (CSRF via HTML form). */
  ERR_CONTENT_TYPE: 'ERR_CONTENT_TYPE',

  // ── Auth (401) ───────────────────────────────────────────────────
  ERR_AUTH_NO_TOKEN: 'ERR_AUTH_NO_TOKEN',
  ERR_AUTH_INVALID_TOKEN: 'ERR_AUTH_INVALID_TOKEN',
  ERR_AUTH_INVALID_TOKEN_TYPE: 'ERR_AUTH_INVALID_TOKEN_TYPE',
  ERR_AUTH_INVALID_PAYLOAD: 'ERR_AUTH_INVALID_PAYLOAD',
  ERR_AUTH_TENANT_REQUIRED: 'ERR_AUTH_TENANT_REQUIRED',
  ERR_AUTH_TENANT_MISMATCH: 'ERR_AUTH_TENANT_MISMATCH',
  ERR_AUTH_SESSION_EXPIRED: 'ERR_AUTH_SESSION_EXPIRED',
  ERR_AUTH_SESSION_IDLE: 'ERR_AUTH_SESSION_IDLE',
  ERR_AUTH_USER_NOT_FOUND: 'ERR_AUTH_USER_NOT_FOUND',
  /** Wrong username/password combination. */
  ERR_AUTH_INVALID_CREDENTIALS: 'ERR_AUTH_INVALID_CREDENTIALS',
  /** Multi-step challenge (2FA setup / PIN set / password reset) expired. */
  ERR_AUTH_CHALLENGE_EXPIRED: 'ERR_AUTH_CHALLENGE_EXPIRED',
  /** Invalid TOTP code during verify. */
  ERR_AUTH_INVALID_TOTP: 'ERR_AUTH_INVALID_TOTP',
  /** Refresh token is missing or expired. */
  ERR_AUTH_REFRESH_MISSING: 'ERR_AUTH_REFRESH_MISSING',
  /** Setup/activation link was invalid or already consumed. */
  ERR_AUTH_SETUP_LINK_INVALID: 'ERR_AUTH_SETUP_LINK_INVALID',
  /** Shop already completed first-run setup. */
  ERR_AUTH_ALREADY_SETUP: 'ERR_AUTH_ALREADY_SETUP',

  // ── Permissions (403) ────────────────────────────────────────────
  ERR_PERM_INSUFFICIENT: 'ERR_PERM_INSUFFICIENT',
  ERR_PERM_ADMIN_REQUIRED: 'ERR_PERM_ADMIN_REQUIRED',
  ERR_PERM_FEATURE_GATED: 'ERR_PERM_FEATURE_GATED',
  ERR_PERM_STEP_UP_REQUIRED: 'ERR_PERM_STEP_UP_REQUIRED',
  ERR_PERM_STEP_UP_NO_2FA: 'ERR_PERM_STEP_UP_NO_2FA',

  // ── Input (400) ──────────────────────────────────────────────────
  ERR_INPUT_INVALID: 'ERR_INPUT_INVALID',
  ERR_INPUT_VALIDATION: 'ERR_INPUT_VALIDATION',
  ERR_INPUT_JSON_MALFORMED: 'ERR_INPUT_JSON_MALFORMED',
  ERR_INPUT_BODY_REQUIRED: 'ERR_INPUT_BODY_REQUIRED',

  // ── Rate limiting (429) ──────────────────────────────────────────
  ERR_RATE_API: 'ERR_RATE_API',
  ERR_RATE_WEBHOOK: 'ERR_RATE_WEBHOOK',
  ERR_RATE_AUTH: 'ERR_RATE_AUTH',

  // ── Tenant (404 / 503) ───────────────────────────────────────────
  ERR_TENANT_NOT_FOUND: 'ERR_TENANT_NOT_FOUND',
  ERR_TENANT_HOST_INVALID: 'ERR_TENANT_HOST_INVALID',
  ERR_TENANT_BARE_DOMAIN: 'ERR_TENANT_BARE_DOMAIN',
  ERR_TENANT_PROVISIONING: 'ERR_TENANT_PROVISIONING',
  ERR_TENANT_DB_FAILED: 'ERR_TENANT_DB_FAILED',
  ERR_TENANT_CONTEXT_MISSING: 'ERR_TENANT_CONTEXT_MISSING',

  // ── Portal / customer-facing (401 / 404 / 409) ───────────────────
  /** Customer portal session expired or not provided. */
  ERR_PORTAL_SESSION_REQUIRED: 'ERR_PORTAL_SESSION_REQUIRED',
  /** Wrong phone + PIN / ticket-id + phone combination on portal lookup. */
  ERR_PORTAL_AUTH_FAILED: 'ERR_PORTAL_AUTH_FAILED',
  /** Portal account is guest-only; requires full-account upgrade for this action. */
  ERR_PORTAL_ACCOUNT_REQUIRED: 'ERR_PORTAL_ACCOUNT_REQUIRED',

  // ── Resource (404 / 409) — generic record-level errors ──────────
  /** Requested record does not exist (ticket / invoice / estimate / customer). */
  ERR_RESOURCE_NOT_FOUND: 'ERR_RESOURCE_NOT_FOUND',
  /** Operation conflicts with current resource state (already paid, already reviewed). */
  ERR_RESOURCE_CONFLICT: 'ERR_RESOURCE_CONFLICT',

  // ── Route / service (503) ────────────────────────────────────────
  ERR_ROUTE_DISABLED: 'ERR_ROUTE_DISABLED',
  ERR_SERVER_BUSY: 'ERR_SERVER_BUSY',

  // ── Internal (500) ───────────────────────────────────────────────
  ERR_INT_GENERIC: 'ERR_INT_GENERIC',
  ERR_INT_DB_UNAVAILABLE: 'ERR_INT_DB_UNAVAILABLE',
} as const;

export type ErrorCode = typeof ERROR_CODES[keyof typeof ERROR_CODES];

/** Strongly-typed error-body shape — use this when manually building error JSON. */
export interface ErrorBody {
  success: false;
  code: ErrorCode | string;
  message: string;
  request_id?: string | undefined;
  /** Optional extra fields — keep keys snake_case for API consistency. */
  [extra: string]: unknown;
}

/**
 * Build a standard error envelope. The request_id comes from the correlation
 * middleware (res.locals.requestId). Add to every 4xx/5xx response so support
 * can trace "error ERR_FOO (ref req-abc)" to a single log line instantly.
 */
export function errorBody(
  code: ErrorCode | string,
  message: string,
  requestId?: string,
  extra?: Record<string, unknown>,
): ErrorBody {
  return {
    success: false,
    code,
    message,
    ...(requestId ? { request_id: requestId } : {}),
    ...(extra ?? {}),
  };
}
