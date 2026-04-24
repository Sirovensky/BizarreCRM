package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

// ─── DTOs ───────────────────────────────────────────────────────────────────

data class TeamChatRoom(
    val id: String,
    val name: String,
    val type: String,           // "channel" | "dm" | "team"
    val description: String?,
    @SerializedName("unread_count")
    val unreadCount: Int = 0,
    @SerializedName("is_pinned")
    val isPinned: Boolean = false,
    @SerializedName("last_message")
    val lastMessage: String?,
    @SerializedName("last_message_at")
    val lastMessageAt: String?,
    @SerializedName("member_count")
    val memberCount: Int = 0,
)

data class TeamChatRoomListData(
    val rooms: List<TeamChatRoom>,
)

data class TeamChatMessage(
    val id: String,
    @SerializedName("room_id")
    val roomId: String,
    val body: String,
    @SerializedName("author_id")
    val authorId: Long,
    @SerializedName("author_name")
    val authorName: String,
    @SerializedName("author_role")
    val authorRole: String?,
    @SerializedName("created_at")
    val createdAt: String,
    @SerializedName("is_pinned")
    val isPinned: Boolean = false,
    val reactions: List<TeamChatReaction> = emptyList(),
    val attachments: List<String> = emptyList(),
)

data class TeamChatReaction(
    val emoji: String,
    val count: Int,
    @SerializedName("reacted_by_me")
    val reactedByMe: Boolean = false,
)

data class TeamChatMessageListData(
    val messages: List<TeamChatMessage>,
    val cursor: String?,
    @SerializedName("has_more")
    val hasMore: Boolean = false,
)

data class TeamChatSendRequest(
    val body: String,
    val mentions: List<Long> = emptyList(),
)

data class TeamChatReactionRequest(
    val emoji: String,
)

/**
 * §47 — Team chat REST endpoints.
 * All endpoints are 404-tolerant: callers catch and degrade gracefully.
 */
interface TeamChatApi {

    /** List all rooms the current user is a member of. */
    @GET("team-chat/rooms")
    suspend fun getRooms(): ApiResponse<TeamChatRoomListData>

    /** Cursor-paginated messages for a room, newest-first. */
    @GET("team-chat/rooms/{id}/messages")
    suspend fun getMessages(
        @Path("id") roomId: String,
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 50,
    ): ApiResponse<TeamChatMessageListData>

    /** Post a new message to a room. */
    @POST("team-chat/rooms/{id}/messages")
    suspend fun sendMessage(
        @Path("id") roomId: String,
        @Body request: TeamChatSendRequest,
    ): ApiResponse<TeamChatMessage>

    /** Toggle a reaction on a message. */
    @POST("team-chat/rooms/{id}/messages/{msgId}/reactions")
    suspend fun toggleReaction(
        @Path("id") roomId: String,
        @Path("msgId") messageId: String,
        @Body request: TeamChatReactionRequest,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
