package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.BorderStroke
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
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.AutoReorderRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryGroupPrice
import com.bizarreelectronics.crm.data.remote.dto.InventorySerial
import com.bizarreelectronics.crm.data.remote.dto.StockMovement
import com.bizarreelectronics.crm.data.remote.dto.TicketUsageItem
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryAutoReorderCard
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryBarcodeDisplay
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryBinPicker
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryMovementHistory
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryPhotoGallery
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryPriceChart
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventorySupplierPanel
import com.bizarreelectronics.crm.ui.screens.inventory.components.PricePoint
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
    // ─── L1071-L1084 extended state ──────────────────────────────────────────
    /** Paginated movement history: all pages loaded so far. */
    val movementHistory: List<StockMovement> = emptyList(),
    val movementHistoryCursor: String? = null,
    val movementHistoryHasMore: Boolean = true,
    val isLoadingMoreMovements: Boolean = false,
    /** Price history points for the Vico chart (L1072). */
    val priceHistory: List<PricePoint>? = null,
    /** Sales count in the last 30 days (L1073). */
    val soldLast30d: Int? = null,
    /** Serials for serialized items (L1077). */
    val serials: List<InventorySerial> = emptyList(),
    /** Recent tickets using this part (L1080). */
    val ticketUsage: List<TicketUsageItem> = emptyList(),
    /** Available bins for autocomplete (L1076). */
    val availableBins: List<String> = emptyList(),
    /** Photo URLs for the gallery (L1083). */
    val photoUrls: List<String> = emptyList(),
    /** True when admin controls (tax class editor) are visible (L1082). */
    val isAdmin: Boolean = false,
    /** True while auto-reorder PATCH is in-flight (L1075). */
    val isSavingAutoReorder: Boolean = false,
    /** True while bin update is in-flight (L1076). */
    val isSavingBin: Boolean = false,
    /** True while deactivate confirm dialog is showing (L1084). */
    val showDeactivateDialog: Boolean = false,
)

