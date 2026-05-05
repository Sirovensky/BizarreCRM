package com.bizarreelectronics.crm.ui.screens.expenses

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseApprovalFilter
import com.bizarreelectronics.crm.ui.screens.expenses.components.EmployeeOption
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseFilterState
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
            val query = _state.value.searchQuery.trim()
            val categoryFilter = _state.value.selectedCategory
            val advFilter = _state.value.advancedFilter

            // Choose the narrowest Room flow given active filters.
            // Priority: search query > date range > employee > approval status > category.
            val flow = when {
                query.isNotEmpty() -> expenseRepository.searchExpenses(query)
                advFilter.fromDate.isNotEmpty() || advFilter.toDate.isNotEmpty() ->
                    expenseRepository.getByDateRange(advFilter.fromDate, advFilter.toDate)
                advFilter.selectedEmployeeId != null ->
                    expenseRepository.getByEmployee(advFilter.selectedEmployeeId)
                advFilter.approvalFilter != ExpenseApprovalFilter.ALL ->
                    expenseRepository.getByApprovalStatus(advFilter.approvalFilter.apiValue!!)
                categoryFilter != "All" && categoryFilter != FILTER_PENDING_APPROVAL ->
                    expenseRepository.getByCategory(categoryFilter)
                else -> expenseRepository.getExpenses()
            }

            flow
                .map { expenses ->
                    var result = expenses

                    // Apply category cross-filter when search + category are both active
                    if (query.isNotEmpty() && categoryFilter != "All" && categoryFilter != FILTER_PENDING_APPROVAL) {
                        result = result.filter { it.category.equals(categoryFilter, ignoreCase = true) }
                    }

                    // Pending approval category tab: filter by status == pending
                    if (categoryFilter == FILTER_PENDING_APPROVAL) {
                        result = result.filter { it.approvalStatus == "pending" }
                    }

                    // When date range is active alongside a category filter, narrow further
                    if ((advFilter.fromDate.isNotEmpty() || advFilter.toDate.isNotEmpty()) &&
                        categoryFilter != "All" && categoryFilter != FILTER_PENDING_APPROVAL
                    ) {
                        result = result.filter { it.category.equals(categoryFilter, ignoreCase = true) }
                    }

                    // When employee filter is active via advanced sheet, also apply category
                    if (advFilter.selectedEmployeeId != null &&
                        categoryFilter != "All" && categoryFilter != FILTER_PENDING_APPROVAL
                    ) {
                        result = result.filter { it.category.equals(categoryFilter, ignoreCase = true) }
                    }

                    // Derive the employee chip options from the loaded list so the sheet
                    // always shows employees that actually have expenses.
                    val employeeOptions = buildEmployeeOptions(result)

                    result to employeeOptions
                }
                .catch {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load expenses. Check your connection and try again.",
                    )
                }
                .collectLatest { (expenses, employeeOptions) ->
                    val sorted = sortExpenses(expenses, _state.value.currentSort)
                    _state.value = _state.value.copy(
                        expenses = sorted,
                        totalAmount = sorted.sumOf { it.amount },
                        categorySlices = buildCategorySlices(sorted),
                        reimbursablePendingAmount = sorted
                            .filter { it.approvalStatus == "pending" }
                            .sumOf { it.amount },
                        employeeOptions = employeeOptions,
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

    fun onSortChanged(sort: ExpenseSort) {
        val sorted = sortExpenses(_state.value.expenses, sort)
        _state.value = _state.value.copy(currentSort = sort, expenses = sorted)
    }

    /** Called from [ExpenseFilterSheet] when the user taps "Apply". */
    fun onAdvancedFilterChanged(filter: ExpenseFilterState) {
        _state.value = _state.value.copy(advancedFilter = filter)
        loadExpenses()
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
     * Columns: id, category, amount_dollars, date, description, recorded_by, status
     */
    fun buildCsvContent(): String {
        val sb = StringBuilder()
        sb.appendLine("id,category,amount,date,description,recorded_by,status")
        _state.value.expenses.forEach { e ->
            val amountDollars = "%.2f".format(e.amount / 100.0)
            val desc = (e.description ?: "").replace("\"", "\"\"")
            val user = (e.userName ?: "").replace("\"", "\"\"")
            sb.appendLine(
                "${e.id},${e.category},$amountDollars,${e.date.take(10)},\"$desc\",\"$user\",${e.approvalStatus}",
            )
        }
        return sb.toString()
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun sortExpenses(list: List<ExpenseEntity>, sort: ExpenseSort): List<ExpenseEntity> =
        when (sort) {
            ExpenseSort.DATE -> list.sortedByDescending { it.date }
            ExpenseSort.AMOUNT -> list.sortedByDescending { it.amount }
            ExpenseSort.CATEGORY -> list.sortedBy { it.category }
        }

    /**
     * Derive employee options from the current loaded list.
     * Always includes an "All employees" sentinel (userId = null) as the first entry.
     * Deduplicates by userId; unknown employee rows (userId=null) are excluded from
     * named entries to avoid a "Unknown" chip clutter.
     */
    private fun buildEmployeeOptions(expenses: List<ExpenseEntity>): List<EmployeeOption> {
        val seen = linkedMapOf<Long, String>()
        expenses.forEach { e ->
            if (e.userId != null && !seen.containsKey(e.userId)) {
                seen[e.userId] = e.userName ?: "Employee #${e.userId}"
            }
        }
        val namedOptions = seen.map { (id, name) -> EmployeeOption(userId = id, displayName = name) }
        return if (namedOptions.isEmpty()) emptyList()
        else listOf(EmployeeOption(userId = null, displayName = "All employees")) + namedOptions
    }
}
