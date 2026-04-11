package com.bizarreelectronics.crm.ui.screens.expenses

// @audit-fixed: removed clickable import — ExpenseCard no longer has a click target
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.util.formatAsMoney
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

val EXPENSE_CATEGORIES = listOf(
    "Rent",
    "Utilities",
    "Parts & Supplies",
    "Tools & Equipment",
    "Marketing",
    "Insurance",
    "Payroll",
    "Software",
    "Office Supplies",
    "Shipping",
    "Travel",
    "Maintenance",
    "Taxes & Fees",
    "Other",
)

data class ExpenseListUiState(
    val expenses: List<ExpenseEntity> = emptyList(),
    /** Total of all expenses shown in the list, in **cents**. */
    val totalAmount: Long = 0L,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedCategory: String = "All",
)

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
                categoryFilter != "All" -> expenseRepository.getByCategory(categoryFilter)
                else -> expenseRepository.getExpenses()
            }

            flow
                .map { expenses ->
                    // If searching AND a category is selected, narrow further in-memory
                    if (query.isNotEmpty() && categoryFilter != "All") {
                        expenses.filter { it.category.equals(categoryFilter, ignoreCase = true) }
                    } else {
                        expenses
                    }
                }
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load expenses. Check your connection and try again.",
                    )
                }
                .collectLatest { expenses ->
                    _state.value = _state.value.copy(
                        expenses = expenses,
                        totalAmount = expenses.sumOf { it.amount },
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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseListScreen(
    onCreateClick: () -> Unit,
    viewModel: ExpenseListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val categories = listOf("All") + EXPENSE_CATEGORIES

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Expenses")
                        if (!state.isLoading) {
                            Text(
                                "Total: ${state.totalAmount.formatAsMoney()}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.loadExpenses() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create Expense")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search expenses...") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                singleLine = true,
                trailingIcon = {
                    if (state.searchQuery.isNotEmpty()) {
                        IconButton(onClick = { viewModel.onSearchChanged("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear")
                        }
                    }
                },
            )

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(categories) { category ->
                    FilterChip(
                        selected = state.selectedCategory == category,
                        onClick = { viewModel.onCategoryChanged(category) },
                        label = { Text(category) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Summary card
            if (!state.isLoading) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text(
                                "Total",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                            Text(
                                state.totalAmount.formatAsMoney(),
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                "Count",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                            Text(
                                "${state.expenses.size}",
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.height(8.dp))
                            TextButton(onClick = { viewModel.loadExpenses() }) { Text("Retry") }
                        }
                    }
                }
                state.expenses.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.AttachMoney,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "No expenses found",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            // @audit-fixed: ExpenseCard previously had an empty onClick {}
                            // which left every row with a dead Modifier.clickable that
                            // produced ripples but did nothing. There is no expense detail
                            // screen yet, so the rows now use a non-clickable card variant.
                            items(state.expenses, key = { it.id }) { expense ->
                                ExpenseCard(expense = expense)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ExpenseCard(expense: ExpenseEntity) {
    Card(
        modifier = Modifier
            .fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                AssistChip(
                    onClick = {},
                    label = { Text(expense.category, style = MaterialTheme.typography.labelSmall) },
                )
                Spacer(modifier = Modifier.height(4.dp))
                if (!expense.description.isNullOrBlank()) {
                    Text(
                        expense.description,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                Text(
                    expense.date.take(10),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (!expense.userName.isNullOrBlank()) {
                    Text(
                        expense.userName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                expense.amount.formatAsMoney(),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
