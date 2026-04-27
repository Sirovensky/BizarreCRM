package com.bizarreelectronics.crm.ui.screens.inventory

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderDetail
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderItem
import com.bizarreelectronics.crm.data.remote.dto.ReceivePoItem
import com.bizarreelectronics.crm.data.remote.dto.ReceivePurchaseOrderRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdatePurchaseOrderRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import javax.inject.Inject

data class PoDetailUiState(
    val po: PurchaseOrderDetail? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    val showCancelDialog: Boolean = false,
    /** Tracks entered receive quantities per PO item id. */
    val receiveQtys: Map<Long, String> = emptyMap(),
    val showReceiveSheet: Boolean = false,
)

@HiltViewModel
class PurchaseOrderDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val poId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(PoDetailUiState())
    val state = _state.asStateFlow()

    private val currency = NumberFormat.getCurrencyInstance(Locale.US)

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val resp = inventoryApi.getPurchaseOrder(poId)
                val po = resp.data?.po
                _state.value = _state.value.copy(
                    po = po,
                    isLoading = false,
                    receiveQtys = po?.items?.associate { it.id to "" } ?: emptyMap(),
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load purchase order",
                )
            }
        }
    }

    fun formatAmount(value: Double?): String =
        if (value == null) "—" else currency.format(value)

    fun clearActionMessage() { _state.value = _state.value.copy(actionMessage = null) }

    // ── Cancel ────────────────────────────────────────────────────────────────

    fun setShowCancelDialog(show: Boolean) {
        _state.value = _state.value.copy(showCancelDialog = show)
    }

    fun confirmCancel() {
        viewModelScope.launch {
            _state.value = _state.value.copy(showCancelDialog = false, isActionInProgress = true)
            try {
                inventoryApi.updatePurchaseOrder(poId, UpdatePurchaseOrderRequest(status = "cancelled"))
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Purchase order cancelled",
                )
                load()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Cancel failed",
                )
            }
        }
    }

    // ── Receive items ─────────────────────────────────────────────────────────

    fun setShowReceiveSheet(show: Boolean) {
        _state.value = _state.value.copy(showReceiveSheet = show)
    }

    fun updateReceiveQty(itemId: Long, qty: String) {
        _state.value = _state.value.copy(
            receiveQtys = _state.value.receiveQtys + (itemId to qty),
        )
    }

    fun submitReceive() {
        val qtys = _state.value.receiveQtys
        val items = qtys.mapNotNull { (id, qtyStr) ->
            val qty = qtyStr.toIntOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
            ReceivePoItem(purchaseOrderItemId = id, quantityReceived = qty)
        }
        if (items.isEmpty()) {
            _state.value = _state.value.copy(actionMessage = "Enter at least one received quantity")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                inventoryApi.receivePurchaseOrder(poId, ReceivePurchaseOrderRequest(items))
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    showReceiveSheet = false,
                    actionMessage = "Items received — stock updated",
                )
                load()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Receive failed",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurchaseOrderDetailScreen(
    onBack: () -> Unit,
    viewModel: PurchaseOrderDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var showOverflow by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(state.actionMessage) {
        val msg = state.actionMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearActionMessage()
    }

    // Cancel confirm dialog
    if (state.showCancelDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.setShowCancelDialog(false) },
            title = { Text(stringResource(R.string.po_cancel_title)) },
            text = { Text(stringResource(R.string.po_cancel_message)) },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.confirmCancel() },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) { Text(stringResource(R.string.po_cancel_confirm)) }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.setShowCancelDialog(false) }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }

    // Receive items bottom sheet
    if (state.showReceiveSheet) {
        ReceiveItemsSheet(
            po = state.po,
            receiveQtys = state.receiveQtys,
            isInProgress = state.isActionInProgress,
            onQtyChange = viewModel::updateReceiveQty,
            onSubmit = viewModel::submitReceive,
            onDismiss = { viewModel.setShowReceiveSheet(false) },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = state.po?.orderId ?: "Purchase Order",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.cd_back))
                    }
                },
                actions = {
                    // §6.7: Send (share PO as text via ACTION_SEND).
                    IconButton(
                        onClick = {
                            val po = state.po ?: return@IconButton
                            val body = buildPoShareText(po)
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_SUBJECT, "Purchase Order ${po.orderId}")
                                putExtra(Intent.EXTRA_TEXT, body)
                            }
                            context.startActivity(Intent.createChooser(intent, "Send PO to supplier"))
                        },
                    ) {
                        Icon(Icons.Default.Share, contentDescription = stringResource(R.string.po_send_cd))
                    }
                    // Overflow: Receive items / Cancel
                    Box {
                        IconButton(onClick = { showOverflow = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More actions")
                        }
                        DropdownMenu(
                            expanded = showOverflow,
                            onDismissRequest = { showOverflow = false },
                        ) {
                            val status = state.po?.status
                            if (status in listOf("ordered", "partial")) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.po_receive_items)) },
                                    onClick = {
                                        showOverflow = false
                                        viewModel.setShowReceiveSheet(true)
                                    },
                                )
                            }
                            if (status != "received" && status != "cancelled") {
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            stringResource(R.string.po_cancel_action),
                                            color = MaterialTheme.colorScheme.error,
                                        )
                                    },
                                    onClick = {
                                        showOverflow = false
                                        viewModel.setShowCancelDialog(true)
                                    },
                                )
                            }
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(Modifier.fillMaxSize().padding(padding), Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(Modifier.fillMaxSize().padding(padding), Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.height(8.dp))
                        FilledTonalButton(onClick = viewModel::load) { Text("Retry") }
                    }
                }
            }
            else -> {
                val po = state.po
                if (po == null) {
                    Box(Modifier.fillMaxSize().padding(padding), Alignment.Center) {
                        Text("Purchase order not found")
                    }
                } else {
                    PoDetailContent(
                        po = po,
                        formatAmount = viewModel::formatAmount,
                        padding = padding,
                    )
                }
            }
        }
    }
}

