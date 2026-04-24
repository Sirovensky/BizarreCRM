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

            val flow = when {
                query.isNotEmpty() -> expenseRepository.searchExpenses(query)
                categoryFilter != "All" && categoryFilter != FILTER_PENDING_APPROVAL ->
                    expenseRepository.getByCategory(categoryFilter)
                else -> expenseRepository.getExpenses()
            }

            flow
                .map { expenses ->
                    var result = expenses
                    // Narrow by category if both search + category active
                    if (query.isNotEmpty() && categoryFilter != "All" && categoryFilter != FILTER_PENDING_APPROVAL) {
                        result = result.filter { it.category.equals(categoryFilter, ignoreCase = true) }
                    }
                    // Pending approval filter: stub — no status column in entity yet,
                    // so we show all for now (placeholder for when status is wired)
                    // This keeps the tab visible without crashing.
                    result
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
                        reimbursablePendingAmount = 0L, // stub: no reimbursable column yet
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
