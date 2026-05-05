package com.bizarreelectronics.crm.ui.screens.expenses

// @audit-fixed: removed clickable import — ExpenseCard no longer has a click target
import android.app.Activity
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.expenses.components.EmployeeOption
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseFilterSheet
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseFilterState
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseSort
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseSortDropdown
import com.bizarreelectronics.crm.util.formatAsMoney
import kotlinx.coroutines.launch

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
    /**
     * Sum of all expenses whose [ExpenseEntity.status] == "pending", in **cents**.
     * Computed by the ViewModel from the loaded entity list once the `status`
     * column is present (Room migration 12 → 13).
     */
    val reimbursablePendingAmount: Long = 0L,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedCategory: String = "All",
    val currentSort: ExpenseSort = ExpenseSort.DATE,
    /** Pre-grouped slices for the pie chart; empty = no data for this period. */
    val categorySlices: List<ExpenseSlice> = emptyList(),
    /** Advanced filter state (date range / employee / approval status). */
    val advancedFilter: ExpenseFilterState = ExpenseFilterState(),
    /**
     * Employee options derived from the loaded expense list.
     * Empty = no named employees in the current view; the filter button is
     * still shown for date-range / status filters.
     */
    val employeeOptions: List<EmployeeOption> = emptyList(),
)

// TODO: cream-theme — pick token — chart-specific cycling palette; no single theme token maps to a multi-hue sequence
private val SLICE_COLORS = listOf(
    Color(0xFF6750A4),
    Color(0xFF625B71),
    Color(0xFF7D5260),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFF44336),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
    Color(0xFF607D8B),
    Color(0xFF8BC34A),
    Color(0xFFE91E63),
    Color(0xFF795548),
)

