package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── §60 Stocktake DTOs ──────────────────────────────────────────────────────

/** One row from GET /stocktake (list) or POST /stocktake (open). */
data class StocktakeRow(
    val id: Long,
    val name: String,
    val location: String?,
    val status: String,           // "open" | "committed" | "cancelled"
    val notes: String?,
    @SerializedName("opened_at")
    val openedAt: String,
    @SerializedName("committed_at")
    val committedAt: String?,
    @SerializedName("opened_by_user_id")
    val openedByUserId: Long?,
    @SerializedName("committed_by_user_id")
    val committedByUserId: Long?,
)

/** One scan/count row nested inside GET /stocktake/:id. */
data class StocktakeCountRow(
    val id: Long,
    @SerializedName("stocktake_id")
    val stocktakeId: Long,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long,
    val name: String?,
    val sku: String?,
    @SerializedName("expected_qty")
    val expectedQty: Int,
    @SerializedName("counted_qty")
    val countedQty: Int,
    val variance: Int,
    val notes: String?,
    @SerializedName("counted_at")
    val countedAt: String,
)

/** Variance summary nested inside GET /stocktake/:id. */
data class StocktakeSummary(
    @SerializedName("items_counted")
    val itemsCounted: Int,
    @SerializedName("items_with_variance")
    val itemsWithVariance: Int,
    @SerializedName("total_variance")
    val totalVariance: Int,
    val surplus: Int,
    val shortage: Int,
)

/** Full session detail: session + counts + summary. */
data class StocktakeSessionDetail(
    val session: StocktakeRow,
    val counts: List<StocktakeCountRow>,
    val summary: StocktakeSummary,
)

/** POST /stocktake — open a new session. */
data class StocktakeOpenRequest(
    val name: String,
    val location: String? = null,
    val notes: String? = null,
)

/** POST /stocktake/:id/counts — UPSERT one item count. */
data class StocktakeCountRequest(
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long,
    @SerializedName("counted_qty")
    val countedQty: Int,
    val notes: String? = null,
)

/** Response body from POST /stocktake/:id/counts. */
data class StocktakeCountResult(
    @SerializedName("stocktake_id")
    val stocktakeId: Long,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long,
    val name: String?,
    @SerializedName("expected_qty")
    val expectedQty: Int,
    @SerializedName("counted_qty")
    val countedQty: Int,
    val variance: Int,
)

/** Response body from POST /stocktake/:id/commit. */
data class StocktakeCommitData(
    @SerializedName("stocktake_id")
    val stocktakeId: Long,
    @SerializedName("items_adjusted")
    val itemsAdjusted: Int,
)

/** Response body from POST /stocktake/:id/cancel. */
data class StocktakeCancelData(
    @SerializedName("stocktake_id")
    val stocktakeId: Long,
    val status: String,
)
