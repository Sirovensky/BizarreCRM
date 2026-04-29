package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ── Response shapes ──────────────────────────────────────────────────────────

/**
 * List-page wrapper returned by `GET /api/v1/recurring-invoices`.
 */
data class RecurringInvoiceListData(
    val templates: List<RecurringInvoiceItem>,
    val total: Int?,
    val page: Int?,
    @SerializedName("pagesize")
    val pageSize: Int?,
)

/**
 * Summary row in the template list.
 *
 * [status]: "active" | "paused" | "cancelled"
 * [intervalKind]: "daily" | "weekly" | "monthly" | "yearly"
 */
data class RecurringInvoiceItem(
    val id: Long,
    val name: String,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_name")
    val customerName: String?,
    @SerializedName("interval_kind")
    val intervalKind: String,
    @SerializedName("interval_count")
    val intervalCount: Int,
    @SerializedName("start_date")
    val startDate: String?,
    @SerializedName("next_run_at")
    val nextRunAt: String?,
    val status: String,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("line_items")
    val lineItems: List<RecurringInvoiceLineItem>?,
)

/** Full template detail with last 20 run records. */
data class RecurringInvoiceDetail(
    val id: Long,
    val name: String,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_name")
    val customerName: String?,
    @SerializedName("interval_kind")
    val intervalKind: String,
    @SerializedName("interval_count")
    val intervalCount: Int,
    @SerializedName("start_date")
    val startDate: String?,
    @SerializedName("next_run_at")
    val nextRunAt: String?,
    val status: String,
    @SerializedName("notes_template")
    val notesTemplate: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("line_items")
    val lineItems: List<RecurringInvoiceLineItem>,
    val runs: List<RecurringInvoiceRun>?,
)

/** A single line-item within a recurring-invoice template. */
data class RecurringInvoiceLineItem(
    val id: Long?,
    val description: String,
    val quantity: Int,
    @SerializedName("unit_price_cents")
    val unitPriceCents: Long,
    @SerializedName("tax_class_id")
    val taxClassId: Long?,
)

/** One execution record from `invoice_template_runs`. */
data class RecurringInvoiceRun(
    val id: Long,
    @SerializedName("invoice_id")
    val invoiceId: Long?,
    val succeeded: Boolean,
    @SerializedName("error_message")
    val errorMessage: String?,
    @SerializedName("created_at")
    val createdAt: String?,
)

// ── Request shapes ────────────────────────────────────────────────────────────

/**
 * Body for `POST /api/v1/recurring-invoices`.
 *
 * Server requires: non-blank [name], valid [customerId], valid [intervalKind],
 * [intervalCount] >= 1, [startDate] ISO date, at least one [lineItems] entry.
 */
data class CreateRecurringInvoiceRequest(
    val name: String,
    @SerializedName("customer_id")
    val customerId: Long,
    @SerializedName("interval_kind")
    val intervalKind: String,
    @SerializedName("interval_count")
    val intervalCount: Int,
    @SerializedName("start_date")
    val startDate: String,
    @SerializedName("line_items")
    val lineItems: List<RecurringInvoiceLineItemRequest>,
    @SerializedName("notes_template")
    val notesTemplate: String? = null,
)

/** Line-item body sent when creating or patching a template. */
data class RecurringInvoiceLineItemRequest(
    val description: String,
    val quantity: Int,
    @SerializedName("unit_price_cents")
    val unitPriceCents: Long,
    @SerializedName("tax_class_id")
    val taxClassId: Long? = null,
)

/**
 * Body for `PATCH /api/v1/recurring-invoices/:id`.
 *
 * All fields optional — send only those that should change.
 */
data class PatchRecurringInvoiceRequest(
    val status: String? = null,
    @SerializedName("next_run_at")
    val nextRunAt: String? = null,
    @SerializedName("notes_template")
    val notesTemplate: String? = null,
    @SerializedName("line_items")
    val lineItems: List<RecurringInvoiceLineItemRequest>? = null,
)
