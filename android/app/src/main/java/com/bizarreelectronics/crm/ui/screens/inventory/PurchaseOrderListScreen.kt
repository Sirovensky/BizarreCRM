package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import javax.inject.Inject

data class PoListUiState(
    val orders: List<PurchaseOrderRow> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val statusFilter: String? = null,
    val page: Int = 1,
    val hasMore: Boolean = false,
)

@HiltViewModel
class PurchaseOrderListViewModel @Inject constructor(
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val _state = MutableStateFlow(PoListUiState())
    val state = _state.asStateFlow()

    private val currency = NumberFormat.getCurrencyInstance(Locale.US)

    init { load() }

    fun setStatusFilter(status: String?) {
        _state.value = _state.value.copy(statusFilter = status, orders = emptyList(), page = 1)
        load()
    }

    fun load(page: Int = 1) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val resp = inventoryApi.getPurchaseOrders(
                    page = page,
                    status = _state.value.statusFilter,
                )
                val data = resp.data ?: return@launch
                val orders = if (page == 1) data.orders else _state.value.orders + data.orders
                val totalPages = data.pagination?.totalPages ?: 1
                _state.value = _state.value.copy(
                    orders = orders,
                    isLoading = false,
                    page = page,
                    hasMore = page < totalPages,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load purchase orders",
                )
            }
        }
    }

    fun loadNextPage() {
        if (!_state.value.hasMore || _state.value.isLoading) return
        load(_state.value.page + 1)
    }

    fun formatAmount(value: Double?): String =
        if (value == null) "—" else currency.format(value)
}

private val STATUS_FILTERS = listOf(null, "draft", "ordered", "partial", "received", "cancelled")
private val STATUS_LABELS = mapOf(
    null to "All",
    "draft" to "Draft",
    "ordered" to "Ordered",
    "partial" to "Partial",
    "received" to "Received",
    "cancelled" to "Cancelled",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurchaseOrderListScreen(
    onBack: () -> Unit,
    onPoClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: PurchaseOrderListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_purchase_orders),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.cd_back))
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onCreateClick) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.cd_create_po))
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Status filter chips
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            ) {
                items(STATUS_FILTERS) { status ->
                    FilterChip(
                        selected = state.statusFilter == status,
                        onClick = { viewModel.setStatusFilter(status) },
                        label = { Text(STATUS_LABELS[status] ?: "") },
                    )
                }
            }

            when {
                state.isLoading && state.orders.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null && state.orders.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                state.error ?: "Error",
                                color = MaterialTheme.colorScheme.error,
                            )
                            Spacer(Modifier.height(8.dp))
                            FilledTonalButton(onClick = { viewModel.load() }) { Text("Retry") }
                        }
                    }
                }
                state.orders.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "No purchase orders",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Tap + to create one",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                else -> {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(state.orders, key = { it.id }) { po ->
                            PoListItem(
                                po = po,
                                formatAmount = viewModel::formatAmount,
                                onClick = { onPoClick(po.id) },
                            )
                            HorizontalDivider()
                        }
                        if (state.hasMore) {
                            item {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    LaunchedEffect(Unit) { viewModel.loadNextPage() }
                                    CircularProgressIndicator(modifier = Modifier.size(24.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PoListItem(
    po: PurchaseOrderRow,
    formatAmount: (Double?) -> String,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = {
            Text(po.orderId ?: "PO #${po.id}")
        },
        supportingContent = {
            Text(po.supplierName ?: "—")
        },
        trailingContent = {
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    formatAmount(po.total),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.height(4.dp))
                PoStatusChip(status = po.status ?: "draft")
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick),
        overlineContent = po.expectedDate?.let {
            { Text("Expected: $it", style = MaterialTheme.typography.labelSmall) }
        },
    )
}

@Composable
internal fun PoStatusChip(status: String) {
    val (containerColor, label) = when (status) {
        "draft"     -> MaterialTheme.colorScheme.surfaceVariant to "Draft"
        "ordered"   -> MaterialTheme.colorScheme.primaryContainer to "Ordered"
        "partial"   -> MaterialTheme.colorScheme.secondaryContainer to "Partial"
        "received"  -> MaterialTheme.colorScheme.tertiaryContainer to "Received"
        "cancelled" -> MaterialTheme.colorScheme.errorContainer to "Cancelled"
        else        -> MaterialTheme.colorScheme.surfaceVariant to status.replaceFirstChar { it.uppercase() }
    }
    Surface(
        shape = MaterialTheme.shapes.small,
        color = containerColor,
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
        )
    }
}
