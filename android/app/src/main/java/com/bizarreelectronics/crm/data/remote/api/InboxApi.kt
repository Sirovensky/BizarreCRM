package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.SmsConversationItem
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §12.1 — Shared team-inbox endpoints.
 *
 * GET  /inbox           — list all inbound conversations across the shop.
 * POST /inbox/:id/assign — assign a conversation to a teammate (by user id).
 *
 * 404 on both endpoints means the tenant does not have team-inbox enabled;
 * callers show a "not available" banner and gracefully degrade.
 */
interface InboxApi {

    /**
     * Fetch the shared inbox conversation list.
     *
     * Query params:
     *   assigned_to=<user_id>  — filter by assignee (optional)
     *   unread=true            — only unread conversations (optional)
     *
     * Response shape (when live):
     * ```json
     * { "success": true, "data": { "conversations": [...] } }
     * ```
     *
     * 404 → team inbox not enabled on this tenant.
     */
    @GET("inbox")
    suspend fun getInbox(
        @Query("assigned_to") assignedTo: Long? = null,
        @Query("unread") unread: Boolean? = null,
    ): ApiResponse<InboxListData>

    /**
     * Assign a conversation to a teammate.
     *
     * POST /inbox/:id/assign
     * Body: { assigned_to: <user_id> | null }
     * null = unassign.
     *
     * 404 → tolerated; assignment is optimistic in the UI.
     */
    @POST("inbox/{id}/assign")
    suspend fun assignConversation(
        @Path("id") conversationId: Long,
        @Body body: InboxAssignRequest,
    ): ApiResponse<Unit>
}

// ── DTOs ─────────────────────────────────────────────────────────────────────

data class InboxListData(
    val conversations: List<InboxConversation>,
)

data class InboxConversation(
    val id: Long,
    @SerializedName("conv_phone")
    val convPhone: String,
    @SerializedName("last_message")
    val lastMessage: String?,
    @SerializedName("last_message_at")
    val lastMessageAt: String?,
    @SerializedName("unread_count")
    val unreadCount: Int = 0,
    @SerializedName("assigned_to_id")
    val assignedToId: Long? = null,
    @SerializedName("assigned_to_name")
    val assignedToName: String? = null,
    @SerializedName("customer_name")
    val customerName: String? = null,
    @SerializedName("customer_id")
    val customerId: Long? = null,
)

data class InboxAssignRequest(
    @SerializedName("assigned_to")
    val assignedTo: Long?,
)