@Composable
private fun PoDetailContent(
    po: PurchaseOrderDetail,
    formatAmount: (Double?) -> String,
    padding: PaddingValues,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Header card
        item {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(po.orderId ?: "PO #${po.id}", style = MaterialTheme.typography.titleMedium)
                        PoStatusChip(status = po.status ?: "draft")
                    }
                    if (po.supplierName != null) {
                        Text("Supplier: ${po.supplierName}", style = MaterialTheme.typography.bodyMedium)
                    }
                    if (po.expectedDate != null) {
                        Text("Expected: ${po.expectedDate}", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(
                        "Total: ${formatAmount(po.total)}",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    if (!po.notes.isNullOrBlank()) {
                        Text("Notes: ${po.notes}", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        // Line items
        if (!po.items.isNullOrEmpty()) {
            item {
                Text("Line Items", style = MaterialTheme.typography.titleSmall)
            }
            items(po.items) { line ->
                PoLineItemCard(line = line, formatAmount = formatAmount)
            }
        }
    }
}

@Composable
private fun PoLineItemCard(
    line: PurchaseOrderItem,
    formatAmount: (Double?) -> String,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        ListItem(
            headlineContent = {
                Text(line.itemName ?: "Item #${line.inventoryItemId}")
            },
            supportingContent = {
                val received = line.quantityReceived
                val ordered = line.quantityOrdered
                Text("$received / $ordered received")
            },
            trailingContent = {
                Text(formatAmount(line.costPrice))
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceiveItemsSheet(
    po: PurchaseOrderDetail?,
    receiveQtys: Map<Long, String>,
    isInProgress: Boolean,
    onQtyChange: (Long, String) -> Unit,
    onSubmit: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Receive items", style = MaterialTheme.typography.titleMedium)
            po?.items?.forEach { item ->
                val remaining = item.quantityOrdered - item.quantityReceived
                if (remaining <= 0) return@forEach
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(item.itemName ?: "Item ${item.id}", style = MaterialTheme.typography.bodyMedium)
                        Text("Remaining: $remaining", style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    OutlinedTextField(
                        value = receiveQtys[item.id] ?: "",
                        onValueChange = { v ->
                            if (v.isEmpty() || v.matches(Regex("^\\d+$")))
                                onQtyChange(item.id, v)
                        },
                        label = { Text("Qty") },
                        singleLine = true,
                        modifier = Modifier.width(80.dp),
                    )
                }
            }
            FilledTonalButton(
                onClick = onSubmit,
                enabled = !isInProgress,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isInProgress) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text("Confirm receipt")
            }
        }
    }
}

private fun buildPoShareText(po: PurchaseOrderDetail): String = buildString {
    appendLine("Purchase Order: ${po.orderId ?: "PO #${po.id}"}")
    appendLine("Supplier: ${po.supplierName ?: "—"}")
    po.expectedDate?.let { appendLine("Expected: $it") }
    appendLine()
    po.items?.forEach { item ->
        appendLine("  • ${item.itemName ?: "Item ${item.inventoryItemId}"}: ${item.quantityOrdered} @ ${item.costPrice ?: "—"}")
    }
    appendLine()
    appendLine("Total: ${po.total ?: "—"}")
    po.notes?.let { appendLine("Notes: $it") }
}
