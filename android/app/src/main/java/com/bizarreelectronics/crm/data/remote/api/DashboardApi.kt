package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * §3.3 L513 — Dashboard-specific API operations.
 *
 * Dismiss endpoint: POST /dashboard/attention/{id}/dismiss
 *
 * **Graceful degradation**: the server does not yet implement this endpoint.
 * The ViewModel catches HTTP 404 and falls back to
 * [com.bizarreelectronics.crm.data.local.prefs.AppPreferences.addDismissedAttentionId]
 * so dismisses are preserved locally regardless of server status.
 *
 * Response body when endpoint is live:
 * ```json
 * { "success": true, "data": { "id": "<id>", "dismissed": true } }
 * ```
 */
interface DashboardApi {

    /**
     * Server-side dismiss for a needs-attention item.
     *
     * Returns a generic [ApiResponse] with a map payload. The ViewModel treats
     * any non-exception response (including 204 No Content projected through
     * Retrofit) as success. A [retrofit2.HttpException] with code 404 is caught
     * and silently demoted to the local-only fallback path.
     *
     * @param id [NeedsAttentionItem.id] value as assigned by the server.
     */
    @POST("dashboard/attention/{id}/dismiss")
    suspend fun dismissAttentionItem(
        @Path("id") id: String,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
