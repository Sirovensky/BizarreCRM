package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.data

/**
 * Tablet ticket-detail Quote add-row typeahead suggestion (T-C6).
 *
 * Three kinds power the dropdown:
 *  - [Kind.PART] — concrete inventory row from `InventoryApi.getItems`.
 *    Has a real `inventoryItemId` and ships via the existing
 *    `POST tickets/devices/{deviceId}/parts` endpoint.
 *  - [Kind.SVC] — labour line from `RepairPricingApi.getServices`.
 *    `inventoryItemId == null`. Server endpoint for service lines is
 *    deferred (T-C6-server) — UI dispatches a structured payload via
 *    `TicketDetailViewModel.addQuoteLine` which logs + snackbars
 *    "wiring deferred" until the route lands.
 *  - [Kind.MISC] — typed-as-misc fallback rendered when both lists are
 *    empty. Lets the user record a one-off line "+ Add \"{q}\" as
 *    one-off misc charge". Same deferred status as SVC.
 *
 * The label tag visible to users:
 *  - PART → "Part"  (in stock count when `inStock != null`)
 *  - SVC  → "Svc"
 *  - MISC → "Misc"
 *
 * Equality + hashCode are structural (data class) so list diffing
 * inside the typeahead dropdown is cheap.
 */
data class QuoteSuggestion(
    val kind: Kind,
    val name: String,
    val meta: String?,
    val priceCents: Long,
    /** Real inventory id when [kind] == PART; null otherwise. */
    val inventoryItemId: Long? = null,
    /** Real repair-service id when [kind] == SVC; null otherwise. */
    val repairServiceId: Long? = null,
    /** Stock-on-hand count for [Kind.PART] suggestions; null otherwise. */
    val inStock: Int? = null,
) {
    enum class Kind { PART, SVC, MISC }
}
