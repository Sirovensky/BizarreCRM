package com.bizarreelectronics.crm.ui.screens.invoices

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
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.util.DateFormatter
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

data class InvoiceListUiState(
    val invoices: List<InvoiceEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedStatus: String = "All",
)

@HiltViewModel
class InvoiceListViewModel @Inject constructor(
    private val invoiceRepository: InvoiceRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(InvoiceListUiState())
    val state = _state.asStateFlow()
    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        loadInvoices()
    }

    fun loadInvoices() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val query = _state.value.searchQuery.trim()
            val statusFilter = _state.value.selectedStatus

            invoiceRepository.getInvoices()
                .map { invoices ->
                    var filtered = invoices
                    // Apply status filter
                    if (statusFilter != "All") {
                        filtered = filtered.filter { it.status.equals(statusFilter, ignoreCase = true) }
                    }
                    // Apply search filter (match on orderId, customerName)
                    if (query.isNotEmpty()) {
                        filtered = filtered.filter { invoice ->
                            invoice.orderId.contains(query, ignoreCase = true) ||
                                (invoice.customerName?.contains(query, ignoreCase = true) == true)
                        }
                    }
                    filtered
                }
                .catch { _ ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load invoices. Check your connection and try again.",
                    )
                }
                .collectLatest { invoices ->
                    _state.value = _state.value.copy(
                        invoices = invoices,
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadInvoices()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadInvoices()
        }
    }

    fun onStatusChanged(status: String) {
        _state.value = _state.value.copy(selectedStatus = status)
        loadInvoices()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvoiceListScreen(
    onInvoiceClick: (Long) -> Unit,
    viewModel: InvoiceListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val statuses = listOf("All", "Paid", "Unpaid", "Partial", "Void")

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Invoices",
                actions = {
                    IconButton(onClick = { viewModel.loadInvoices() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
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
                placeholder = "Search invoices...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statuses) { status ->
                    FilterChip(
                        selected = state.selectedStatus == status,
                        onClick = { viewModel.onStatusChanged(status) },
                        label = { Text(status) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    BrandSkeleton(
                        rows = 6,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(
                            message = state.error ?: "Error loading invoices",
                            onRetry = { viewModel.loadInvoices() },
                        )
                    }
                }
                state.invoices.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Receipt,
                            title = "No invoices found",
                            subtitle = if (state.searchQuery.isNotEmpty() || state.selectedStatus != "All")
                                "Try adjusting your search or filter"
                            else
                                "Invoices will appear here",
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
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.invoices, key = { it.id }) { invoice ->
                                InvoiceListRow(
                                    invoice = invoice,
                                    onClick = { onInvoiceClick(invoice.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InvoiceListRow(invoice: InvoiceEntity, onClick: () -> Unit) {
    BrandCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
    ) {
        BrandListItem(
            headline = {
                Text(
                    invoice.orderId.ifBlank { "INV-?" },
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                    ),
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            },
            support = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        invoice.customerName ?: "Unknown Customer",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        DateFormatter.formatRelative(invoice.createdAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            trailing = {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        invoice.total.formatAsMoney(),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    BrandStatusBadge(
                        label = invoice.status.ifBlank { "Unknown" },
                        status = invoice.status,
                    )
                    if (invoice.amountDue > 0) {
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            "Due: ${invoice.amountDue.formatAsMoney()}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            },
            onClick = onClick,
        )
    }
}
