// FIXED-by-Fixer-A20 2026-04-25 — WEB-FAE-001 follow-up.
// Boolean counterpart to <PermissionBoundary>. Use for ad-hoc role gating
// that can't easily be wrapped in JSX (filter callbacks, derived state,
// disabled-prop math). Keeps role-source authority centralised in the
// auth store so a future role-check rewrite (e.g. policy-driven, server
// permissions hash) only has to touch this file + PermissionBoundary.
import { useAuthStore } from '@/stores/authStore';

export function useHasRole(roles: string[] | string): boolean {
  const user = useAuthStore((s) => s.user);
  if (!user) return false;
  const allowed = Array.isArray(roles) ? roles : [roles];
  return allowed.includes(user.role);
}
