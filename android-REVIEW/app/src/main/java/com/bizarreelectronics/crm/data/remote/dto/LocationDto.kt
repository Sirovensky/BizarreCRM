package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * DTO returned by GET /api/v1/locations and GET /api/v1/locations/:id.
 *
 * ActionPlan §63 — Multi-Location Management.
 *
 * Server contract (locations.routes.ts):
 *   GET /locations  → { success: true, data: [LocationDto] }
 *   GET /locations/:id → { success: true, data: LocationDto + user_count }
 *   POST /locations → 201 { success: true, data: LocationDto }
 *   PATCH /locations/:id → { success: true, data: LocationDto }
 *   DELETE /locations/:id → soft-deactivates; { success: true, data: { id, is_active: 0 } }
 *   POST /locations/:id/set-default → { success: true, data: LocationDto }
 *
 * Role gates enforced server-side:
 *   CRUD + set-default: admin only
 *   List / detail: any authenticated user
 */
data class LocationDto(
    @SerializedName("id")           val id: Long = 0,
    @SerializedName("name")         val name: String = "",
    @SerializedName("address_line") val addressLine: String? = null,
    @SerializedName("city")         val city: String? = null,
    @SerializedName("state")        val state: String? = null,
    @SerializedName("postcode")     val postcode: String? = null,
    @SerializedName("country")      val country: String = "US",
    @SerializedName("phone")        val phone: String? = null,
    @SerializedName("email")        val email: String? = null,
    @SerializedName("lat")          val lat: Double? = null,
    @SerializedName("lng")          val lng: Double? = null,
    @SerializedName("timezone")     val timezone: String = "America/New_York",
    @SerializedName("is_active")    val isActive: Int = 1,
    @SerializedName("is_default")   val isDefault: Int = 0,
    @SerializedName("notes")        val notes: String? = null,
    @SerializedName("created_at")   val createdAt: String = "",
    @SerializedName("updated_at")   val updatedAt: String = "",
    /** Only present on GET /locations/:id response. */
    @SerializedName("user_count")   val userCount: Int? = null,
)

data class CreateLocationRequest(
    @SerializedName("name")         val name: String,
    @SerializedName("address_line") val addressLine: String? = null,
    @SerializedName("city")         val city: String? = null,
    @SerializedName("state")        val state: String? = null,
    @SerializedName("postcode")     val postcode: String? = null,
    @SerializedName("country")      val country: String = "US",
    @SerializedName("phone")        val phone: String? = null,
    @SerializedName("email")        val email: String? = null,
    @SerializedName("timezone")     val timezone: String = "America/New_York",
    @SerializedName("notes")        val notes: String? = null,
)

data class UpdateLocationRequest(
    @SerializedName("name")         val name: String? = null,
    @SerializedName("address_line") val addressLine: String? = null,
    @SerializedName("city")         val city: String? = null,
    @SerializedName("state")        val state: String? = null,
    @SerializedName("postcode")     val postcode: String? = null,
    @SerializedName("country")      val country: String? = null,
    @SerializedName("phone")        val phone: String? = null,
    @SerializedName("email")        val email: String? = null,
    @SerializedName("timezone")     val timezone: String? = null,
    @SerializedName("notes")        val notes: String? = null,
)
