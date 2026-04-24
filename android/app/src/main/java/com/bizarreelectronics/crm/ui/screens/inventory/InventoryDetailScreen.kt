package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
// @audit-fixed: Section 33 / D1 — explicit import for the deprecated Double
// shims that now read from the new costPriceCents / retailPriceCents columns.
import com.bizarreelectronics.crm.data.local.db.entities.costPrice
import com.bizarreelectronics.crm.data.local.db.entities.retailPrice
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryGroupPrice
import com.bizarreelectronics.crm.data.remote.dto.StockMovement
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.util.UndoStack
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/** Reversible edits made from the inventory-detail screen. */
sealed class InventoryEdit {
    data class QuantityAdjust(
        val oldQty: Int,
        val newQty: Int,
        val reason: String?,
    ) : InventoryEdit()

    data class FieldEdit(
        val fieldName: String,
        val oldValue: String?,
        val newValue: String?,
    ) : InventoryEdit()
}

data class InventoryDetailUiState(
    val item: InventoryItemEntity? = null,
    val movements: List<StockMovement> = emptyList(),
    val groupPrices: List<InventoryGroupPrice> = emptyList(),
    val movementsOfflineMessage: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    // U2 fix: success counter mirrors InvoiceDetailUiState so the UI can close
    // the adjust-stock dialog strictly after a successful mutation — not mid-click.
    val adjustSuccessCounter: Int = 0,
    /** Non-null while an undo snackbar is pending display. */
    val undoMessage: String? = null,
    /** True when the undo stack has at least one undoable action. */
    val canUndo: Boolean = false,
)

