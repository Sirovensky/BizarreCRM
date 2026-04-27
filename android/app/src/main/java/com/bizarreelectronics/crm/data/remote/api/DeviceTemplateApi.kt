package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * DeviceTemplateApi — §4.9 L762
 *
 * Retrofit interface for device-template CRUD. Templates are pre-configured
 * device + common-repair bundles that pre-fill the TicketCreate Device step
 * and appear as shortcuts on the Bench tab.
 *
 * iOS parallel: same endpoints consumed by the iOS Swift client.
 *
 * Server endpoints (packages/server/src/routes/device-templates.ts):
 *   GET    /api/v1/device-templates
 *   POST   /api/v1/device-templates
 *   PUT    /api/v1/device-templates/:id
 */
interface DeviceTemplateApi {

    /**
     * List all device templates for this tenant.
     *
     * @return list of [DeviceTemplateDto]; 404-tolerant — callers fall back to
     *         an empty list when the endpoint does not exist yet on the server.
     */
    @GET("device-templates")
    suspend fun getTemplates(): ApiResponse<List<DeviceTemplateDto>>

    /**
     * Create a new device template.
     *
     * @param body [CreateDeviceTemplateRequest] with name, deviceModelId, and
     *             optional list of common repair names.
     * @return the newly created [DeviceTemplateDto].
     */
    @POST("device-templates")
    suspend fun createTemplate(@Body body: CreateDeviceTemplateRequest): ApiResponse<DeviceTemplateDto>

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
        @Body body: CreateDeviceTemplateRequest,
    ): ApiResponse<DeviceTemplateDto>

    /**
     * Search templates by category or device model hint.
     *
     * @param category    Optional category slug (phone/tablet/etc.).
     * @param model       Optional free-text model name filter.
     * @return filtered list of [DeviceTemplateDto].
     */
    @GET("device-templates")
    suspend fun searchTemplates(
        @Query("category") category: String? = null,
        @Query("model") model: String? = null,
    ): ApiResponse<List<DeviceTemplateDto>>

    /**
     * Apply a template to an existing ticket.
     * Server inserts common_repairs as ticket lines + copies parts_json.
     *
     * @param id            Template ID.
     * @param ticketId      Target ticket ID.
     * @param body          Optional ticket_device_id binding.
     * @return [ApplyTemplateResult] with inserted line count.
     */
    @POST("device-templates/{id}/apply-to-ticket/{ticketId}")
    suspend fun applyTemplate(
        @Path("id") id: Long,
        @Path("ticketId") ticketId: Long,
        @Body body: ApplyTemplateBody = ApplyTemplateBody(),
    ): ApiResponse<ApplyTemplateResult>
}

// ─── DTOs ────────────────────────────────────────────────────────────────────

data class DeviceTemplateDto(
    val id: Long,
    val name: String,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    @SerializedName("device_model_name")
    val deviceModelName: String?,
    @SerializedName("common_repairs")
    val commonRepairs: List<String> = emptyList(),
    @SerializedName("created_at")
    val createdAt: String?,
    // Extended fields returned by server apply-to-ticket endpoint
    @SerializedName("device_category")
    val deviceCategory: String? = null,
    @SerializedName("device_model")
    val deviceModel: String? = null,
    val fault: String? = null,
    @SerializedName("est_labor_minutes")
    val estLaborMinutes: Int = 0,
    @SerializedName("suggested_price")
    val suggestedPrice: Int = 0,
    @SerializedName("diagnostic_checklist")
    val diagnosticChecklist: List<String> = emptyList(),
    @SerializedName("is_active")
    val isActive: Int = 1,
) {
    /** Display subtitle: "ModelName — Fault" or just model or fault, whichever is available. */
    val displaySubtitle: String?
        get() {
            val parts = listOfNotNull(deviceModelName ?: deviceModel, fault)
            return parts.joinToString(" — ").takeIf { it.isNotBlank() }
        }

    /** Repairs to display; falls back to diagnostic checklist when common_repairs is empty. */
    val displayRepairs: List<String>
        get() = commonRepairs.ifEmpty { diagnosticChecklist }
}

data class CreateDeviceTemplateRequest(
    val name: String,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    @SerializedName("common_repairs")
    val commonRepairs: List<String>,
)

/** Body for POST device-templates/:id/apply-to-ticket/:ticketId */
data class ApplyTemplateBody(
    @SerializedName("ticket_device_id")
    val ticketDeviceId: Long? = null,
)

/** Result returned by apply-to-ticket endpoint. */
data class ApplyTemplateResult(
    @SerializedName("lines_inserted")
    val linesInserted: Int = 0,
    @SerializedName("parts_inserted")
    val partsInserted: Int = 0,
    val message: String? = null,
)
