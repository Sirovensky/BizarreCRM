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
    /** Approval status: `pending` | `approved` | `denied`. Server migration 120. */
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

data class UpdateExpenseRequest(
    val category: String? = null,
    val amount: Double? = null,
    val description: String? = null,
    val date: String? = null,
)