@HiltViewModel
class InventoryDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val inventoryRepository: InventoryRepository,
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val itemId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(InventoryDetailUiState())
    val state = _state.asStateFlow()

    /** Undo/redo history for optimistic writes made on this screen. */
    val undoStack = UndoStack<InventoryEdit>()

    init {
        loadItem()
        observeUndoEvents()
    }

    /** Forward Undone/Redone events to Timber (audit trail). */
    private fun observeUndoEvents() {
        viewModelScope.launch {
            undoStack.events.collect { event ->
                when (event) {
                    is UndoStack.UndoEvent.Undone ->
                        Timber.tag("InventoryUndo").i("Undone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Redone ->
                        Timber.tag("InventoryUndo").i("Redone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Failed ->
                        Timber.tag("InventoryUndo").w("Failed: ${event.reason} — ${event.entry.auditDescription}")
                    else -> Unit
                }
            }
        }
        // Keep canUndo in sync with the stack so the UI can gate the Undo action.
        viewModelScope.launch {
            undoStack.canUndo.collect { can ->
                _state.value = _state.value.copy(canUndo = can)
            }
        }
    }

    fun loadItem() {
        // Collect entity from repository (cached + background refresh)
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            inventoryRepository.getItem(itemId)
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load item",
                    )
                }
                .collectLatest { entity ->
                    _state.value = _state.value.copy(
                        item = entity,
                        isLoading = false,
                    )
                }
        }
        // Fetch movements and group prices from API (online-only)
        loadOnlineDetails()
    }

    private fun loadOnlineDetails() {
        viewModelScope.launch {
            try {
                val response = inventoryApi.getItem(itemId)
                val data = response.data
                _state.value = _state.value.copy(
                    movements = data?.movements ?: data?.item?.stockMovements ?: emptyList(),
                    groupPrices = data?.groupPrices ?: data?.item?.groupPrices ?: emptyList(),
                    movementsOfflineMessage = null,
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    movements = emptyList(),
                    groupPrices = emptyList(),
                    movementsOfflineMessage = "Stock history available when online",
                )
            }
        }
    }

    fun adjustStock(quantity: Int, type: String, reason: String?) {
        // U2 fix: hard guard against re-entry so a double-tap on the Apply
        // button cannot enqueue two POST /inventory/{id}/adjust-stock requests.
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val oldQty = _state.value.item?.inStock ?: 0
                val newQty = oldQty + quantity
                val request = AdjustStockRequest(
                    quantity = quantity,
                    type = type,
                    reason = reason?.takeIf { it.isNotBlank() },
                )
                inventoryRepository.adjustStock(itemId, request)

                val adjustLabel = if (quantity > 0) "+$quantity" else "$quantity"
                val auditDesc = "Adjusted quantity from $oldQty to $newQty (delta $adjustLabel, type=$type)"

                // Push undo entry. The server uses a delta-based endpoint
                // (POST /inventory/{id}/adjust-stock with quantity), so the
                // compensating sync is the negative delta with reason "undo".
                undoStack.push(
                    UndoStack.Entry(
                        payload = InventoryEdit.QuantityAdjust(
                            oldQty = oldQty,
                            newQty = newQty,
                            reason = reason?.takeIf { it.isNotBlank() },
                        ),
                        apply = {
                            // Re-do: optimistically restore newQty in the local entity.
                            val current = _state.value.item ?: return@Entry
                            _state.value = _state.value.copy(
                                item = current.copy(inStock = newQty),
                            )
                        },
                        reverse = {
                            // Undo: optimistically restore oldQty in the local entity.
                            val current = _state.value.item ?: return@Entry
                            _state.value = _state.value.copy(
                                item = current.copy(inStock = oldQty),
                            )
                        },
                        auditDescription = auditDesc,
                        compensatingSync = {
                            try {
                                // Negative delta undoes the original adjust.
                                val undoRequest = AdjustStockRequest(
                                    quantity = -quantity,
                                    type = "correction",
                                    reason = "undo",
                                )
                                inventoryRepository.adjustStock(itemId, undoRequest)
                                true
                            } catch (_: Exception) {
                                false
                            }
                        },
                    ),
                )

                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    undoMessage = "Stock adjusted by $adjustLabel",
                    adjustSuccessCounter = _state.value.adjustSuccessCounter + 1,
                )
                loadOnlineDetails()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to adjust stock: ${e.message}",
                )
            }
        }
    }

    /** Undo the most recent reversible action. */
    fun performUndo() {
        viewModelScope.launch {
            val ok = undoStack.undo()
            if (!ok) {
                _state.value = _state.value.copy(
                    actionMessage = "Nothing to undo",
                )
            }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    fun clearUndoMessage() {
        _state.value = _state.value.copy(undoMessage = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryDetailScreen(
    itemId: Long,
    onBack: () -> Unit,
    onEditItem: ((Long) -> Unit)? = null,
    viewModel: InventoryDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val item = state.item

    // U2 / form state: rememberSaveable so rotation doesn't drop the in-progress
    // dialog state.
    var showAdjustDialog by rememberSaveable { mutableStateOf(false) }
    var adjustQuantity by rememberSaveable { mutableStateOf("") }
    var adjustIsPositive by rememberSaveable { mutableStateOf(true) }
    var adjustType by rememberSaveable { mutableStateOf("adjustment") }
    var adjustReason by rememberSaveable { mutableStateOf("") }
    var showTypeDropdown by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }

    // Clear the undo stack when the screen leaves composition (nav back / replace).
    DisposableEffect(Unit) {
        onDispose { viewModel.undoStack.clear() }
    }

    // U2 fix: close the adjust-stock dialog strictly after a successful mutation.
    LaunchedEffect(state.adjustSuccessCounter) {
        if (state.adjustSuccessCounter > 0) {
            showAdjustDialog = false
            adjustQuantity = ""
            adjustReason = ""
            adjustType = "adjustment"
            adjustIsPositive = true
        }
    }

    val adjustmentTypes = listOf("adjustment", "purchase", "sale", "return", "damage", "correction")
    val adjustmentTypeLabels = mapOf(
        "adjustment" to "Adjustment",
        "purchase" to "Purchase",
        "sale" to "Sale",
        "return" to "Return",
        "damage" to "Damage",
        "correction" to "Correction",
    )

    // Generic error/info snackbar (no Undo action).
    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    // Undo snackbar: shown after a successful adjust-stock with an Undo action.
    LaunchedEffect(state.undoMessage) {
        state.undoMessage?.let { message ->
            viewModel.clearUndoMessage()
            val result = snackbarHostState.showSnackbar(
                message = message,
                actionLabel = "Undo",
                duration = SnackbarDuration.Short,
            )
            if (result == SnackbarResult.ActionPerformed) {
                viewModel.performUndo()
            }
        }
    }

    // Stock adjustment dialog
    if (showAdjustDialog) {
        AlertDialog(
            onDismissRequest = {
                showAdjustDialog = false
                adjustQuantity = ""
                adjustReason = ""
                adjustType = "adjustment"
                adjustIsPositive = true
            },
            title = { Text("Adjust Stock") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // Direction toggle
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        FilterChip(
                            selected = adjustIsPositive,
                            onClick = { adjustIsPositive = true },
                            label = { Text("Add (+)") },
                            leadingIcon = if (adjustIsPositive) {
                                { Icon(Icons.Default.Check, null, modifier = Modifier.size(16.dp)) }
                            } else null,
                            modifier = Modifier.weight(1f),
                        )
                        FilterChip(
                            selected = !adjustIsPositive,
                            onClick = { adjustIsPositive = false },
                            label = { Text("Remove (-)") },
                            leadingIcon = if (!adjustIsPositive) {
                                { Icon(Icons.Default.Check, null, modifier = Modifier.size(16.dp)) }
                            } else null,
                            modifier = Modifier.weight(1f),
                        )
                    }

                    val currentStock = item?.inStock ?: 0
                    val parsedQty = adjustQuantity.toIntOrNull()
                    // U11 fix: surface the exact validation rule. The regex
                    // already blocks negatives / non-digits, but we still have
                    // to reject zero AND reject a Remove that would push stock
                    // below zero.
                    val qtyError: String? = when {
                        adjustQuantity.isBlank() -> null
                        parsedQty == null -> "Enter a whole number"
                        parsedQty <= 0 -> "Quantity must be greater than 0"
                        !adjustIsPositive && parsedQty > currentStock ->
                            "Cannot remove more than current stock ($currentStock)"
                        else -> null
                    }

                    OutlinedTextField(
                        value = adjustQuantity,
                        onValueChange = { value ->
                            // U11 fix: regex already prevents negatives (no minus sign)
                            // and decimals (digits only). We keep it strict.
                            if (value.isEmpty() || value.matches(Regex("^\\d+$"))) {
                                adjustQuantity = value
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Quantity") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                        isError = qtyError != null,
                        supportingText = {
                            if (qtyError != null) {
                                Text(qtyError, color = MaterialTheme.colorScheme.error)
                            }
                        },
                    )

                    // Type dropdown
                    Box {
                        OutlinedTextField(
                            value = adjustmentTypeLabels[adjustType] ?: adjustType,
                            onValueChange = {},
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Type") },
                            readOnly = true,
                            trailingIcon = {
                                IconButton(onClick = { showTypeDropdown = true }) {
                                    Icon(Icons.Default.ArrowDropDown, contentDescription = "Select type")
                                }
                            },
                        )
                        DropdownMenu(
                            expanded = showTypeDropdown,
                            onDismissRequest = { showTypeDropdown = false },
                        ) {
                            adjustmentTypes.forEach { type ->
                                DropdownMenuItem(
                                    text = { Text(adjustmentTypeLabels[type] ?: type) },
                                    onClick = {
                                        adjustType = type
                                        showTypeDropdown = false
                                    },
                                )
                            }
                        }
                    }

                    OutlinedTextField(
                        value = adjustReason,
                        onValueChange = { adjustReason = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Reason (optional)") },
                        singleLine = true,
                    )
                }
            },
            confirmButton = {
                val currentStock = item?.inStock ?: 0
                val parsedQty = adjustQuantity.toIntOrNull()
                val isQtyValid = parsedQty != null &&
                    parsedQty > 0 &&
                    (adjustIsPositive || parsedQty <= currentStock)
                TextButton(
                    onClick = {
                        // U2 fix: do NOT close the dialog here. The
                        // LaunchedEffect keyed on adjustSuccessCounter does
                        // that after the mutation is confirmed.
                        val qty = parsedQty
                        if (isQtyValid && qty != null && !state.isActionInProgress) {
                            val finalQty = if (adjustIsPositive) qty else -qty
                            viewModel.adjustStock(finalQty, adjustType, adjustReason)
                        }
                    },
                    // U2 fix: button is disabled while isActionInProgress.
                    enabled = isQtyValid && !state.isActionInProgress,
                ) {
                    if (state.isActionInProgress) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Applying...")
                    } else {
                        Text("Apply")
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showAdjustDialog = false
                    adjustQuantity = ""
                    adjustReason = ""
                    adjustType = "adjustment"
                    adjustIsPositive = true
                }) {
                    Text("Cancel")
                }
            },
        )
    }

    Scaffold(
        // D5-8: stock-adjust and reorder-point inputs sit near the bottom of
        // the scroll; imePadding keeps them visible when the keyboard opens.
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = item?.name?.ifBlank { "Item #$itemId" } ?: "Item #$itemId",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // U5 fix: wire the edit button to the edit-item navigation.
                    if (onEditItem != null) {
                        IconButton(onClick = { onEditItem(itemId) }) {
                            Icon(Icons.Default.Edit, contentDescription = "Edit")
                        }
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
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load item.",
                        onRetry = { viewModel.loadItem() },
                    )
                }
            }
            item != null -> {
                InventoryDetailContent(
                    item = item,
                    movements = state.movements,
                    groupPrices = state.groupPrices,
                    movementsOfflineMessage = state.movementsOfflineMessage,
                    padding = padding,
                    isActionInProgress = state.isActionInProgress,
                    onAdjustStock = { showAdjustDialog = true },
                )
            }
        }
    }
}

