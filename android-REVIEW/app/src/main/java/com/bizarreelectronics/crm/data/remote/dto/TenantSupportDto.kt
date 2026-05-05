package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * DTO returned by GET /api/v1/tenants/me/support-contact (ActionPlan §2.12 L355).
 *
 * All fields are nullable. When the endpoint returns 404 (server side pending) or
 * is unreachable, the Android client must render "Contact your admin." copy with NO
 * mail/call intent rather than using any hardcoded address.
 *
 * Contract:
 *   { "email": "admin@example.com", "phone": "+15551234567", "hours": "Mon–Fri 9–5" }
 *
 * Self-hosted tenants return their own admin's contact info.
 * The bizarrecrm.com-hosted tenant returns pavel@bizarreelectronics.com.
 * NEVER hardcode any email address on the client side.
 *
 * Server-side endpoint: packages/server/src/routes/ — NOT YET IMPLEMENTED (pending).
 * This DTO and the TenantsApi interface define the agreed contract.
 */
data class TenantSupportDto(
    @SerializedName("email") val email: String? = null,
    @SerializedName("phone") val phone: String? = null,
    @SerializedName("hours") val hours: String? = null,
)