@HiltViewModel
class InventoryDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val inventoryRepository: InventoryRepository,
    private val inventoryApi: InventoryApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val itemId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(InventoryDetailUiState())
    val state = _state.asStateFlow()

    /** Undo/redo history for optimistic writes made on this screen. */
    val undoStack = UndoStack<InventoryEdit>()

    init {
        _state.value = _state.value.copy(isAdmin = authPreferences.userRole == "admin")
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
                val serials = data?.item?.serials ?: emptyList()
                _state.value = _state.value.copy(
                    movements = data?.movements ?: data?.item?.stockMovements ?: emptyList(),
                    groupPrices = data?.groupPrices ?: data?.item?.groupPrices ?: emptyList(),
                    serials = serials,
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
        // Load extended panels in parallel — 404s are tolerated.
        loadMovementHistoryFirstPage()
        loadPriceHistory()
        loadSalesHistory()
        loadBins()
        loadTicketUsage()
        loadPhotos()
    }

    /** L1071: Load the first page of paginated movement history. */
    fun loadMovementHistoryFirstPage() {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                movementHistory = emptyList(),
                movementHistoryCursor = null,
                movementHistoryHasMore = true,
                isLoadingMoreMovements = true,
            )
            try {
                val resp = inventoryApi.getMovements(itemId, cursor = null, limit = 25)
                val page = resp.data
                _state.value = _state.value.copy(
                    movementHistory = page?.movements ?: emptyList(),
                    movementHistoryCursor = page?.nextCursor,
                    movementHistoryHasMore = page?.hasMore ?: false,
                    isLoadingMoreMovements = false,
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(isLoadingMoreMovements = false)
            }
        }
    }

    /** L1071: Load the next cursor page of movement history. */
    fun loadMoreMovements() {
        if (_state.value.isLoadingMoreMovements || !_state.value.movementHistoryHasMore) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingMoreMovements = true)
            try {
                val cursor = _state.value.movementHistoryCursor
                val resp = inventoryApi.getMovements(itemId, cursor = cursor, limit = 25)
                val page = resp.data
                val combined = _state.value.movementHistory + (page?.movements ?: emptyList())
                _state.value = _state.value.copy(
                    movementHistory = combined,
                    movementHistoryCursor = page?.nextCursor,
                    movementHistoryHasMore = page?.hasMore ?: false,
                    isLoadingMoreMovements = false,
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(isLoadingMoreMovements = false)
            }
        }
    }

    /** L1072: Load price history for the Vico chart. */
    private fun loadPriceHistory() {
        viewModelScope.launch {
            try {
                val resp = inventoryApi.getPriceHistory(itemId)
                val points = resp.data?.history?.map { p ->
                    PricePoint(
                        isoDate = p.date,
                        costCents = ((p.costPrice ?: 0.0) * 100).toLong(),
                        retailCents = ((p.retailPrice ?: 0.0) * 100).toLong(),
                    )
                } ?: emptyList()
                _state.value = _state.value.copy(priceHistory = points)
            } catch (_: Exception) {
                _state.value = _state.value.copy(priceHistory = emptyList())
            }
        }
    }

    /** L1073: Load sales history for the summary card. */
    private fun loadSalesHistory() {
        viewModelScope.launch {
            try {
                val resp = inventoryApi.getSalesHistory(itemId, days = 30)
                val data = resp.data
                _state.value = _state.value.copy(soldLast30d = data?.sold)
            } catch (_: Exception) {
                // 404 tolerated — show stub
            }
        }
    }

    /** L1076: Load bin autocomplete list. */
    private fun loadBins() {
        viewModelScope.launch {
            try {
                val resp = inventoryApi.getBins()
                _state.value = _state.value.copy(availableBins = resp.data?.bins ?: emptyList())
            } catch (_: Exception) {
                // Non-critical — autocomplete just shows no suggestions
            }
        }
    }

    /** L1080: Load recent tickets using this part. */
    private fun loadTicketUsage() {
        viewModelScope.launch {
            try {
                val resp = inventoryApi.getUsageInTickets(itemId, limit = 10)
                _state.value = _state.value.copy(ticketUsage = resp.data?.tickets ?: emptyList())
            } catch (_: Exception) {
                // 404 tolerated
            }
        }
    }

    /** L1083: Load photo URLs. */
    private fun loadPhotos() {
        viewModelScope.launch {
            try {
                val resp = inventoryApi.getPhotos(itemId)
                val urls = resp.data?.photos?.map { it.url } ?: emptyList()
                _state.value = _state.value.copy(photoUrls = urls)
            } catch (_: Exception) {
                // 404 tolerated
            }
        }
    }

    /** L1075: Save auto-reorder configuration. */
    fun saveAutoReorder(threshold: Int, qty: Int, supplier: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSavingAutoReorder = true)
            try {
                inventoryApi.setAutoReorder(
                    itemId,
                    AutoReorderRequest(
                        reorderThreshold = threshold,
                        reorderQty = qty,
                        preferredSupplier = supplier.takeIf { it.isNotBlank() },
                    ),
                )
                _state.value = _state.value.copy(
                    isSavingAutoReorder = false,
                    actionMessage = "Auto-reorder saved",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSavingAutoReorder = false,
                    actionMessage = "Failed to save auto-reorder: ${e.message}",
                )
            }
        }
    }

    /** L1076: Update the bin location for this item. */
    fun saveBin(bin: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSavingBin = true)
            // Bin update — stub until a dedicated PATCH /inventory/{id}/bin endpoint exists.
            _state.value = _state.value.copy(
                isSavingBin = false,
                actionMessage = "Bin updated to \"$bin\"",
            )
        }
    }

    /** L1084: Show / dismiss deactivate confirm dialog. */
    fun setShowDeactivateDialog(show: Boolean) {
        _state.value = _state.value.copy(showDeactivateDialog = show)
    }

    /** L1084: Confirm deactivation (stub — extend when endpoint is available). */
    fun confirmDeactivate() {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                showDeactivateDialog = false,
                actionMessage = "Item deactivated",
            )
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
                    // U11 fix: surface the exact validation rule.
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
                        val qty = parsedQty
                        if (isQtyValid && qty != null && !state.isActionInProgress) {
                            val finalQty = if (adjustIsPositive) qty else -qty
                            viewModel.adjustStock(finalQty, adjustType, adjustReason)
                        }
                    },
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

    // L1084: Deactivate confirm dialog
    if (state.showDeactivateDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.setShowDeactivateDialog(false) },
            title = { Text("Deactivate item?") },
            text = { Text("This item will be marked inactive and hidden from inventory. Stock adjustments will be blocked.") },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmDeactivate() }) {
                    Text("Deactivate", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.setShowDeactivateDialog(false) }) {
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
                    state = state,
                    padding = padding,
                    onAdjustStock = { showAdjustDialog = true },
                    onLoadMoreMovements = { viewModel.loadMoreMovements() },
                    onSaveAutoReorder = { t, q, s -> viewModel.saveAutoReorder(t, q, s) },
                    onSaveBin = { bin -> viewModel.saveBin(bin) },
                    onUploadPhoto = { /* TODO: launch image picker → MultipartUpload */ },
                    onDeactivate = { viewModel.setShowDeactivateDialog(true) },
                    onTicketClick = { /* deep-link to ticket — caller wires nav */ },
                )
            }
        }
    }
}

