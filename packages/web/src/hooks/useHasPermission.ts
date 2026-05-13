/**
 * Boolean permission check hook — TICKETS-STATUS-NOOP-1 unblock.
 *
 * Reads `user.permissions` from the auth store. The server side already
 * computes `effectivePermissionMap(user)` (custom role + per-user grants /
 * denies + legacy role fallback) and ships it down with `/auth/me`, so the
 * client never has to re-derive precedence.
 *
 * Use this for ad-hoc gating that can't easily be wrapped in JSX:
 * disabling a dropdown, filtering an action menu, hiding a row button.
 * For full subtree gating use `<PermissionBoundary />` instead.
 *
 * Admin always passes — the server hardcodes `tickets.change_status`,
 * `invoices.credit_note`, etc. to true for the admin role, but a future
 * deny override might be added; if `permissions` is present, trust it.
 * If `permissions` is null/undefined (logged-out, stale cache), return
 * false so callers fail closed.
 */
import { useAuthStore } from '@/stores/authStore';

export function useHasPermission(permissionKey: string): boolean {
  const user = useAuthStore((s) => s.user);
  if (!user) return false;
  if (user.role === 'admin') return true;
  const map = user.permissions;
  if (!map) return false;
  return map[permissionKey] === true;
}
