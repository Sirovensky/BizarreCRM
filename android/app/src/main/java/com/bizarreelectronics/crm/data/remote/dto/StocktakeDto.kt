package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── §60 Inventory Stocktake DTOs ────────────────────────────────────────────

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
