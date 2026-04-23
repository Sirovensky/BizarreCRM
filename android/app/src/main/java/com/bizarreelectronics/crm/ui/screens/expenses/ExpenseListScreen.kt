package com.bizarreelectronics.crm.ui.screens.expenses

// @audit-fixed: removed clickable import — ExpenseCard no longer has a click target
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
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
    /** Pre-grouped slices for the pie chart; empty = no data for this period. */
    val categorySlices: List<ExpenseSlice> = emptyList(),
)

// Cycling palette for pie slices. Color(Long) is Compose's recommended pattern for
// compile-time color literals; the 0xFF prefix encodes alpha=FF (fully opaque).
private val SLICE_COLORS = listOf(
    Color(0xFF6750A4), // primary purple
    Color(0xFF625B71), // secondary
    Color(0xFF7D5260), // tertiary
    Color(0xFF4CAF50), // green
    Color(0xFF2196F3), // blue
    Color(0xFFFF9800), // amber
    Color(0xFFF44336), // red
    Color(0xFF9C27B0), // purple
    Color(0xFF00BCD4), // cyan
    Color(0xFFFF5722), // deep-orange
    Color(0xFF607D8B), // blue-grey
    Color(0xFF8BC34A), // light-green
    Color(0xFFE91E63), // pink
    Color(0xFF795548), // brown
)

/** Build [ExpenseSlice] list from raw entity list. Pure — safe to call from any thread. */
internal fun buildCategorySlices(expenses: List<ExpenseEntity>): List<ExpenseSlice> {
    if (expenses.isEmpty()) return emptyList()
    // Group and sum, preserving insertion order of first occurrence
    val grouped = linkedMapOf<String, Long>()
    expenses.forEach { e ->
        grouped[e.category] = (grouped[e.category] ?: 0L) + e.amount
    }
    // Sort descending by total so largest slice comes first
    val sorted = grouped.entries.sortedByDescending { it.value }
    return sorted.mapIndexed { idx, entry ->
        ExpenseSlice(
            category = entry.key,
            totalCents = entry.value,
            color = SLICE_COLORS[idx % SLICE_COLORS.size],
        )
    }
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
                        categorySlices = buildCategorySlices(expenses),
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
    var chartExpanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    // ReduceMotion: read once per composition — no AppPreferences injection needed here;
    // fall back to the system animator scale check only (in-app toggle not wired at this level).
    val reduceMotion = remember(context) {
        android.provider.Settings.Global.getFloat(
            context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Expenses",
                actions = {
                    IconButton(onClick = { viewModel.loadExpenses() }) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = "Refresh",
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create expense")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // Brand search bar: filled surface2, 16dp radius, teal leading icon
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search expenses...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(categories, key = { it }) { category ->
                    FilterChip(
                        selected = state.selectedCategory == category,
                        onClick = { viewModel.onCategoryChanged(category) },
                        label = { Text(category) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Summary card — sanctioned highlight usage of primaryContainer
            if (!state.isLoading) {
                BrandCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
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
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                state.totalAmount.formatAsMoney(),
                                style = MaterialTheme.typography.headlineSmall,
                                // BrandMono via fontFamily copy — amount is a financial figure
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                "Count",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "${state.expenses.size}",
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }

            // Collapsible "By category" section — shows pie chart when expanded
            if (!state.isLoading && state.error == null) {
                Spacer(modifier = Modifier.height(4.dp))
                BrandCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) {
                    Column {
                        // Header row — tap to toggle
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { chartExpanded = !chartExpanded }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = "By category",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Icon(
                                imageVector = if (chartExpanded) {
                                    Icons.Default.KeyboardArrowUp
                                } else {
                                    Icons.Default.KeyboardArrowDown
                                },
                                contentDescription = if (chartExpanded) {
                                    "Collapse category chart"
                                } else {
                                    "Expand category chart"
                                },
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        // Animated chart content
                        AnimatedVisibility(
                            visible = chartExpanded,
                            enter = expandVertically(),
                            exit = shrinkVertically(),
                        ) {
                            ExpenseCategoryPieChart(
                                slices = state.categorySlices,
                                modifier = Modifier.padding(
                                    start = 16.dp,
                                    end = 16.dp,
                                    bottom = 16.dp,
                                ),
                                reduceMotion = reduceMotion,
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    // Skeleton rows while data loads — replaces bare CircularProgressIndicator
                    BrandSkeleton(rows = 6, modifier = Modifier.fillMaxWidth())
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(
                            message = state.error ?: "Unknown error",
                            onRetry = { viewModel.loadExpenses() },
                        )
                    }
                }
                state.expenses.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                        EmptyState(
                            icon = Icons.Default.AttachMoney,
                            title = "No expenses found",
                            subtitle = if (state.searchQuery.isNotEmpty() || state.selectedCategory != "All") {
                                "Try adjusting your filters"
                            } else {
                                "Tap + to record your first expense"
                            },
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            // CROSS16-ext: bottom inset so the last row can
                            // scroll above the bottom-nav / gesture area.
                            contentPadding = PaddingValues(
                                start = 16.dp,
                                end = 16.dp,
                                top = 8.dp,
                                bottom = 80.dp,
                            ),
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
    BrandCard(modifier = Modifier.fillMaxWidth()) {
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
            // Amount: right-aligned, labelLarge, primary purple — brand money value treatment
            Text(
                expense.amount.formatAsMoney(),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}
