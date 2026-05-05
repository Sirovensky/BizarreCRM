package com.bizarreelectronics.crm.ui.screens.purchaseorders

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.viewmodels.purchaseorders.PO_STATUS_OPTIONS
import com.bizarreelectronics.crm.viewmodels.purchaseorders.PurchaseOrderListViewModel
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurchaseOrderListScreen(
    onPoClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: PurchaseOrderListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Purchase Orders",
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh purchase orders")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create purchase order")
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
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(PO_STATUS_OPTIONS, key = { it }) { status ->
                    val isSelected = if (status == "all") {
                        state.statusFilter == null
                    } else {
                        state.statusFilter == status
                    }
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onStatusFilterChanged(status) },
                        label = { Text(status.replaceFirstChar { it.uppercase() }) },
                        modifier = Modifier.semantics {
                            contentDescription = if (isSelected) "$status filter, selected" else "$status filter"
                        },
                    )
                }
            }

            when {
                state.isLoading -> {
                    BrandSkeleton(rows = 6, modifier = Modifier.padding(top = 8.dp))
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load purchase orders.",
                            onRetry = { viewModel.load() },
                        )
                    }
                }
                state.orders.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            title = "No purchase orders",
                            subtitle = "Tap + to create your first purchase order.",
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn(contentPadding = PaddingValues(bottom = 80.dp)) {
                            items(state.orders, key = { it.id }) { order ->
                                PoListRow(
                                    order = order,
                                    onClick = { onPoClick(order.id) },
                                )
                                BrandListItemDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PoListRow(order: PurchaseOrderRow, onClick: () -> Unit) {
    BrandListItem(
        modifier = Modifier.clickable(onClick = onClick),
        headline = {
            Text(
                order.orderId,
                style = MaterialTheme.typography.titleSmall,
            )
        },
        support = {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (!order.supplierName.isNullOrBlank()) {
                    Text(
                        order.supplierName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                PoStatusBadge(status = order.status)
            }
        },
        trailing = {
            Text(
                "$${String.format(Locale.US, "%.2f", order.total)}",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
        },
    )
}

@Composable
internal fun PoStatusBadge(status: String) {
    val (label, color) = when (status) {
        "draft"       -> "Draft"       to MaterialTheme.colorScheme.onSurfaceVariant
        "pending"     -> "Pending"     to MaterialTheme.colorScheme.secondary
        "ordered"     -> "Ordered"     to MaterialTheme.colorScheme.primary
        "partial"     -> "Partial"     to MaterialTheme.colorScheme.tertiary
        "backordered" -> "Backordered" to MaterialTheme.colorScheme.error
        "received"    -> "Received"    to SuccessGreen
        "cancelled"   -> "Cancelled"   to MaterialTheme.colorScheme.onSurfaceVariant
        else          -> status.replaceFirstChar { it.uppercase() } to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(
        label,
        style = MaterialTheme.typography.labelSmall,
        color = color,
    )
}
