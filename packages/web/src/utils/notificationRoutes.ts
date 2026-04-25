// WEB-FL-016: Notification deep-link routing — hoisted from Header.tsx
// so the entity_type → URL-prefix mapping stays alignable with the server's
// notifications taxonomy (server emits notifications with these entity_type
// strings; client routes to the matching feature page).
//
// To add a new entity_type:
//   1. Add a row below mapping the server taxonomy key to its UI route prefix.
//   2. The notification click handler in Header.tsx will navigate to
//      `${routes[entity_type]}/${entity_id}` automatically.
//
// Keep this list in sync with packages/server/src/services/notifications.* —
// any entity_type emitted server-side that's missing here yields a no-op
// click in the bell dropdown (visible bug for users).

export const NOTIFICATION_ENTITY_ROUTES: Readonly<Record<string, string>> = Object.freeze({
  ticket: '/tickets',
  invoice: '/invoices',
  customer: '/customers',
  inventory: '/inventory',
  lead: '/leads',
});

/**
 * Resolve a notification's deep-link URL given an entity_type/entity_id pair
 * coming from the server. Returns null when the entity_type is unknown so the
 * caller can fall back to a no-nav (or a toast in dev mode).
 */
export function notificationDeepLink(
  entityType: string | null | undefined,
  entityId: number | string | null | undefined,
): string | null {
  if (!entityType || entityId == null) return null;
  const base = NOTIFICATION_ENTITY_ROUTES[entityType];
  return base ? `${base}/${entityId}` : null;
}