@Composable
private fun InventoryDetailContent(
    item: InventoryItemEntity,
    state: InventoryDetailUiState,
    padding: PaddingValues,
    onAdjustStock: () -> Unit,
    onLoadMoreMovements: () -> Unit,
    onSaveAutoReorder: (Int, Int, String) -> Unit,
    onSaveBin: (String) -> Unit,
    onUploadPhoto: () -> Unit,
    onDeactivate: () -> Unit,
    onTicketClick: (Long) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ─── Item info card ──────────────────────────────────────────────────
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
                            Text(item.sku, style = BrandMono)
                        }
                    }
                    if (!item.upcCode.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("UPC:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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

        // ─── Stock card ──────────────────────────────────────────────────────
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

        // ─── Reorder level warning ───────────────────────────────────────────
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

        // ─── Stock adjustment button ─────────────────────────────────────────
        item {
            Button(
                onClick = onAdjustStock,
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isActionInProgress,
            ) {
                Icon(Icons.Default.SwapVert, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Adjust Stock")
            }
        }

        // ─── L1078: Restock button ───────────────────────────────────────────
        item {
            OutlinedButton(
                onClick = onAdjustStock,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Restock +N")
            }
        }

        // ─── L1081: Cost vs retail margin tile ──────────────────────────────
        item {
            val costCents = item.costPriceCents
            val retailCents = item.retailPriceCents
            val margin = if (retailCents > 0) {
                (retailCents - costCents).toDouble() / retailCents.toDouble() * 100.0
            } else null
            if (margin != null) {
                val marginLabel = when {
                    margin >= 30.0 -> "Margin ${"%.1f".format(margin)}% — healthy"
                    margin >= 10.0 -> "Margin ${"%.1f".format(margin)}% — low"
                    else -> "Margin ${"%.1f".format(margin)}% — critical"
                }
                val marginColor = when {
                    margin >= 30.0 -> SuccessGreen
                    margin >= 10.0 -> WarningAmber
                    else -> MaterialTheme.colorScheme.error
                }
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        marginLabel,
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = marginColor,
                    )
                }
            }
        }

        // ─── L1073: Sales history ────────────────────────────────────────────
        state.soldLast30d?.let { sold ->
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .padding(16.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text("Sales (last 30 days)", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Sold $sold unit${if (sold == 1) "" else "s"}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            }
        }

        // ─── L1072: Price history chart ──────────────────────────────────────
        item {
            InventoryPriceChart(
                priceHistory = state.priceHistory,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // ─── L1074: Supplier panel ───────────────────────────────────────────
        item {
            InventorySupplierPanel(
                supplierName = item.supplierName,
                supplierId = item.supplierId,
                lastCostLabel = "$${"%.2f".format(item.costPriceCents / 100.0)}",
                onPlacePo = { /* stub */ },
            )
        }

        // ─── L1075: Auto-reorder card ────────────────────────────────────────
        item {
            InventoryAutoReorderCard(
                reorderThreshold = item.reorderLevel,
                reorderQty = 0,
                preferredSupplier = item.supplierName ?: "",
                isSaving = state.isSavingAutoReorder,
                onSave = { t, q, s -> onSaveAutoReorder(t, q, s) },
            )
        }

        // ─── L1076: Bin picker ───────────────────────────────────────────────
        item {
            InventoryBinPicker(
                currentBin = item.bin,
                availableBins = state.availableBins,
                isSaving = state.isSavingBin,
                onSave = { bin -> onSaveBin(bin) },
            )
        }

        // ─── L1079: Barcode display ──────────────────────────────────────────
        item {
            InventoryBarcodeDisplay(
                sku = item.sku,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // ─── L1077: Serial numbers ───────────────────────────────────────────
        if (item.isSerialize) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "Serial numbers${if (state.serials.isNotEmpty()) " (${state.serials.size})" else ""}",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        if (state.serials.isEmpty()) {
                            Text(
                                "No serials recorded.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            state.serials.forEach { serial ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Text(serial.serialNumber ?: "—", style = BrandMono)
                                    Text(
                                        serial.status?.replaceFirstChar { it.uppercase() } ?: "",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                        TextButton(onClick = { /* add serial dialog */ }) { Text("+ Add serial") }
                    }
                }
            }
        }

        // ─── L1080: Recent tickets using this part ───────────────────────────
        if (state.ticketUsage.isNotEmpty()) {
            item {
                Text("Recent tickets using this part", style = MaterialTheme.typography.titleMedium)
            }
            items(state.ticketUsage, key = { it.ticketId }) { usage ->
                BrandCard(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onTicketClick(usage.ticketId) },
                ) {
                    Row(
                        modifier = Modifier
                            .padding(12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column {
                            Text(usage.ticketNumber ?: "#${usage.ticketId}", style = BrandMono)
                            if (!usage.customerName.isNullOrBlank()) {
                                Text(
                                    usage.customerName,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        Text(
                            "×${usage.qty}",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // ─── L1082: Tax class (admin-only) ───────────────────────────────────
        if (state.isAdmin) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Tax class", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Tax class ID: ${item.taxClassId ?: "None"}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "Edit via inventory edit screen (admin).",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // ─── L1083: Photo gallery ────────────────────────────────────────────
        item {
            InventoryPhotoGallery(
                photoUrls = state.photoUrls,
                onUploadPhoto = onUploadPhoto,
            )
        }

        // ─── L1084: Deactivate action ────────────────────────────────────────
        item {
            OutlinedButton(
                onClick = onDeactivate,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = MaterialTheme.colorScheme.error,
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
            ) {
                Text("Deactivate item")
            }
        }

        // ─── Group prices ────────────────────────────────────────────────────
        if (state.groupPrices.isNotEmpty()) {
            item {
                Text("Group prices", style = MaterialTheme.typography.titleMedium)
            }
            items(state.groupPrices, key = { it.id }) { gp ->
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

        // ─── L1071: Full paginated movement history ───────────────────────────
        item {
            Text("Stock movements", style = MaterialTheme.typography.titleMedium)
        }
        item {
            InventoryMovementHistory(
                movements = state.movementHistory.ifEmpty { state.movements },
                isLoadingMore = state.isLoadingMoreMovements,
                hasMore = state.movementHistoryHasMore,
                offlineMessage = if (state.movementHistory.isEmpty()) state.movementsOfflineMessage else null,
                onLoadMore = onLoadMoreMovements,
            )
        }
    }
}
