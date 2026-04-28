package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── §60 / §6.6 Inventory Stocktake DTOs ─────────────────────────────────────

/**
 * One row from GET /stocktake or POST /stocktake.
 * Mirrors the `stocktakes` DB table returned by stocktake.routes.ts.
 */
data class StocktakeListItem(
    val id: Int,
    val name: String,
    val location: String?,
    /** "open" | "committed" | "cancelled" */
    val status: String,
    @SerializedName("opened_by_user_id")
    val openedByUserId: Int?,
    @SerializedName("opened_at")
    val openedAt: String,
    @SerializedName("committed_at")
    val committedAt: String?,
    val notes: String?,
)

/**
 * Request body for POST /stocktake (open a new session).
 * [name] required; [location] and [notes] optional.
 */
data class StocktakeCreateRequest(
    val name: String,
    val location: String? = null,
    val notes: String? = null,
)



/**
 * Returned by POST /inventory/stocktake/start.
 * [sessionId] is a server-assigned UUID used for multi-scanner WebSocket sync.
 * Absent when the endpoint 404s (offline / server not yet updated).
 */
data class StocktakeSessionData(
    @SerializedName("session_id")
    val sessionId: String?,
)

/**
 * One counted line within a stocktake session.
 * [itemId] references inventory_items.id. [countedQty] is what the operator
 * physically counted. [systemQty] is the quantity recorded in the DB at the
 * time the session was started (used for variance computation).
 */
data class StocktakeCountLine(
    @SerializedName("item_id")
    val itemId: Long,
    @SerializedName("item_name")
    val itemName: String,
    val sku: String?,
    @SerializedName("upc_code")
    val upcCode: String?,
    @SerializedName("system_qty")
    val systemQty: Int,
    @SerializedName("counted_qty")
    val countedQty: Int,
) {
    /** Positive = surplus found on shelf. Negative = shrinkage. */
    val variance: Int get() = countedQty - systemQty
}

/**
 * Request body for POST /inventory/stocktake/commit.
 * [sessionId] may be null when the server start endpoint 404d.
 */
data class StocktakeCommitRequest(
    @SerializedName("session_id")
    val sessionId: String?,
    val lines: List<StocktakeCountLine>,
    val note: String?,
)
