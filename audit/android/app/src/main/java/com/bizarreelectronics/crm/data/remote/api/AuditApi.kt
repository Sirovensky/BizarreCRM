package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.GET
import retrofit2.http.Query

// ─── DTOs ────────────────────────────────────────────────────────────────────

data class AuditEntry(
    val id: Long,
    val actor: String,
    val actorRole: String,
    val action: String,
    val entityType: String,
    val entityId: Long?,
    val entityLabel: String?,
    val diffSummary: String?,
    val diffJson: String?,
    val timestamp: String,
    val ipAddress: String?,
)

data class AuditPageResponse(
    val items: List<AuditEntry>,
    val nextCursor: String?,
    val total: Int,
)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * §52 — Audit Logs API.
 *
 * GET /audit — returns cursor-paginated log entries.
 * 404 is tolerated: callers show an empty-state screen rather than crashing.
 *
 * All params are optional filters:
 *  - [actor]      — username or user-id substring
 *  - [entityType] — e.g. "ticket", "customer", "invoice"
 *  - [action]     — e.g. "create", "update", "delete", "login"
 *  - [from] / [to] — ISO-8601 datetime strings (server interprets as UTC)
 *  - [cursor]     — opaque pagination token from previous response
 *  - [limit]      — page size (default 50)
 */
interface AuditApi {

    @GET("audit")
    suspend fun getAuditLog(
        @Query("actor") actor: String? = null,
        @Query("entity") entityType: String? = null,
        @Query("action") action: String? = null,
        @Query("from") from: String? = null,
        @Query("to") to: String? = null,
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 50,
    ): ApiResponse<AuditPageResponse>
}