@Composable
private fun InventoryDetailContent(
    item: InventoryItemEntity,
    movements: List<StockMovement>,
    groupPrices: List<InventoryGroupPrice>,
    movementsOfflineMessage: String?,
    padding: PaddingValues,
    isActionInProgress: Boolean,
    onAdjustStock: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Item info card
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("Item details", style = MaterialTheme.typography.titleSmall)

                    if (!item.itemType.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Type:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(item.itemType.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    if (!item.sku.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("SKU:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            // BrandMono for SKU/barcode strings per todo rule
                            Text(item.sku, style = BrandMono)
                        }
                    }
                    if (!item.upcCode.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("UPC:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            // BrandMono for barcode values per todo rule
                            Text(item.upcCode, style = BrandMono)
                        }
                    }
                    if (!item.manufacturerName.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Manufacturer:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(item.manufacturerName, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    if (!item.supplierName.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Supplier:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(item.supplierName, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    if (!item.description.isNullOrBlank()) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(item.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        // Stock card
        item {
            val stockColor = when {
                item.inStock <= 0 -> MaterialTheme.colorScheme.error
                item.inStock <= item.reorderLevel -> WarningAmber
                else -> MaterialTheme.colorScheme.primary
            }

            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .padding(16.dp)
                        .fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        // BrandMono big quantity display per todo rule
                        Text(
                            "${item.inStock}",
                            style = BrandMono.copy(
                                fontSize = MaterialTheme.typography.headlineMedium.fontSize,
                                lineHeight = MaterialTheme.typography.headlineMedium.lineHeight,
                            ),
                            color = stockColor,
                        )
                        Text("In stock", style = MaterialTheme.typography.bodySmall)
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "$${"%.2f".format(item.costPrice)}",
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text("Cost price", style = MaterialTheme.typography.bodySmall)
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "$${"%.2f".format(item.retailPrice)}",
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text("Retail price", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // Reorder level warning — dynamic color avoids WarningBg pastel on OLED
        if (item.reorderLevel > 0 && item.inStock <= item.reorderLevel) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = WarningAmber.copy(alpha = 0.12f),
                    ),
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        // decorative — non-clickable warning row; sibling "Stock is at or below…" Text carries the announcement
                        Icon(Icons.Default.Warning, contentDescription = null, tint = WarningAmber, modifier = Modifier.size(20.dp))
                        Text(
                            "Stock is at or below reorder level (${item.reorderLevel})",
                            style = MaterialTheme.typography.bodySmall,
                            color = WarningAmber,
                        )
                    }
                }
            }
        }

        // Stock adjustment button
        item {
            Button(
                onClick = onAdjustStock,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isActionInProgress,
            ) {
                // decorative — Button's "Adjust Stock" Text supplies the accessible name
                Icon(Icons.Default.SwapVert, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Adjust Stock")
            }
        }

        // Group prices
        if (groupPrices.isNotEmpty()) {
            item {
                Text("Group prices", style = MaterialTheme.typography.titleMedium)
            }
            items(groupPrices, key = { it.id }) { gp ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(gp.groupName ?: "Group ${gp.groupId}", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "$${"%.2f".format(gp.price ?: 0.0)}",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }

        // Stock movements
        item {
            Text("Stock movements", style = MaterialTheme.typography.titleMedium)
        }

        if (movements.isEmpty()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        movementsOfflineMessage ?: "No stock movements recorded",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(movements, key = { it.id }) { movement ->
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .padding(12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                movement.type?.replaceFirstChar { it.uppercase() } ?: "Movement",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            if (!movement.reason.isNullOrBlank()) {
                                Text(
                                    movement.reason,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Text(
                                "${movement.userName ?: ""} ${movement.createdAt?.take(16)?.replace("T", " ") ?: ""}".trim(),
                                // BrandMono for timestamps per todo convention
                                style = BrandMono,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        val qty = movement.quantity ?: 0
                        Text(
                            if (qty > 0) "+$qty" else "$qty",
                            style = MaterialTheme.typography.titleSmall,
                            color = if (qty >= 0) SuccessGreen else MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
        }
    }
}
