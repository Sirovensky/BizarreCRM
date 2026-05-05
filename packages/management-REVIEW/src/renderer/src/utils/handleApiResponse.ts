/**
 * AUDIT-MGT-010: Centralised auth-expiry detection for authenticated IPC calls.
 *
 * Problem: auto-logout on 401 only fired when the management:get-stats poll
 * returned an expired-token response. Any other page (TenantsPage, SessionsPage,
 * AuditLogPage, BackupPage) that received a 401 would silently fail — the user
 * would see "Failed to load …" toasts but stay authenticated, and could keep
 * navigating to broken pages indefinitely.
 *
 * Fix: every authenticated IPC call result is piped through this helper.
 * When a 401-shaped response is detected it dispatches `managementAuthExpired`
 * on the window. The authStore subscribes to this event and clears state +
 * triggers navigation to /login (see authStore.ts).
 *
 * Usage (in any page):
 *   const res = await getAPI().superAdmin.listTenants();
 *   if (handleApiResponse(res)) return; // expired — do not proceed
 *   // safe to use res.data here
 */

import type { ApiResponse } from '@/api/bridge';

/** Phrases the server returns when a JWT is expired or invalid. */
const AUTH_EXPIRED_MARKERS = [
  'invalid or expired',
  'token expired',
  'session expired',
  'jwt expired',
  'unauthorized',
] as const;

function isAuthExpiredMessage(message: string | undefined): boolean {
  if (!message) return false;
  const lower = message.toLowerCase();
  return AUTH_EXPIRED_MARKERS.some((marker) => lower.includes(marker));
}

/**
 * Check an IPC API response for auth-expiry signals.
 *
 * Priority order (DASH-ELEC-060):
 *   1. HTTP status === 401 — unambiguous, server-authoritative.
 *   2. Explicit `authExpired` flag — future-proofing for custom IPC errors.
 *   3. Message substring match — fallback for legacy responses that lack
 *      a propagated status field.
 *
 * When any signal fires this function dispatches `managementAuthExpired` on
 * the window and returns `true` so the caller can bail out immediately.
 *
 * Returns `false` for all other responses (including normal success or
 * non-auth errors), so callers can always do:
 *
 *   if (handleApiResponse(res)) return;
 */
export function handleApiResponse(res: ApiResponse<unknown>): boolean {
  if (res.success) return false;

  // Primary: HTTP status propagated by main-process bodyOf() helper.
  // (DASH-ELEC-060)
  if (res.status === 401) {
    window.dispatchEvent(new Event('managementAuthExpired'));
    return true;
  }

  // Secondary: explicit authExpired flag (future-proofing)
  if ((res as ApiResponse<unknown> & { authExpired?: boolean }).authExpired) {
    window.dispatchEvent(new Event('managementAuthExpired'));
    return true;
  }

  // Tertiary: message substring match — handles network-layer responses that
  // never reach the HTTP layer and therefore carry no status code.
  if (isAuthExpiredMessage(res.message)) {
    window.dispatchEvent(new Event('managementAuthExpired'));
    return true;
  }

  return false;
}
