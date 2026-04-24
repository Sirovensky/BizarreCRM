package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path

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
)

data class CreateDeviceTemplateRequest(
    val name: String,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    @SerializedName("common_repairs")
    val commonRepairs: List<String>,
)
