package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * DeviceTemplateApi — §44.1
 *
 * Retrofit interface for device-template CRUD. Templates are pre-configured
 * device + common-repair bundles that pre-fill the TicketCreate Device step
 * and appear as shortcuts on the Bench tab.
 *
 * iOS parallel: same endpoints consumed by the iOS Swift client.
 *
 * Server endpoints (packages/server/src/routes/deviceTemplates.routes.ts):
 *   GET    /api/v1/device-templates
 *   POST   /api/v1/device-templates
 *   PUT    /api/v1/device-templates/:id
 *   DELETE /api/v1/device-templates/:id
 */
interface DeviceTemplateApi {

    /**
     * List all device templates for this tenant.
     *
     * @param category  Optional filter by device category slug.
     * @param model     Optional filter by device model name.
     * @return list of [DeviceTemplateDto]; 404-tolerant — callers fall back to
     *         an empty list when the endpoint does not exist yet on the server.
     */
    @GET("device-templates")
    suspend fun getTemplates(
        @Query("category") category: String? = null,
        @Query("model") model: String? = null,
    ): ApiResponse<List<DeviceTemplateDto>>

    /**
     * Create a new device template.
     *
     * @param body [UpsertDeviceTemplateRequest] with all template fields.
     * @return the newly created [DeviceTemplateDto].
     */
    @POST("device-templates")
    suspend fun createTemplate(@Body body: UpsertDeviceTemplateRequest): ApiResponse<DeviceTemplateDto>

    /**
     * Update an existing device template.
     *
     * @param id   Numeric template ID.
     * @param body Fields to update.
     * @return the updated [DeviceTemplateDto].
     */
    @PUT("device-templates/{id}")
    suspend fun updateTemplate(
        @Path("id") id: Long,
        @Body body: UpsertDeviceTemplateRequest,
    ): ApiResponse<DeviceTemplateDto>

    /**
     * Delete a device template (admin only).
     *
     * @param id Numeric template ID.
     */
    @DELETE("device-templates/{id}")
    suspend fun deleteTemplate(@Path("id") id: Long): ApiResponse<Unit>
}

// ─── DTOs ────────────────────────────────────────────────────────────────────

/**
 * Full device-template shape returned by the server.
 *
 * Money fields ([estLaborCostCents], [suggestedPriceCents]) are stored on the
 * server as integer cents. Format for display with
 * [java.text.NumberFormat.getCurrencyInstance].
 *
 * @param diagnosticChecklist  Pre-conditions / diagnostic steps for this device class.
 * @param parts                Enriched parts list with inventory status badges.
 */
data class DeviceTemplateDto(
    val id: Long,
    val name: String,
    @SerializedName("device_category")
    val deviceCategory: String?,
    @SerializedName("device_model")
    val deviceModel: String?,
    val fault: String?,
    /** Estimated labor time in minutes. */
    @SerializedName("est_labor_minutes")
    val estLaborMinutes: Int = 0,
    /** Estimated labor cost in cents (store as Long, display via NumberFormat). */
    @SerializedName("est_labor_cost")
    val estLaborCostCents: Long = 0L,
    /** Suggested ticket price in cents. */
    @SerializedName("suggested_price")
    val suggestedPriceCents: Long = 0L,
    @SerializedName("diagnostic_checklist")
    val diagnosticChecklist: List<String> = emptyList(),
    /** Enriched parts list including inventory stock badge. */
    val parts: List<TemplatePartDto> = emptyList(),
    @SerializedName("warranty_days")
    val warrantyDays: Int = 30,
    @SerializedName("is_active")
    val isActive: Int = 1,
    @SerializedName("sort_order")
    val sortOrder: Int = 0,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    // Legacy fields kept for backward compat with older server versions
    @SerializedName("device_model_id")
    val deviceModelId: Long? = null,
    @SerializedName("device_model_name")
    val deviceModelName: String? = null,
    /** Legacy flat list of common repair names (pre-§44.1 server). */
    @SerializedName("common_repairs")
    val commonRepairs: List<String> = emptyList(),
)

/** One part entry within a device template, enriched with inventory status. */
data class TemplatePartDto(
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long,
    val qty: Int = 1,
    val name: String = "",
    val sku: String? = null,
    /** Cost price in cents. */
    @SerializedName("cost_price")
    val costPriceCents: Long = 0L,
    /** Retail price in cents. */
    @SerializedName("retail_price")
    val retailPriceCents: Long = 0L,
    @SerializedName("in_stock")
    val inStock: Int = 0,
    /** "green" | "yellow" | "red" */
    @SerializedName("stock_badge")
    val stockBadge: String = "red",
)

data class UpsertDeviceTemplateRequest(
    val name: String,
    @SerializedName("device_category")
    val deviceCategory: String?,
    @SerializedName("device_model")
    val deviceModel: String?,
    val fault: String?,
    @SerializedName("est_labor_minutes")
    val estLaborMinutes: Int,
    /** Labor cost in cents. */
    @SerializedName("est_labor_cost")
    val estLaborCost: Long,
    /** Suggested price in cents. */
    @SerializedName("suggested_price")
    val suggestedPrice: Long,
    @SerializedName("diagnostic_checklist")
    val diagnosticChecklist: List<String>,
    @SerializedName("warranty_days")
    val warrantyDays: Int,
    @SerializedName("is_active")
    val isActive: Int = 1,
)

// Keep backward-compat alias so any remaining callers of CreateDeviceTemplateRequest compile.
@Deprecated("Use UpsertDeviceTemplateRequest", ReplaceWith("UpsertDeviceTemplateRequest"))
typealias CreateDeviceTemplateRequest = UpsertDeviceTemplateRequest
