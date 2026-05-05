package com.bizarreelectronics.crm.ui.screens.purchaseorders

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.viewmodels.purchaseorders.PurchaseOrderDetailViewModel
import com.bizarreelectronics.crm.viewmodels.purchaseorders.ReceiveEntry
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurchaseOrderDetailScreen(
    onBack: () -> Unit,
    viewModel: PurchaseOrderDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Receive success toast
    LaunchedEffect(state.receiveSuccess) {
        if (state.receiveSuccess) {
            snackbarHostState.showSnackbar("Items received — inventory updated.")
            viewModel.clearReceiveSuccess()
        }
    }

    // Receive error toast
    LaunchedEffect(state.receiveError) {
        val err = state.receiveError ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(err)
        viewModel.clearReceiveSuccess()
    }

    // Cancel confirm dialog
    if (state.showCancelConfirm) {
        CancelPoConfirmDialog(
            cancelReason = state.cancelReason,
            isCancelling = state.isCancelling,
            cancelError = state.cancelError,
            onReasonChange = { viewModel.onCancelReasonChanged(it) },
            onConfirm = { viewModel.confirmCancel() },
            onDismiss = { viewModel.dismissCancelConfirm() },
        )
    }

    val order = state.order
    val isCancellable = order != null &&
        order.status !in listOf("received", "cancelled")

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = order?.orderId ?: "Purchase Order",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // Send / Print actions — only shown once the PO is loaded
                    if (order != null) {
                        PurchaseOrderSendActions(
                            order  = order,
                            items  = state.items,
                            snackbarHost = snackbarHostState,
                        )
                    }
                    IconButton(onClick = { viewModel.load() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                BrandSkeleton(rows = 8, modifier = Modifier.padding(padding).padding(top = 8.dp))
            }
            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(message = state.error ?: "Error", onRetry = { viewModel.load() })
                }
            }
            order != null -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // ── Header card ───────────────────────────────────────
                    item {
                        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Column {
                                        Text("PO #${order.orderId}", style = MaterialTheme.typography.titleMedium)
                                        if (!order.supplierName.isNullOrBlank()) {
                                            Text(
                                                order.supplierName,
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                    Column(horizontalAlignment = Alignment.End) {
                                        PoStatusBadge(status = order.status)
                                        Text(
                                            "$${String.format(Locale.US, "%.2f", order.total)}",
                                            style = MaterialTheme.typography.titleSmall,
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                    }
                                }
                                if (!order.notes.isNullOrBlank()) {
                                    Text(
                                        order.notes,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                order.expectedDate?.let {
                                    Text("Expected: $it", style = MaterialTheme.typography.bodySmall)
                                }
                                order.cancelledReason?.let {
                                    Text(
                                        "Cancelled: $it",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                }
                            }
                        }
                    }

                    // ── Line items ────────────────────────────────────────
                    item {
                        Text("Line Items", style = MaterialTheme.typography.titleSmall)
                    }

                    items(state.items, key = { it.id }) { poItem ->
                        PoLineItemRow(poItem = poItem)
                    }

                    // ── Receive section (only for receivable statuses) ──
                    val isReceivable = order.status in listOf("ordered", "partial", "backordered")
                    if (isReceivable && state.receiveEntries.isNotEmpty()) {
                        item {
                            Spacer(Modifier.height(4.dp))
                            Text("Receive Items", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Enter quantities received. Server will update inventory counts.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        items(state.receiveEntries, key = { it.poItem.id }) { entry ->
                            ReceiveItemRow(
                                entry = entry,
                                onQtyChange = { qty -> viewModel.updateReceiveQty(entry.poItem.id, qty) },
                            )
                        }

                        item {
                            Button(
                                onClick = { viewModel.submitReceive() },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = !state.isReceiving,
                            ) {
                                if (state.isReceiving) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        strokeWidth = 2.dp,
                                        color = MaterialTheme.colorScheme.onPrimary,
                                    )
                                    Spacer(Modifier.width(8.dp))
                                }
                                Text("Submit Receipt")
                            }
                        }
                    }

                    // ── Cancel action ─────────────────────────────────────
                    if (isCancellable) {
                        item {
                            Spacer(Modifier.height(4.dp))
                            OutlinedButton(
                                onClick = { viewModel.requestCancel() },
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error,
                                ),
                            ) {
                                Text("Cancel PO")
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Line item row (read-only) ──────────────────────────────────────────────

@Composable
private fun PoLineItemRow(poItem: PurchaseOrderItem) {
    val remaining = poItem.quantityOrdered - poItem.quantityReceived
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    poItem.itemName ?: "Item #${poItem.inventoryItemId}",
                    style = MaterialTheme.typography.titleSmall,
                )
                if (!poItem.sku.isNullOrBlank()) {
                    Text(
                        "SKU: ${poItem.sku}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "${poItem.quantityReceived}/${poItem.quantityOrdered} received",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    "$${String.format(Locale.US, "%.2f", poItem.costPrice)} ea",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (remaining > 0) {
                    Text(
                        "$remaining remaining",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
        }
    }
}

// ─── Receive qty entry row ──────────────────────────────────────────────────

@Composable
private fun ReceiveItemRow(
    entry: ReceiveEntry,
    onQtyChange: (Int) -> Unit,
) {
    val maxReceivable = entry.poItem.quantityOrdered - entry.poItem.quantityReceived
    var text by remember(entry.poItem.id) { mutableStateOf(entry.qtyToReceive.toString()) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                entry.poItem.itemName ?: "Item #${entry.poItem.inventoryItemId}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                "Max: $maxReceivable",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        OutlinedTextField(
            value = text,
            onValueChange = { v ->
                text = v
                val parsed = v.toIntOrNull()?.coerceIn(0, maxReceivable) ?: 0
                onQtyChange(parsed)
            },
            label = { Text("Qty") },
            modifier = Modifier.width(90.dp),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
        )
    }
}

// ─── Cancel PO confirm dialog ───────────────────────────────────────────────

@Composable
private fun CancelPoConfirmDialog(
    cancelReason: String,
    isCancelling: Boolean,
    cancelError: String?,
    onReasonChange: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = { if (!isCancelling) onDismiss() },
        title = { Text("Cancel Purchase Order?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("This will permanently cancel the PO. Received quantities are not reversed.")
                OutlinedTextField(
                    value = cancelReason,
                    onValueChange = onReasonChange,
                    label = { Text("Reason (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isCancelling,
                )
                if (!cancelError.isNullOrBlank()) {
                    Text(
                        cancelError,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                enabled = !isCancelling,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                if (isCancelling) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onError,
                    )
                } else {
                    Text("Cancel PO")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isCancelling) {
                Text("Keep PO")
            }
        },
    )
}
