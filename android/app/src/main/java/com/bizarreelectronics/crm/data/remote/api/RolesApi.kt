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
 * §49   — Roles Matrix Editor (permission grid).
 *
 * Mounted at /api/v1/roles on the server (roles.routes.ts).
 * All write endpoints admin-only (server enforces; client shows 403 snackbar).
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

// ── §49 — Permission matrix DTOs ──────────────────────────────────────────────

/** One row of the permission matrix returned by GET /roles/:id/permissions. */
data class PermissionEntryDto(
    val key: String,
    val allowed: Boolean,
)

/** Full payload returned by GET /roles/:id/permissions. */
data class PermissionMatrixDto(
    val role: CustomRoleDto,
    val matrix: List<PermissionEntryDto>,
)

/** Body for PUT /roles/:id/permissions. */
data class UpdatePermissionsBody(
    val updates: List<PermissionEntryDto>,
)

interface RolesApi {

    /** List all custom roles. Admin only. */
    @GET("roles")
    suspend fun getRoles(): ApiResponse<List<CustomRoleDto>>

    /**
     * §49 — Canonical permission key list.
     * GET /roles/permission-keys — returns the server's PERMISSION_KEYS array.
     * No auth required.
     */
    @GET("roles/permission-keys")
    suspend fun getPermissionKeys(): ApiResponse<List<String>>

    /** Create a custom role. Admin only. */
    @POST("roles")
    suspend fun createRole(
        @Body body: CreateRoleBody,
    ): ApiResponse<CustomRoleDto>

    /** Update role description / is_active. Admin only. */
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
     * §49 — Full permission matrix for a role.
     * GET /roles/:id/permissions → { role, matrix: [{key, allowed}] }
     * Admin only.
     */
    @GET("roles/{id}/permissions")
    suspend fun getRolePermissions(
        @Path("id") roleId: Long,
    ): ApiResponse<PermissionMatrixDto>

    /**
     * §49 — Persist toggled permissions for a role.
     * PUT /roles/:id/permissions with { updates: [{key, allowed}] }
     * Admin only. Server applies as a transaction — partial-fail rolls back.
     */
    @PUT("roles/{id}/permissions")
    suspend fun updateRolePermissions(
        @Path("id") roleId: Long,
        @Body body: UpdatePermissionsBody,
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
