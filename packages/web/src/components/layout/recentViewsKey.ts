// Per-user localStorage key for the Sidebar's "Recent views" list. Lives
// in its own file so Sidebar.tsx exports only React components — keeps
// React Fast Refresh happy. Previously this lived alongside the Sidebar
// component, which caused vite to emit:
//   hmr invalidate ... Could not Fast Refresh ("recentViewsKey" export
//   is incompatible)
// on every Sidebar edit, forcing a full page reload (and the reload then
// occasionally hung). See the auth-cleared listener still in Sidebar.tsx
// for the wipe behavior on logout.
//
// Tenant scoping rationale: a single browser shared across two tenants
// would otherwise spill tenant A's recent tickets into B's sidebar. The
// User type has no tenant_id field, so per-user is the strongest scope
// we can express client-side; cross-tenant leak follows for free since a
// single user.id can't span tenants.
export function recentViewsKey(userId: number | null | undefined): string {
  return userId ? `recent_views:u${userId}` : 'recent_views';
}
