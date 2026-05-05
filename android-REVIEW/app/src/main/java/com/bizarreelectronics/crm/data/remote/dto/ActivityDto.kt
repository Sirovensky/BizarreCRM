package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * §3.16 L592-L599 — Activity feed DTOs.
 *
 * Server returns events pre-rendered without raw customer PII:
 *   "text": "Ticket #1234 status changed to Ready"
 * rather than "John Smith's iPhone repair complete".
 *
 * Android adds a defense-in-depth regex pass to strip any residual
 * emails / phone numbers before display (see ActivityFeedViewModel.redactText).
 */

/**
 * A single activity feed event from the server.
 *
 * @param id          Stable server-assigned row ID (used as scroll cursor).
 * @param type        Event category: "ticket", "invoice", "customer", "inventory", etc.
 * @param actor       Display name of the user who triggered the action.
 * @param verb        Short action word: "updated", "created", "closed", "assigned", etc.
 * @param subject     Short subject: "Ticket #1234", "Invoice #56", etc.
 * @param text        Full pre-rendered sentence from the server (no raw PII).
 * @param entityType  Entity domain for deep-link routing: "ticket", "invoice", "customer".
 * @param entityId    Entity primary key for deep-link routing. Null if not linkable.
 * @param timeAgo     Pre-formatted relative time from the server: "5m ago", "2h ago".
 * @param avatarInitials Up to 2 initials for the actor avatar. Null → generic icon.
 * @param location    Optional shop location tag (e.g. "Main St"). Null = not set.
 * @param reactions   Map of emoji → count from existing reactions. Empty if none.
 */
data class ActivityEventDto(
    val id: Long,
    val type: String,
    val actor: String,
    val verb: String,
    val subject: String,
    val text: String,
    @SerializedName("entity_type") val entityType: String? = null,
    @SerializedName("entity_id") val entityId: Long? = null,
    @SerializedName("time_ago") val timeAgo: String,
    @SerializedName("avatar_initials") val avatarInitials: String? = null,
    val location: String? = null,
    val reactions: Map<String, Int> = emptyMap(),
)

/**
 * Cursor-paginated page of activity events.
 *
 * @param items      Events for this page, newest first.
 * @param nextCursor Opaque cursor to pass as `?cursor=` on the next call.
 *                   Null when this is the last page.
 */
data class ActivityPageResponse(
    val items: List<ActivityEventDto>,
    @SerializedName("next_cursor") val nextCursor: String? = null,
)
