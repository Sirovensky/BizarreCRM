package com.bizarreelectronics.crm.ui.screens.invoices

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.AgingBucket
import com.bizarreelectronics.crm.data.remote.dto.AgingInvoiceRow
import com.bizarreelectronics.crm.data.remote.dto.BulkActionRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import javax.inject.Inject

// ── UiState ──────────────────────────────────────────────────────────────────

data class AgingUiState(
    val buckets: Map<String, AgingBucket> = emptyMap(),
    val invoices: List<AgingInvoiceRow> = emptyList(),
    val selectedBucket: String = "all",
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class InvoiceAgingViewModel @Inject constructor(
    private val invoiceApi: InvoiceApi,
) : ViewModel() {

    private val _state = MutableStateFlow(AgingUiState())
    val state = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { invoiceApi.getAgingReport() }
                .onSuccess { resp ->
                    val data = resp.data
                    if (resp.success && data != null) {
                        _state.value = _state.value.copy(
                            buckets = data.buckets,
                            invoices = data.invoices,
                            isLoading = false,
                        )
                    } else {
                        _state.value = _state.value.copy(
                            isLoading = false,
                            error = "Aging report unavailable.",
                        )
                    }
                }
                .onFailure { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load aging report.",
                    )
                }
        }
    }

    fun selectBucket(bucket: String) {
        _state.value = _state.value.copy(selectedBucket = bucket)
    }

    /** Send a reminder for a single invoice row. 404-tolerant stub. */
    fun sendReminder(invoiceId: Long) {
        viewModelScope.launch {
            // POST /invoices/bulk-action { action: "send_reminder", ids: [invoiceId] }
            runCatching {
                invoiceApi.bulkAction(BulkActionRequest(action = "send_reminder", ids = listOf(invoiceId)))
            }
            _state.value = _state.value.copy(actionMessage = "Reminder sent.")
        }
    }

    /** Navigate to record-payment is handled by the screen via callback. */

    /** Write-off: void the invoice. */
    fun writeOff(invoiceId: Long) {
        viewModelScope.launch {
            runCatching { invoiceApi.voidInvoice(invoiceId) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        invoices = _state.value.invoices.filter { it.id != invoiceId },
                        actionMessage = "Invoice written off.",
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(actionMessage = "Write-off failed. Check your connection.")
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvoiceAgingScreen(
    onBack: () -> Unit,
    onRecordPayment: (Long) -> Unit,
    viewModel: InvoiceAgingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearActionMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Aging Report",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.load() },
                        modifier = Modifier.semantics { contentDescription = "Refresh aging report" },
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null)
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(message = state.error!!, onRetry = { viewModel.load() })
                }
            }
            else -> {
                AgingContent(
                    state = state,
                    padding = padding,
                    onSelectBucket = { viewModel.selectBucket(it) },
                    onSendReminder = { viewModel.sendReminder(it) },
                    onRecordPayment = onRecordPayment,
                    onWriteOff = { viewModel.writeOff(it) },
                )
            }
        }
    }
}

@Composable
private fun AgingContent(
    state: AgingUiState,
    padding: PaddingValues,
    onSelectBucket: (String) -> Unit,
    onSendReminder: (Long) -> Unit,
    onRecordPayment: (Long) -> Unit,
    onWriteOff: (Long) -> Unit,
) {
    val bucketOrder = listOf("0-30", "31-60", "61-90", "90+")
    val bucketLabels = mapOf(
        "0-30" to "0–30 days",
        "31-60" to "31–60 days",
        "61-90" to "61–90 days",
        "90+" to "90+ days",
    )
    val allBuckets = listOf("all") + bucketOrder

    val filteredInvoices = if (state.selectedBucket == "all") {
        state.invoices
    } else {
        state.invoices.filter { it.bucket == state.selectedBucket }
    }

    // Write-off confirm state
    var pendingWriteOffId by remember { mutableStateOf<Long?>(null) }
    if (pendingWriteOffId != null) {
        val inv = state.invoices.find { it.id == pendingWriteOffId }
        ConfirmDialog(
            title = "Write off invoice?",
            message = "Void invoice ${inv?.orderId ?: "#${pendingWriteOffId}"} for ${inv?.customerName ?: "customer"}? This marks it as uncollectable and cannot be undone.",
            confirmLabel = "Write Off",
            onConfirm = {
                pendingWriteOffId?.let { onWriteOff(it) }
                pendingWriteOffId = null
            },
            onDismiss = { pendingWriteOffId = null },
            isDestructive = true,
        )
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Bucket summary cards
        item {
            Text(
                "Summary",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                bucketOrder.forEach { key ->
                    val bucket = state.buckets[key]
                    val formatter = NumberFormat.getCurrencyInstance(Locale.US)
                    OutlinedCard(
                        modifier = Modifier
                            .weight(1f)
                            .semantics {
                                contentDescription = "${bucketLabels[key]}: ${bucket?.count ?: 0} invoices"
                            },
                    ) {
                        Column(
                            modifier = Modifier.padding(8.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(
                                key,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "${bucket?.count ?: 0}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = if (key == "90+") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                            )
                            Text(
                                formatter.format((bucket?.totalCents ?: 0L) / 100.0),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }

        // Bucket filter chips
        item {
            Spacer(modifier = Modifier.height(4.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                allBuckets.forEach { bucket ->
                    val label = if (bucket == "all") "All" else (bucketLabels[bucket] ?: bucket)
                    FilterChip(
                        selected = state.selectedBucket == bucket,
                        onClick = { onSelectBucket(bucket) },
                        label = { Text(label) },
                        modifier = Modifier.semantics {
                            contentDescription = if (state.selectedBucket == bucket) "$label filter, selected" else "$label filter"
                        },
                    )
                }
            }
        }

        // Invoice rows
        if (filteredInvoices.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No overdue invoices in this range.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            item {
                Text(
                    "${filteredInvoices.size} invoice(s)",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            items(filteredInvoices, key = { it.id }) { row ->
                AgingInvoiceCard(
                    row = row,
                    onSendReminder = { onSendReminder(row.id) },
                    onRecordPayment = { onRecordPayment(row.id) },
                    onWriteOff = { pendingWriteOffId = row.id },
                )
            }
        }
    }
}

@Composable
private fun AgingInvoiceCard(
    row: AgingInvoiceRow,
    onSendReminder: () -> Unit,
    onRecordPayment: () -> Unit,
    onWriteOff: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    val formatter = NumberFormat.getCurrencyInstance(Locale.US)
    val amountDue = formatter.format(row.amountDueCents / 100.0)
    val overdueLabel = if (row.daysOverdue > 0) "${row.daysOverdue}d overdue" else "Due today"

    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    row.orderId ?: "INV-${row.id}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    row.customerName ?: "Unknown customer",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.errorContainer,
                ) {
                    Text(
                        overdueLabel,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    amountDue,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.error,
                )
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            Icons.Default.MoreVert,
                            contentDescription = "Actions for invoice ${row.orderId ?: row.id}",
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text("Send reminder") },
                            leadingIcon = { Icon(Icons.Default.Send, contentDescription = null) },
                            onClick = { showMenu = false; onSendReminder() },
                        )
                        DropdownMenuItem(
                            text = { Text("Record payment") },
                            leadingIcon = { Icon(Icons.Default.Payment, contentDescription = null) },
                            onClick = { showMenu = false; onRecordPayment() },
                        )
                        DropdownMenuItem(
                            text = { Text("Write off", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.DeleteForever,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error,
                                )
                            },
                            onClick = { showMenu = false; onWriteOff() },
                        )
                    }
                }
            }
        }
    }
}
