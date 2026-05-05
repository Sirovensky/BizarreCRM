package com.bizarreelectronics.crm.ui.screens.purchaseorders

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.SupplierRow
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.viewmodels.purchaseorders.DraftPoItem
import com.bizarreelectronics.crm.viewmodels.purchaseorders.PurchaseOrderCreateViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurchaseOrderCreateScreen(
    onCreated: (Long) -> Unit,
    onBack: () -> Unit,
    viewModel: PurchaseOrderCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // Navigate away once PO is created
    LaunchedEffect(state.createdPoId) {
        val id = state.createdPoId ?: return@LaunchedEffect
        onCreated(id)
    }

    // Supplier picker dialog state
    var showSupplierPicker by remember { mutableStateOf(false) }
    // Add line-item dialog state
    var showAddItem by remember { mutableStateOf(false) }

    if (showSupplierPicker) {
        SupplierPickerDialog(
            suppliers = state.suppliers,
            isLoading = state.suppliersLoading,
            onSelect = { supplier ->
                viewModel.onSupplierSelected(supplier.id, supplier.name)
                showSupplierPicker = false
            },
            onDismiss = { showSupplierPicker = false },
        )
    }

    if (showAddItem) {
        AddLineItemDialog(
            onAdd = { item ->
                viewModel.addLineItem(item)
                showAddItem = false
            },
            onDismiss = { showAddItem = false },
        )
    }

    state.submitError?.let { err ->
        LaunchedEffect(err) {
            // Auto-clear after being shown; UI surfaces via Snackbar below
        }
    }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.submitError) {
        val err = state.submitError ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(err)
        viewModel.clearSubmitError()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "New Purchase Order",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        onClick = { viewModel.submit() },
                        enabled = !state.isSubmitting &&
                            state.selectedSupplierId != null &&
                            state.lineItems.isNotEmpty(),
                    ) {
                        if (state.isSubmitting) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else {
                            Text("Create")
                        }
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Supplier picker ─────────────────────────────────────────────
            item {
                OutlinedCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showSupplierPicker = true },
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
                                "Supplier",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                state.selectedSupplierName ?: "Tap to select supplier…",
                                style = MaterialTheme.typography.bodyMedium,
                                color = if (state.selectedSupplierName != null)
                                    MaterialTheme.colorScheme.onSurface
                                else
                                    MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // ── Notes ───────────────────────────────────────────────────────
            item {
                OutlinedTextField(
                    value = state.notes,
                    onValueChange = { viewModel.onNotesChanged(it) },
                    label = { Text("Notes (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                )
            }

            // ── Expected date ────────────────────────────────────────────────
            item {
                OutlinedTextField(
                    value = state.expectedDate,
                    onValueChange = { viewModel.onExpectedDateChanged(it) },
                    label = { Text("Expected date (YYYY-MM-DD, optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                )
            }

            // ── Line items header ────────────────────────────────────────────
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Line Items (${state.lineItems.size})",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    FilledTonalButton(onClick = { showAddItem = true }) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Add item")
                    }
                }
            }

            // ── Line item rows ───────────────────────────────────────────────
            itemsIndexed(state.lineItems, key = { idx, _ -> idx }) { idx, item ->
                LineItemRow(
                    item = item,
                    onQtyChange = { qty ->
                        viewModel.updateLineItem(idx, item.copy(quantityOrdered = qty))
                    },
                    onCostChange = { cost ->
                        viewModel.updateLineItem(idx, item.copy(costPrice = cost))
                    },
                    onRemove = { viewModel.removeLineItem(idx) },
                )
            }

            // Empty state hint
            if (state.lineItems.isEmpty()) {
                item {
                    Text(
                        "No line items yet. Tap \"Add item\" to add inventory items.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 8.dp),
                    )
                }
            }
        }
    }
}

// ─── Supplier picker dialog ─────────────────────────────────────────────────

@Composable
private fun SupplierPickerDialog(
    suppliers: List<SupplierRow>,
    isLoading: Boolean,
    onSelect: (SupplierRow) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Select Supplier") },
        text = {
            if (isLoading) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (suppliers.isEmpty()) {
                Text("No active suppliers found. Add a supplier in Settings → Suppliers.")
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    suppliers.forEach { supplier ->
                        ListItem(
                            headlineContent = { Text(supplier.name) },
                            supportingContent = supplier.contactName?.let { { Text(it) } },
                            modifier = Modifier.clickable { onSelect(supplier) },
                        )
                        HorizontalDivider()
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Add line item dialog ───────────────────────────────────────────────────

@Composable
private fun AddLineItemDialog(
    onAdd: (DraftPoItem) -> Unit,
    onDismiss: () -> Unit,
) {
    var inventoryItemId by remember { mutableStateOf("") }
    var itemName by remember { mutableStateOf("") }
    var sku by remember { mutableStateOf("") }
    var qty by remember { mutableStateOf("1") }
    var cost by remember { mutableStateOf("0.00") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Line Item") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = inventoryItemId,
                    onValueChange = { inventoryItemId = it },
                    label = { Text("Inventory Item ID") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    value = itemName,
                    onValueChange = { itemName = it },
                    label = { Text("Item Name") },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = sku,
                    onValueChange = { sku = it },
                    label = { Text("SKU (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = qty,
                        onValueChange = { qty = it },
                        label = { Text("Qty") },
                        modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                    OutlinedTextField(
                        value = cost,
                        onValueChange = { cost = it },
                        label = { Text("Cost $") },
                        modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val id = inventoryItemId.toLongOrNull() ?: return@Button
                    val q = qty.toIntOrNull()?.coerceAtLeast(1) ?: 1
                    val c = cost.toDoubleOrNull() ?: 0.0
                    onAdd(
                        DraftPoItem(
                            inventoryItemId = id,
                            itemName = itemName.ifBlank { "Item $id" },
                            sku = sku.takeIf { it.isNotBlank() },
                            quantityOrdered = q,
                            costPrice = c,
                        ),
                    )
                },
                enabled = inventoryItemId.toLongOrNull() != null,
            ) {
                Text("Add")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Line item row ──────────────────────────────────────────────────────────

@Composable
private fun LineItemRow(
    item: DraftPoItem,
    onQtyChange: (Int) -> Unit,
    onCostChange: (Double) -> Unit,
    onRemove: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(item.itemName, style = MaterialTheme.typography.titleSmall)
                if (!item.sku.isNullOrBlank()) {
                    Text(
                        "SKU: ${item.sku}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(
                        "Qty: ${item.quantityOrdered}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Text(
                        "Cost: $${String.format(java.util.Locale.US, "%.2f", item.costPrice)}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            IconButton(onClick = onRemove) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Remove ${item.itemName}",
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}
