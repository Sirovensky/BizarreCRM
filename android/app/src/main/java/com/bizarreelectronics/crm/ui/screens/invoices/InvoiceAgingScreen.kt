package com.bizarreelectronics.crm.ui.screens.invoices

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.AgingBucket
import com.bizarreelectronics.crm.data.remote.dto.AgingInvoiceRow
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ── UiState ───────────────────────────────────────────────────────────────────

private val BUCKET_ORDER = listOf("0-30", "31-60", "61-90", "90+")
private val BUCKET_LABELS = mapOf(
    "0-30"  to "0 – 30 days",
    "31-60" to "31 – 60 days",
    "61-90" to "61 – 90 days",
    "90+"   to "90 + days",
)

data class AgingUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val buckets: Map<String, AgingBucket> = emptyMap(),
    val invoices: List<AgingInvoiceRow> = emptyList(),
    /** Currently selected bucket filter; null = All */
    val selectedBucket: String? = null,
)

/** Invoices after applying the bucket filter. */
private fun AgingUiState.filteredInvoices(): List<AgingInvoiceRow> =
    if (selectedBucket == null) invoices
    else invoices.filter { it.bucket == selectedBucket }

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class InvoiceAgingViewModel @Inject constructor(
    private val invoiceApi: InvoiceApi,
) : ViewModel() {

    private val _state = MutableStateFlow(AgingUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = !isRefresh,
                isRefreshing = isRefresh,
                error = null,
            )
            runCatching { invoiceApi.getAgingReport() }
                .onSuccess { resp ->
                    val data = resp.data
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        buckets = data?.buckets ?: emptyMap(),
                        invoices = data?.invoices ?: emptyList(),
                    )
                }
                .onFailure { ex ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = ex.message ?: "Failed to load aging report",
                    )
                }
        }
    }

    fun onBucketSelected(bucket: String?) {
        _state.value = _state.value.copy(selectedBucket = bucket)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvoiceAgingScreen(
    onBack: () -> Unit,
    onInvoiceClick: ((Long) -> Unit)? = null,
    viewModel: InvoiceAgingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Accounts Receivable Aging",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Error loading report",
                        onRetry = { viewModel.load() },
                    )
                }
            }
            else -> {
                PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = { viewModel.load(isRefresh = true) },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    AgingContent(
                        state = state,
                        onBucketSelected = viewModel::onBucketSelected,
                        onInvoiceClick = onInvoiceClick,
                    )
                }
            }
        }
    }
}

@Composable
private fun AgingContent(
    state: AgingUiState,
    onBucketSelected: (String?) -> Unit,
    onInvoiceClick: ((Long) -> Unit)?,
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        // ── Bucket summary cards ─────────────────────────────────────────────
        item {
            Text(
                "Summary",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                BUCKET_ORDER.forEach { key ->
                    val bucket = state.buckets[key] ?: AgingBucket()
                    AgingBucketCard(
                        label = BUCKET_LABELS[key] ?: key,
                        count = bucket.count,
                        totalCents = bucket.totalCents,
                        isSelected = state.selectedBucket == key,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            onBucketSelected(if (state.selectedBucket == key) null else key)
                        },
                    )
                }
            }
        }

        // ── Filter chips ─────────────────────────────────────────────────────
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    FilterChip(
                        selected = state.selectedBucket == null,
                        onClick = { onBucketSelected(null) },
                        label = { Text("All") },
                    )
                }
                items(BUCKET_ORDER, key = { it }) { key ->
                    FilterChip(
                        selected = state.selectedBucket == key,
                        onClick = {
                            onBucketSelected(if (state.selectedBucket == key) null else key)
                        },
                        label = { Text(BUCKET_LABELS[key] ?: key) },
                    )
                }
            }
        }

        // ── Invoice rows ─────────────────────────────────────────────────────
        item {
            val count = state.filteredInvoices().size
            Text(
                "$count invoice${if (count != 1) "s" else ""}",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        val visible = state.filteredInvoices()
        if (visible.isEmpty()) {
            item {
                EmptyState(title = "No overdue invoices in this range")
            }
        } else {
            items(visible, key = { it.id }) { row ->
                AgingInvoiceRowCard(
                    row = row,
                    onClick = { onInvoiceClick?.invoke(row.id) },
                )
            }
        }
    }
}

@Composable
private fun AgingBucketCard(
    label: String,
    count: Int,
    totalCents: Long,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Card(
        modifier = modifier,
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = if (isSelected)
                    MaterialTheme.colorScheme.onPrimaryContainer
                else
                    MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                totalCents.formatAsMoney(),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = if (isSelected)
                    MaterialTheme.colorScheme.onPrimaryContainer
                else
                    MaterialTheme.colorScheme.onSurface,
            )
            Text(
                "$count inv.",
                style = MaterialTheme.typography.labelSmall,
                color = if (isSelected)
                    MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                else
                    MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun AgingInvoiceRowCard(
    row: AgingInvoiceRow,
    onClick: () -> Unit,
) {
    BrandCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier
                .padding(12.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    row.customerName ?: "Unknown Customer",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    row.orderId ?: "INV-${row.id}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "${row.daysOverdue} days overdue",
                    style = MaterialTheme.typography.labelSmall,
                    color = when {
                        row.daysOverdue > 60 -> MaterialTheme.colorScheme.error
                        row.daysOverdue > 30 -> MaterialTheme.colorScheme.error.copy(alpha = 0.7f)
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    row.amountDueCents.formatAsMoney(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.error,
                )
                SuggestionChip(
                    onClick = {},
                    label = {
                        Text(
                            BUCKET_LABELS[row.bucket] ?: row.bucket,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    },
                )
            }
        }
    }
}
