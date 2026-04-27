package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path

/**
 * §14.4 — Custom roles API.
 *
 * Mounted at /api/v1/roles on the server (roles.routes.ts).
 * All endpoints admin-only (server enforces; client shows 403 snackbar).
 *
 * Also covers: PUT /roles/users/:userId/role for per-user role assignment.
 */

data class CustomRoleDto(
    val id: Long,
    val name: String,
    val description: String?,
    @SerializedName("is_active") val isActive: Int = 1,
    @SerializedName("created_at") val createdAt: String?,
)

data class CreateRoleBody(
    val name: String,
    val description: String? = null,
)

data class UpdateRoleBody(
    val name: String? = null,
    val description: String? = null,
    @SerializedName("is_active") val isActive: Int? = null,
)

data class AssignRoleBody(
    val role: String,
)

interface RolesApi {

    /** List all custom roles. Admin only. */
    @GET("roles")
    suspend fun getRoles(): ApiResponse<List<CustomRoleDto>>

    /** Create a custom role. Admin only. */
    @POST("roles")
    suspend fun createRole(
        @Body body: CreateRoleBody,
    ): ApiResponse<CustomRoleDto>

    /** Update role name / description / is_active. Admin only. */
    @PUT("roles/{id}")
    suspend fun updateRole(
        @Path("id") roleId: Long,
        @Body body: UpdateRoleBody,
    ): ApiResponse<CustomRoleDto>

    /** Delete a custom role. Admin only. */
    @DELETE("roles/{id}")
    suspend fun deleteRole(
        @Path("id") roleId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Assign a role to a user.
     * PUT /roles/users/:userId/role with { role: "technician" }
     * Admin only.
     */
    @PUT("roles/users/{userId}/role")
    suspend fun assignRole(
        @Path("userId") userId: Long,
        @Body body: AssignRoleBody,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
