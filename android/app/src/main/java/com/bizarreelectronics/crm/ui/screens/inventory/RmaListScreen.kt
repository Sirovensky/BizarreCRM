package com.bizarreelectronics.crm.ui.screens.inventory

import android.util.Log
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.RmaApi
import com.bizarreelectronics.crm.data.remote.dto.Pagination
import com.bizarreelectronics.crm.data.remote.dto.RmaRow
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────

data class RmaListUiState(
    val rmas: List<RmaRow> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val statusFilter: String? = null,   // null = all
    val pagination: Pagination? = null,
)

/** Filter chip options — mirrors server state-machine values + "all". */
val RMA_STATUS_OPTIONS = listOf("all", "pending", "approved", "shipped", "received", "resolved", "declined")

// ─── ViewModel ─────────────────────────────────────────────────────────────

@HiltViewModel
class RmaListViewModel @Inject constructor(
    private val api: RmaApi,
) : ViewModel() {

    private val _state = MutableStateFlow(RmaListUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = api.listRmas(status = _state.value.statusFilter)
                val rows = if (response.success) response.data ?: emptyList() else emptyList()
                _state.value = _state.value.copy(
                    rmas = rows,
                    isLoading = false,
                    isRefreshing = false,
                )
            } catch (e: Exception) {
                Log.w(TAG, "load failed: ${e.message}")
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = e.message ?: "Failed to load returns",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        load()
    }

    fun onStatusFilterChanged(status: String) {
        _state.value = _state.value.copy(statusFilter = if (status == "all") null else status)
        load()
    }

    companion object { private const val TAG = "RmaListVM" }
}

// ─── Screen ────────────────────────────────────────────────────────────────

/**
 * §61.5 — Vendor Return (RMA) list screen.
 *
 * Shows all RMA requests with status filter chips (pending / approved / shipped /
 * received / resolved / declined). Tapping a row opens the detail sheet (future).
 * FAB opens [RmaCreateScreen].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RmaListScreen(
    onRmaClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    onBack: () -> Unit,
    viewModel: RmaListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Vendor Returns (RMA)",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh RMAs")
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
                Icon(Icons.Default.Add, contentDescription = "Create vendor return")
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
                items(RMA_STATUS_OPTIONS, key = { it }) { option ->
                    val isSelected = if (option == "all") {
                        state.statusFilter == null
                    } else {
                        state.statusFilter == option
                    }
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onStatusFilterChanged(option) },
                        label = { Text(option.replaceFirstChar { it.uppercase() }) },
                        modifier = Modifier.semantics {
                            contentDescription = if (isSelected) "$option filter, selected" else "$option filter"
                        },
                    )
                }
            }

            when {
                state.isLoading -> {
                    BrandSkeleton(rows = 6, modifier = Modifier.padding(top = 8.dp))
                }
                state.error != null -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(
                            message = state.error ?: "Failed to load returns.",
                            onRetry = { viewModel.load() },
                        )
                    }
                }
                state.rmas.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        EmptyState(
                            title = "No vendor returns",
                            subtitle = "Tap + to log a return to a supplier.",
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn(contentPadding = PaddingValues(bottom = 80.dp)) {
                            items(state.rmas, key = { it.id }) { rma ->
                                RmaListRow(rma = rma, onClick = { onRmaClick(rma.id) })
                                BrandListItemDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Row composable ────────────────────────────────────────────────────────

@Composable
private fun RmaListRow(rma: RmaRow, onClick: () -> Unit) {
    BrandListItem(
        modifier = Modifier.clickable(onClick = onClick),
        headline = {
            Text(rma.orderId, style = MaterialTheme.typography.titleSmall)
        },
        support = {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (!rma.supplierName.isNullOrBlank()) {
                    Text(
                        rma.supplierName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RmaStatusBadge(status = rma.status)
                    if (rma.itemCount > 0) {
                        Text(
                            "${rma.itemCount} item${if (rma.itemCount != 1) "s" else ""}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        },
        trailing = {
            if (!rma.trackingNumber.isNullOrBlank()) {
                Text(
                    rma.trackingNumber,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
    )
}

/** Color-coded status label — mirrors server state machine. */
@Composable
internal fun RmaStatusBadge(status: String) {
    val (label, color) = when (status) {
        "pending"  -> "Pending"  to MaterialTheme.colorScheme.secondary
        "approved" -> "Approved" to MaterialTheme.colorScheme.primary
        "shipped"  -> "Shipped"  to MaterialTheme.colorScheme.tertiary
        "received" -> "Received" to SuccessGreen
        "resolved" -> "Resolved" to SuccessGreen
        "declined" -> "Declined" to MaterialTheme.colorScheme.error
        else       -> status.replaceFirstChar { it.uppercase() } to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(label, style = MaterialTheme.typography.labelSmall, color = color)
}