/** Build [ExpenseSlice] list from raw entity list. Pure — safe to call from any thread. */
internal fun buildCategorySlices(expenses: List<ExpenseEntity>): List<ExpenseSlice> {
    if (expenses.isEmpty()) return emptyList()
    val grouped = linkedMapOf<String, Long>()
    expenses.forEach { e ->
        grouped[e.category] = (grouped[e.category] ?: 0L) + e.amount
    }
    val sorted = grouped.entries.sortedByDescending { it.value }
    return sorted.mapIndexed { idx, entry ->
        ExpenseSlice(
            category = entry.key,
            totalCents = entry.value,
            color = SLICE_COLORS[idx % SLICE_COLORS.size],
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ExpenseListScreen(
    onCreateClick: () -> Unit,
    onDetailClick: (Long) -> Unit = {},
    viewModel: ExpenseListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val categories = listOf("All") + EXPENSE_CATEGORIES + listOf(FILTER_PENDING_APPROVAL)
    var chartExpanded by remember { mutableStateOf(false) }
    var showFilterSheet by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val reduceMotion = remember(context) {
        android.provider.Settings.Global.getFloat(
            context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }

    // Advanced filter sheet
    if (showFilterSheet) {
        ExpenseFilterSheet(
            filterState = state.advancedFilter,
            employeeOptions = state.employeeOptions,
            onFilterChanged = { viewModel.onAdvancedFilterChanged(it) },
            onDismiss = { showFilterSheet = false },
        )
    }

    // SAF launcher for CSV export
    val csvLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val uri = result.data?.data
            if (uri != null) {
                scope.launch {
                    try {
                        val csv = viewModel.buildCsvContent()
                        context.contentResolver.openOutputStream(uri)?.use { os ->
                            os.write(csv.toByteArray(Charsets.UTF_8))
                        }
                        snackbarHostState.showSnackbar("CSV exported")
                    } catch (e: Exception) {
                        snackbarHostState.showSnackbar("Export failed: ${e.message}")
                    }
                }
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Expenses",
                actions = {
                    // Advanced filter button — badge when any advanced filter is active
                    BadgedBox(
                        badge = {
                            if (state.advancedFilter.isActive) {
                                Badge()
                            }
                        },
                    ) {
                        IconButton(onClick = { showFilterSheet = true }) {
                            Icon(
                                Icons.Outlined.FilterList,
                                contentDescription = if (state.advancedFilter.isActive)
                                    "Advanced filters (active)"
                                else
                                    "Advanced filters",
                            )
                        }
                    }
                    // Sort dropdown
                    ExpenseSortDropdown(
                        currentSort = state.currentSort,
                        onSortSelected = { viewModel.onSortChanged(it) },
                    )
                    // Export CSV
                    IconButton(
                        onClick = {
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "text/csv"
                                putExtra(Intent.EXTRA_TITLE, "expenses.csv")
                            }
                            csvLauncher.launch(intent)
                        },
                    ) {
                        Icon(Icons.Default.FileDownload, contentDescription = "Export expenses as CSV")
                    }
                    IconButton(onClick = { viewModel.loadExpenses() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh expenses")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add expense")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Category, description, date…",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            Text(
                "Category filter",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(categories, key = { it }) { category ->
                    val isSelected = state.selectedCategory == category
                    val label = if (category == FILTER_PENDING_APPROVAL) "Pending approval" else category
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onCategoryChanged(category) },
                        label = { Text(label) },
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) "$label filter, selected" else "$label filter, not selected"
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Summary tiles
            if (!state.isLoading) {
                val summaryPeriodLabel = when (state.selectedCategory) {
                    "All" -> "All expenses"
                    FILTER_PENDING_APPROVAL -> "Pending approval expenses"
                    else -> "${state.selectedCategory} expenses"
                }
                val summaryA11yDesc = "$summaryPeriodLabel: ${state.totalAmount.formatAsMoney()}, " +
                    "${state.expenses.size} items"
                BrandCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = summaryA11yDesc
                        },
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
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "Reimbursable pending",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                state.reimbursablePendingAmount.formatAsMoney(),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.tertiary,
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

            // Collapsible "By category" section
            if (!state.isLoading && state.error == null) {
                Spacer(modifier = Modifier.height(4.dp))
                BrandCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) {
                    Column {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { chartExpanded = !chartExpanded }
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                                .semantics {
                                    role = Role.Button
                                    contentDescription = if (chartExpanded) {
                                        "By category, expanded. Tap to collapse."
                                    } else {
                                        "By category, collapsed. Tap to expand."
                                    }
                                },
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
                                imageVector = if (chartExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        AnimatedVisibility(
                            visible = chartExpanded,
                            enter = expandVertically(),
                            exit = shrinkVertically(),
                        ) {
                            ExpenseCategoryPieChart(
                                slices = state.categorySlices,
                                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                                reduceMotion = reduceMotion,
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading expenses"
                        },
                    ) {
                        BrandSkeleton(rows = 6, modifier = Modifier.fillMaxWidth())
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Unknown error",
                            onRetry = { viewModel.loadExpenses() },
                        )
                    }
                }
                state.expenses.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.TopCenter,
                    ) {
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
                            contentPadding = PaddingValues(
                                start = 16.dp,
                                end = 16.dp,
                                top = 8.dp,
                                bottom = 80.dp,
                            ),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.expenses, key = { it.id }) { expense ->
                                SwipeableExpenseCard(
                                    expense = expense,
                                    onClick = { onDetailClick(expense.id) },
                                    onApprove = { /* stub: only in detail screen */ },
                                    onReject = { /* stub: only in detail screen */ },
                                    onDelete = { viewModel.deleteExpense(expense.id) },
                                    onDuplicate = { viewModel.duplicateExpense(expense) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SwipeableExpenseCard(
    expense: ExpenseEntity,
    onClick: () -> Unit,
    onApprove: () -> Unit,
    onReject: () -> Unit,
    onDelete: () -> Unit,
    onDuplicate: () -> Unit,
) {
    var showContextMenu by remember { mutableStateOf(false) }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    onApprove()
                    false // Don't dismiss — approval is handled by approval bar in detail
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    onReject()
                    false
                }
                else -> false
            }
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            when (direction) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    // Approve background (green)
                    val successColor = LocalExtendedColors.current.success
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(vertical = 2.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Surface(
                            color = successColor.copy(alpha = 0.15f),
                            modifier = Modifier.fillMaxSize(),
                        ) {}
                        Row(
                            modifier = Modifier.padding(start = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(Icons.Default.Check, contentDescription = null, tint = successColor)
                            Text("Approve", color = successColor, style = MaterialTheme.typography.labelLarge)
                        }
                    }
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    // Reject background (red)
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(vertical = 2.dp),
                        contentAlignment = Alignment.CenterEnd,
                    ) {
                        Surface(
                            color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.4f),
                            modifier = Modifier.fillMaxSize(),
                        ) {}
                        Row(
                            modifier = Modifier.padding(end = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(Icons.Default.Close, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                            Text("Reject", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelLarge)
                        }
                    }
                }
                else -> {}
            }
        },
    ) {
        Box {
            ExpenseCard(
                expense = expense,
                modifier = Modifier.combinedClickable(
                    onClick = onClick,
                    onLongClick = { showContextMenu = true },
                ),
            )
            // Long-press context menu
            DropdownMenu(
                expanded = showContextMenu,
                onDismissRequest = { showContextMenu = false },
            ) {
                DropdownMenuItem(
                    text = { Text("Open") },
                    onClick = { showContextMenu = false; onClick() },
                    leadingIcon = { Icon(Icons.Default.OpenInNew, contentDescription = null) },
                )
                DropdownMenuItem(
                    text = { Text("Duplicate") },
                    onClick = { showContextMenu = false; onDuplicate() },
                    leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
                )
                DropdownMenuItem(
                    text = { Text("Delete") },
                    onClick = { showContextMenu = false; onDelete() },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                    },
                )
            }
        }
    }
}

@Composable
private fun ExpenseCard(
    expense: ExpenseEntity,
    modifier: Modifier = Modifier,
) {
    val vendorOrNote = expense.description?.takeIf { it.isNotBlank() } ?: ""
    val expenseA11yDesc = buildString {
        append("Expense ${expense.amount.formatAsMoney()}")
        append(" for ${expense.category}")
        append(", on ${expense.date.take(10)}")
        if (vendorOrNote.isNotBlank()) append(", $vendorOrNote")
        if (!expense.userName.isNullOrBlank()) append(", ${expense.userName}")
        append(".")
    }
    BrandCard(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = expenseA11yDesc
            },
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
                    Text(expense.description, style = MaterialTheme.typography.bodyMedium)
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
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}
