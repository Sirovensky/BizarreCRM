package com.bizarreelectronics.crm.ui.screens.expenses

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseSort
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Pending-approval tab pseudo-category constant — never a real DB category. */
internal const val FILTER_PENDING_APPROVAL = "__pending_approval__"

/** Approval status values used in filter sheet + DAO. */
internal object ApprovalStatus {
    const val ALL = ""
    const val PENDING = "pending"
    const val APPROVED = "approved"
    const val DENIED = "denied"
}

@HiltViewModel
class ExpenseListViewModel @Inject constructor(
    private val expenseRepository: ExpenseRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(ExpenseListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        loadExpenses()
    }

    fun loadExpenses() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.expenses.isEmpty(), error = null)
            val current = _state.value
            val query = current.searchQuery.trim()
            val categoryFilter = current.selectedCategory

            // Resolve effective approval status: the quick-tab "pending" pseudo-category
            // maps to the "pending" approval status filter; the advanced filter sheet
            // value overrides otherwise.
            val effectiveApprovalStatus = when {
                categoryFilter == FILTER_PENDING_APPROVAL -> ApprovalStatus.PENDING
                current.approvalStatusFilter.isNotBlank() -> current.approvalStatusFilter
                else -> ApprovalStatus.ALL
            }

            val effectiveCategory = when {
                categoryFilter == "All" || categoryFilter == FILTER_PENDING_APPROVAL -> ""
                else -> categoryFilter
            }

            // Use getFiltered when any advanced filter is active OR when any category/
            // status filter is needed. Fall back to search-only flow for search-only case.
            val flow = when {
                query.isNotEmpty() && effectiveCategory.isEmpty() &&
                    effectiveApprovalStatus.isEmpty() && current.dateFrom.isEmpty() &&
                    current.dateTo.isEmpty() && current.employeeNameFilter.isEmpty() ->
                    expenseRepository.searchExpenses(query)

                else -> expenseRepository.getFiltered(
                    category = effectiveCategory,
                    dateFrom = current.dateFrom,
                    dateTo = current.dateTo,
                    approvalStatus = effectiveApprovalStatus,
                    employeeName = current.employeeNameFilter,
                )
            }

            flow
                .map { expenses ->
                    // If search is active alongside other filters, narrow by text locally
                    if (query.isNotEmpty() && (effectiveCategory.isNotEmpty() ||
                            effectiveApprovalStatus.isNotEmpty() || current.dateFrom.isNotEmpty() ||
                            current.dateTo.isNotEmpty() || current.employeeNameFilter.isNotEmpty())) {
                        expenses.filter { e ->
                            e.description?.contains(query, ignoreCase = true) == true ||
                                e.category.contains(query, ignoreCase = true)
                        }
                    } else {
                        expenses
                    }
                }
                .catch {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load expenses. Check your connection and try again.",
                    )
                }
                .collectLatest { expenses ->
                    val sorted = sortExpenses(expenses, _state.value.currentSort)
                    _state.value = _state.value.copy(
                        expenses = sorted,
                        totalAmount = sorted.sumOf { it.amount },
                        categorySlices = buildCategorySlices(sorted),
                        pendingApprovalCount = sorted.count { it.approvalStatus == ApprovalStatus.PENDING },
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadExpenses()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadExpenses()
        }
    }

    fun onCategoryChanged(category: String) {
        _state.value = _state.value.copy(selectedCategory = category)
        loadExpenses()
    }

    fun onDateFromChanged(date: String) {
        _state.value = _state.value.copy(dateFrom = date)
        loadExpenses()
    }

    fun onDateToChanged(date: String) {
        _state.value = _state.value.copy(dateTo = date)
        loadExpenses()
    }

    fun onApprovalStatusFilterChanged(status: String) {
        _state.value = _state.value.copy(approvalStatusFilter = status)
        loadExpenses()
    }

    fun onEmployeeNameFilterChanged(name: String) {
        _state.value = _state.value.copy(employeeNameFilter = name)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadExpenses()
        }
    }

    fun openFilterSheet() {
        _state.value = _state.value.copy(isFilterSheetOpen = true)
    }

    fun closeFilterSheet() {
        _state.value = _state.value.copy(isFilterSheetOpen = false)
    }

    fun clearAdvancedFilters() {
        _state.value = _state.value.copy(
            dateFrom = "",
            dateTo = "",
            approvalStatusFilter = "",
            employeeNameFilter = "",
            isFilterSheetOpen = false,
        )
        loadExpenses()
    }

    /** True when any advanced filter (date/status/employee) is active. */
    val hasAdvancedFilters: Boolean
        get() = _state.value.let {
            it.dateFrom.isNotBlank() || it.dateTo.isNotBlank() ||
                it.approvalStatusFilter.isNotBlank() || it.employeeNameFilter.isNotBlank()
        }

    fun onSortChanged(sort: ExpenseSort) {
        val sorted = sortExpenses(_state.value.expenses, sort)
        _state.value = _state.value.copy(currentSort = sort, expenses = sorted)
    }

    fun deleteExpense(id: Long) {
        viewModelScope.launch {
            try {
                expenseRepository.deleteExpense(id)
                loadExpenses()
            } catch (_: Exception) {
                // Best-effort: list will refresh on next pull-to-refresh
            }
        }
    }

    fun duplicateExpense(expense: ExpenseEntity) {
        viewModelScope.launch {
            try {
                val request = CreateExpenseRequest(
                    category = expense.category,
                    amount = expense.amount / 100.0,
                    description = expense.description,
                    date = expense.date,
                )
                expenseRepository.createExpense(request)
                loadExpenses()
            } catch (_: Exception) {
                // Best-effort
            }
        }
    }

    /**
     * Builds CSV content from the current expense list.
     * Columns: id, category, amount_dollars, date, description, recorded_by
     */
    fun buildCsvContent(): String {
        val sb = StringBuilder()
        sb.appendLine("id,category,amount,date,description,recorded_by")
        _state.value.expenses.forEach { e ->
            val amountDollars = "%.2f".format(e.amount / 100.0)
            val desc = (e.description ?: "").replace("\"", "\"\"")
            val user = (e.userName ?: "").replace("\"", "\"\"")
            sb.appendLine(
                "${e.id},${e.category},$amountDollars,${e.date.take(10)},\"$desc\",\"$user\"",
            )
        }
        return sb.toString()
    }

    // ── Private helpers ───────────────────────────────────────────────

    private fun sortExpenses(list: List<ExpenseEntity>, sort: ExpenseSort): List<ExpenseEntity> =
        when (sort) {
            ExpenseSort.DATE -> list.sortedByDescending { it.date }
            ExpenseSort.AMOUNT -> list.sortedByDescending { it.amount }
            ExpenseSort.CATEGORY -> list.sortedBy { it.category }
        }
}
