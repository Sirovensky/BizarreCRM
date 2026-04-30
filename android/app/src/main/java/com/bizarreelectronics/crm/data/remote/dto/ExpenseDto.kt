package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class ExpenseListData(
    val expenses: List<ExpenseListItem>,
    val summary: ExpenseSummary? = null,
    val categories: List<ExpenseCategorySummary>? = null,
    val pagination: Pagination? = null
)

data class ExpenseListItem(
    val id: Long,
    val category: String?,
    val amount: Double?,
    val description: String?,
    val date: String?,
    /** Approval status from server: `pending` | `approved` | `denied`. Server migration 120. */
    val status: String? = null,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
) {
    val userName: String
        get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { "Unknown" }
}

data class ExpenseDetail(
    val id: Long,
    val category: String?,
    val amount: Double?,
    val description: String?,
    val date: String?,
    /** Approval status: `pending` | `approved` | `denied`. Server migration 120. */
    val status: String? = null,
    @SerializedName("receipt_path")
    val receiptPath: String?,
    @SerializedName("user_id")
    val userId: Long?,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
) {
    val userName: String
        get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { "Unknown" }
}

data class ExpenseSummary(
    @SerializedName("total_amount")
    val totalAmount: Double?,
    @SerializedName("total_count")
    val totalCount: Int?,
)

data class ExpenseCategorySummary(
    val category: String?,
    val count: Int?,
    val total: Double?,
)

data class CreateExpenseRequest(
    val category: String,
    val amount: Double,
    val description: String? = null,
    val date: String? = null,
    val reimbursable: Boolean = false,
    @SerializedName("approval_status")
    val approvalStatus: String? = null,
)

/**
 * Request body for POST /api/v1/expenses/mileage.
 * Server computes amount as round(miles * rate_cents) and stores expense_subtype = 'mileage'.
 * Constraints: miles 0–1000, rate_cents 1–50000.
 */
data class CreateMileageExpenseRequest(
    /** Optional vendor / business purpose label. */
    val vendor: String? = null,
    val description: String? = null,
    /** ISO date string (YYYY-MM-DD) of when the mileage was incurred. */
    @SerializedName("incurred_at")
    val incurredAt: String? = null,
    /** Distance in miles (0–1000). */
    val miles: Double,
    /** Reimbursement rate in cents per mile (1–50000). */
    @SerializedName("rate_cents")
    val rateCents: Int,
    /** Expense category; defaults to "Travel" if omitted. */
    val category: String = "Travel",
    @SerializedName("customer_id")
    val customerId: Long? = null,
)

/**
 * Request body for POST /api/v1/expenses/perdiem.
 * Server computes amount as days * rate_cents and stores expense_subtype = 'perdiem'.
 * Constraints: days 1–90, rate_cents 1–50000.
 */
data class CreatePerDiemExpenseRequest(
    val description: String? = null,
    /** ISO date string (YYYY-MM-DD) of the first day. */
    @SerializedName("incurred_at")
    val incurredAt: String? = null,
    /** Number of days (1–90). */
    val days: Int,
    /** Per-diem rate in cents per day (1–50000). */
    @SerializedName("rate_cents")
    val rateCents: Int,
    /** Expense category; defaults to "Per Diem" if omitted. */
    val category: String = "Per Diem",
)

data class UpdateExpenseRequest(
    val category: String? = null,
    val amount: Double? = null,
    val description: String? = null,
    val date: String? = null,
)
