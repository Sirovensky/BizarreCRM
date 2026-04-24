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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.ui.components.WaveDivider
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
    onCreateClick: (() -> Unit)? = null,
    viewModel: InvoiceListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val statuses = listOf("All", "Paid", "Unpaid", "Partial", "Void")

    Scaffold(
        floatingActionButton = {
            if (onCreateClick != null) {
                FloatingActionButton(
                    onClick = onCreateClick,
                    modifier = Modifier.semantics { contentDescription = "Create new invoice" },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                }
            }
        },
        floatingActionButtonPosition = FabPosition.End,
        topBar = {
            // CROSS45: WaveDivider docked directly below the TopAppBar — canonical
            // placement for every list screen so the branded moment sits at the
            // end-of-header seam, not floating mid-content.
            Column {
                BrandTopAppBar(
                    title = "Invoices",
                    actions = {
                        IconButton(onClick = { viewModel.loadInvoices() }) {
                            // a11y: "Refresh invoices" is more specific than generic "Refresh"
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh invoices")
                        }
                    },
                )
                WaveDivider()
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
                placeholder = "Search invoices...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // a11y: "Status filter" heading so TalkBack can navigate directly to this section
            Text(
                "Status filter",
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
                items(statuses, key = { it }) { status ->
                    val isSelected = state.selectedStatus == status
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onStatusChanged(status) },
                        label = { Text(status) },
                        // a11y: Role.Tab + selection state announcement; the chip's
                        // selected param already flips the chip visually; the
                        // semantics here make TalkBack say "<status> filter, selected/not selected"
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) {
                                "$status filter, selected"
                            } else {
                                "$status filter, not selected"
                            }
                        },
                    )
                }
            }

            // Invoice count pill — appears after the filter row when data is loaded
            if (!state.isLoading && state.invoices.isNotEmpty()) {
                val invoiceCount = state.invoices.size
                val invoiceCountLabel = "$invoiceCount ${if (invoiceCount == 1) "invoice" else "invoices"}"
                Text(
                    invoiceCountLabel,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 2.dp)
                        // a11y: liveRegion=Polite so TalkBack announces the updated count
                        // when a filter or search query changes the result set, without interrupting.
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = invoiceCountLabel
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription so TalkBack announces
                    // "Loading invoices" on a single focus stop rather than reading
                    // each shimmer box individually.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading invoices"
                        },
                    ) {
                        BrandSkeleton(
                            rows = 6,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive interrupts TalkBack immediately so the
                    // user is not left wondering why the list is empty after a network failure.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
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
                        // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                        // into one TalkBack node so the empty state reads as a single announcement.
                        Box(modifier = Modifier.semantics(mergeDescendants = true) {}) {
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
    // a11y: build the full announcement string once so it can be used in semantics.
    // BrandCard(onClick) carries Material 3 Card Role.Button semantics; the inner
    // BrandListItem also applies mergeDescendants=true + Role.Button on its Row.
    // We add contentDescription on the BrandCard modifier so TalkBack announces a
    // single coherent sentence instead of reading each child Text node individually.
    val a11yDesc = buildString {
        append("Invoice #${invoice.orderId.ifBlank { "?" }}")
        invoice.customerName?.takeIf { it.isNotBlank() }?.let { append(" for $it") }
        append(", ${invoice.total.formatAsMoney()}")
        append(", ${invoice.status.ifBlank { "Unknown" }}")
        val dateStr = DateFormatter.formatRelative(invoice.createdAt)
        if (dateStr.isNotBlank()) append(", dated $dateStr")
        append(". Tap to open.")
    }

    BrandCard(
        // a11y: contentDescription overrides merged child-text reading; 48dp floor
        // ensures the row meets the Material 3 minimum touch target.
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .semantics { contentDescription = a11yDesc },
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
                // a11y: visual-only trailing column. The BrandCard modifier-level
                // contentDescription already announces invoice number + customer + amount
                // + status for TalkBack; these child composables are decorative within
                // the merged row node.
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
