package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
// @audit-fixed: Section 33 / D1 — costPrice / retailPrice are now top-level
// extension properties on InventoryItemEntity that read from the new Long-cents
// columns. They must be imported explicitly because Kotlin does not pull
// extension members in via the entity import alone.
import com.bizarreelectronics.crm.data.local.db.entities.costPrice
import com.bizarreelectronics.crm.data.local.db.entities.retailPrice
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.UndoStack
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * Reversible field edits made from the inventory-edit screen.
 * Named `InventoryItemEdit` (not `InventoryEdit`) to avoid collision with the
 * identically-named sealed class in InventoryDetailScreen.
 */
sealed class InventoryItemEdit {
    data class FieldEdit(
        val fieldName: String,
        val oldValue: String?,
        val newValue: String?,
    ) : InventoryItemEdit()
}

data class InventoryEditUiState(
    val item: InventoryItemEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val name: String = "",
    val sku: String = "",
    val upcCode: String = "",
    val itemType: String = "product",
    val costPrice: String = "",
    val retailPrice: String = "",
    val inStock: String = "",
    val reorderLevel: String = "",
    val description: String = "",
    val hasInitialized: Boolean = false,
    val isSaving: Boolean = false,
    val saveMessage: String? = null,
    val saved: Boolean = false,
    /** Non-null while an undo snackbar is pending display. */
    val undoMessage: String? = null,
    /** True when the undo stack has at least one undoable action. */
    val canUndo: Boolean = false,
    /** §6.4: true while delete confirm dialog is visible. */
    val showDeleteDialog: Boolean = false,
    /** §6.4: true while deactivate confirm dialog is visible. */
    val showDeactivateDialog: Boolean = false,
    /** §6.4: true while stock-adjust sheet is open. */
    val showStockAdjustSheet: Boolean = false,
    /** §6.4: set after item is deleted — signals the screen to pop back. */
    val deleted: Boolean = false,
    /** §6.4: set after item is deactivated — signals the screen to pop back. */
    val deactivated: Boolean = false,
)

@HiltViewModel
class InventoryEditViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val inventoryRepository: InventoryRepository,
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val itemId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(InventoryEditUiState())
    val state = _state.asStateFlow()
    private var collectJob: Job? = null

    /** Undo/redo history for optimistic field-edit writes made on this screen. */
    val undoStack = UndoStack<InventoryItemEdit>()

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
                        Timber.tag("InventoryItemUndo").i("Undone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Redone ->
                        Timber.tag("InventoryItemUndo").i("Redone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Failed ->
                        Timber.tag("InventoryItemUndo").w("Failed: ${event.reason} — ${event.entry.auditDescription}")
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
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                inventoryRepository.getItem(itemId).collectLatest { entity ->
                    val current = _state.value
                    // Populate fields from entity ONCE, so the user's edits aren't clobbered
                    // when a background refresh re-emits the same item.
                    if (entity != null && !current.hasInitialized) {
                        _state.value = current.copy(
                            item = entity,
                            isLoading = false,
                            name = entity.name,
                            sku = entity.sku ?: "",
                            upcCode = entity.upcCode ?: "",
                            itemType = entity.itemType ?: "product",
                            costPrice = if (entity.costPrice > 0.0) formatAmount(entity.costPrice) else "",
                            retailPrice = if (entity.retailPrice > 0.0) formatAmount(entity.retailPrice) else "",
                            inStock = entity.inStock.toString(),
                            reorderLevel = if (entity.reorderLevel > 0) entity.reorderLevel.toString() else "",
                            description = entity.description ?: "",
                            hasInitialized = true,
                        )
                    } else {
                        _state.value = current.copy(item = entity, isLoading = false)
                    }
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load inventory item. Check your connection and try again.",
                )
            }
        }
    }

    fun updateName(value: String) { _state.value = _state.value.copy(name = value) }
    fun updateSku(value: String) { _state.value = _state.value.copy(sku = value) }
    fun updateUpcCode(value: String) { _state.value = _state.value.copy(upcCode = value) }
    fun updateItemType(value: String) { _state.value = _state.value.copy(itemType = value) }
    fun updateCostPrice(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d*$"))) {
            _state.value = _state.value.copy(costPrice = value)
        }
    }
    fun updateRetailPrice(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d*$"))) {
            _state.value = _state.value.copy(retailPrice = value)
        }
    }
    fun updateInStock(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*$"))) {
            _state.value = _state.value.copy(inStock = value)
        }
    }
    fun updateReorderLevel(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*$"))) {
            _state.value = _state.value.copy(reorderLevel = value)
        }
    }
    fun updateDescription(value: String) { _state.value = _state.value.copy(description = value) }

    fun clearSaveMessage() {
        _state.value = _state.value.copy(saveMessage = null)
    }

    fun saveItem() {
        val current = _state.value
        if (current.name.isBlank()) {
            _state.value = current.copy(saveMessage = "Name is required")
            return
        }
        val retail = current.retailPrice.toDoubleOrNull()
        if (retail == null || retail <= 0.0) {
            _state.value = current.copy(saveMessage = "Retail price must be greater than 0")
            return
        }

        // Snapshot original values from the loaded entity for diffing.
        val originalItem = current.item

        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true)
            try {
                val request = CreateInventoryRequest(
                    name = current.name.trim(),
                    itemType = current.itemType,
                    description = current.description.trim().ifBlank { null },
                    sku = current.sku.trim().ifBlank { null },
                    upcCode = current.upcCode.trim().ifBlank { null },
                    inStock = current.inStock.toIntOrNull() ?: 0,
                    costPrice = current.costPrice.toDoubleOrNull(),
                    price = retail,
                    reorderLevel = current.reorderLevel.toIntOrNull(),
                )
                inventoryRepository.updateItem(itemId, request)

                // Push one undo entry per changed field so each change is
                // individually undoable. Diff current form state against the
                // original entity snapshot captured before the save.
                if (originalItem != null) {
                    pushFieldUndoEntries(current, originalItem, request)
                }

                _state.value = _state.value.copy(
                    isSaving = false,
                    undoMessage = "Inventory item updated",
                    saved = true,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveMessage = e.message ?: "Failed to update inventory item",
                )
            }
        }
    }

    /**
     * Computes field-level diffs between the submitted form state and the
     * original loaded entity, then pushes one [UndoStack.Entry] per changed
     * field. The compensating sync calls [InventoryRepository.updateItem] with
     * the old values restored.
     */
    private suspend fun pushFieldUndoEntries(
        current: InventoryEditUiState,
        original: InventoryItemEntity,
        savedRequest: CreateInventoryRequest,
    ) {
        data class Diff(val field: String, val old: String?, val new: String?)

        val diffs = buildList {
            val oldName = original.name
            val newName = savedRequest.name
            if (oldName != newName) add(Diff("name", oldName, newName))

            val oldSku = original.sku ?: ""
            val newSku = savedRequest.sku ?: ""
            if (oldSku != newSku) add(Diff("sku", oldSku.ifBlank { null }, newSku.ifBlank { null }))

            val oldUpc = original.upcCode ?: ""
            val newUpc = savedRequest.upcCode ?: ""
            if (oldUpc != newUpc) add(Diff("upcCode", oldUpc.ifBlank { null }, newUpc.ifBlank { null }))

            val oldType = original.itemType ?: "product"
            val newType = savedRequest.itemType
            if (oldType != newType) add(Diff("itemType", oldType, newType))

            val oldCost = if (original.costPrice > 0.0) formatAmount(original.costPrice) else ""
            val newCost = current.costPrice
            if (oldCost != newCost) add(Diff("costPrice", oldCost.ifBlank { null }, newCost.ifBlank { null }))

            val oldRetail = if (original.retailPrice > 0.0) formatAmount(original.retailPrice) else ""
            val newRetail = current.retailPrice
            if (oldRetail != newRetail) add(Diff("retailPrice", oldRetail.ifBlank { null }, newRetail.ifBlank { null }))

            val oldStock = original.inStock.toString()
            val newStock = current.inStock
            if (oldStock != newStock) add(Diff("inStock", oldStock, newStock))

            val oldReorder = if (original.reorderLevel > 0) original.reorderLevel.toString() else ""
            val newReorder = current.reorderLevel
            if (oldReorder != newReorder) add(Diff("reorderLevel", oldReorder.ifBlank { null }, newReorder.ifBlank { null }))

            val oldDesc = original.description ?: ""
            val newDesc = savedRequest.description ?: ""
            if (oldDesc != newDesc) add(Diff("description", oldDesc.ifBlank { null }, newDesc.ifBlank { null }))
        }

        if (diffs.isEmpty()) return

        // Build a restore request from the original entity values (old state).
        // A single whole-entity PUT reverts all changed fields at once; each
        // per-field undo entry shares the same compensatingSync lambda so that
        // undoing any single field always restores the complete original state.
        val restoreRequest = CreateInventoryRequest(
            name = original.name,
            itemType = original.itemType ?: "product",
            description = original.description?.ifBlank { null },
            sku = original.sku?.ifBlank { null },
            upcCode = original.upcCode?.ifBlank { null },
            inStock = original.inStock,
            costPrice = if (original.costPrice > 0.0) original.costPrice else null,
            price = original.retailPrice,
            reorderLevel = if (original.reorderLevel > 0) original.reorderLevel else null,
        )

        for (diff in diffs) {
            val auditDesc = "Edited ${diff.field} from '${diff.old ?: ""}' to '${diff.new ?: ""}'"
            undoStack.push(
                UndoStack.Entry(
                    payload = InventoryItemEdit.FieldEdit(
                        fieldName = diff.field,
                        oldValue = diff.old,
                        newValue = diff.new,
                    ),
                    apply = {
                        // Redo: optimistically reflect the new value in UI state.
                        _state.value = applyFieldToState(_state.value, diff.field, diff.new)
                    },
                    reverse = {
                        // Undo: optimistically restore the old value in UI state.
                        _state.value = applyFieldToState(_state.value, diff.field, diff.old)
                    },
                    auditDescription = auditDesc,
                    compensatingSync = {
                        try {
                            inventoryRepository.updateItem(itemId, restoreRequest)
                            true
                        } catch (_: Exception) {
                            false
                        }
                    },
                ),
            )
        }
    }

    /** Returns a new [InventoryEditUiState] with [fieldName] set to [value]. */
    private fun applyFieldToState(
        s: InventoryEditUiState,
        fieldName: String,
        value: String?,
    ): InventoryEditUiState = when (fieldName) {
        "name"         -> s.copy(name = value ?: "")
        "sku"          -> s.copy(sku = value ?: "")
        "upcCode"      -> s.copy(upcCode = value ?: "")
        "itemType"     -> s.copy(itemType = value ?: "product")
        "costPrice"    -> s.copy(costPrice = value ?: "")
        "retailPrice"  -> s.copy(retailPrice = value ?: "")
        "inStock"      -> s.copy(inStock = value ?: "0")
        "reorderLevel" -> s.copy(reorderLevel = value ?: "")
        "description"  -> s.copy(description = value ?: "")
        else           -> s
    }

    /** Undo the most recent reversible field edit. */
    fun performUndo() {
        viewModelScope.launch {
            val ok = undoStack.undo()
            if (!ok) {
                _state.value = _state.value.copy(saveMessage = "Nothing to undo")
            }
        }
    }

    fun clearUndoMessage() {
        _state.value = _state.value.copy(undoMessage = null)
    }

    private fun formatAmount(value: Double): String {
        // @audit-fixed: was String.format("%.2f", value) which uses the default
        // platform locale and produces comma decimal separators in many EU
        // locales (e.g. "12,34"). The pre-filled value would then fail
        // toDoubleOrNull() parsing on save and the user would see a phantom
        // "Retail price must be greater than 0" error. Pinning to Locale.US
        // matches the wire format and the regex in updateRetailPrice().
        return if (value % 1.0 == 0.0) value.toLong().toString()
        else String.format(java.util.Locale.US, "%.2f", value)
    }

    // ── §6.4: Delete / Deactivate / Stock-adjust quick-actions ──────────────

    fun setShowDeleteDialog(show: Boolean) {
        _state.value = _state.value.copy(showDeleteDialog = show)
    }

    fun confirmDelete() {
        viewModelScope.launch {
            _state.value = _state.value.copy(showDeleteDialog = false, isSaving = true)
            try {
                inventoryApi.deleteItem(itemId)
                _state.value = _state.value.copy(isSaving = false, deleted = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveMessage = e.message ?: "Failed to delete item",
                )
            }
        }
    }

    fun setShowDeactivateDialog(show: Boolean) {
        _state.value = _state.value.copy(showDeactivateDialog = show)
    }

    fun confirmDeactivate() {
        // Deactivation on the server is handled by the same DELETE endpoint
        // (it sets is_active=0 and preserves history).
        viewModelScope.launch {
            _state.value = _state.value.copy(showDeactivateDialog = false, isSaving = true)
            try {
                inventoryApi.deleteItem(itemId)
                _state.value = _state.value.copy(isSaving = false, deactivated = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveMessage = e.message ?: "Failed to deactivate item",
                )
            }
        }
    }

    fun setShowStockAdjustSheet(show: Boolean) {
        _state.value = _state.value.copy(showStockAdjustSheet = show)
    }

    /** §6.4: Quick stock-adjust: delta can be +1, -1, or "set to N". */
    fun quickAdjustStock(delta: Int?, setTo: Int? = null) {
        viewModelScope.launch {
            val current = _state.value
            val oldQty = current.item?.inStock ?: 0
            val qty: Int
            val type: String
            if (setTo != null) {
                qty = setTo - oldQty
                type = "adjustment"
            } else {
                qty = delta ?: return@launch
                type = if (qty > 0) "received" else "sold"
            }
            if (qty == 0) return@launch
            try {
                inventoryRepository.adjustStock(
                    itemId,
                    AdjustStockRequest(quantity = qty, type = type, reason = "manual"),
                )
                _state.value = _state.value.copy(
                    showStockAdjustSheet = false,
                    saveMessage = if (qty > 0) "Stock +$qty" else "Stock $qty",
                    // Optimistically update the form field.
                    inStock = (oldQty + qty).toString(),
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    saveMessage = e.message ?: "Stock adjust failed",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryEditScreen(
    onBack: () -> Unit,
    onSaved: () -> Unit,
    /** Called after a delete or deactivate — caller should pop back to list. */
    onDeleted: () -> Unit = onSaved,
    viewModel: InventoryEditViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showOverflowMenu by rememberSaveable { mutableStateOf(false) }

    // Clear the undo stack when the screen leaves composition (nav back / replace).
    DisposableEffect(Unit) {
        onDispose { viewModel.undoStack.clear() }
    }

    // Generic error/validation snackbar (no Undo action).
    LaunchedEffect(state.saveMessage) {
        val msg = state.saveMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSaveMessage()
        }
    }

    // Undo snackbar: shown after a successful save with an Undo action.
    LaunchedEffect(state.undoMessage) {
        state.undoMessage?.let { message ->
            viewModel.clearUndoMessage()
            val result = snackbarHostState.showSnackbar(
                message = message,
                actionLabel = if (state.canUndo) "Undo" else null,
                duration = SnackbarDuration.Short,
            )
            if (result == SnackbarResult.ActionPerformed) {
                viewModel.performUndo()
            }
        }
    }

    LaunchedEffect(state.saved) {
        if (state.saved) {
            onSaved()
        }
    }

    // §6.4: pop back after delete or deactivate.
    LaunchedEffect(state.deleted, state.deactivated) {
        if (state.deleted || state.deactivated) {
            onDeleted()
        }
    }

    val canSave = state.name.isNotBlank() &&
        (state.retailPrice.toDoubleOrNull() ?: 0.0) > 0.0 &&
        !state.isSaving

    val barTitle = state.item?.name?.ifBlank { null }
        ?: if (state.isLoading) "Loading..." else "Edit item"

    // §6.4: Delete confirm dialog.
    if (state.showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.setShowDeleteDialog(false) },
            title = { Text("Delete item") },
            text = { Text("Remove \"${state.name}\"? This cannot be undone. Historical records on invoices and tickets are preserved.") },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.confirmDelete() },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.setShowDeleteDialog(false) }) { Text("Cancel") }
            },
        )
    }

    // §6.4: Deactivate confirm dialog.
    if (state.showDeactivateDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.setShowDeactivateDialog(false) },
            title = { Text("Deactivate item") },
            text = { Text("Deactivate \"${state.name}\"? It will be hidden from POS and lookups. Historical records are preserved and you can reactivate it later.") },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmDeactivate() }) { Text("Deactivate") }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.setShowDeactivateDialog(false) }) { Text("Cancel") }
            },
        )
    }

    // §6.4: Stock adjust bottom sheet.
    if (state.showStockAdjustSheet) {
        StockAdjustSheet(
            currentStock = state.item?.inStock ?: (state.inStock.toIntOrNull() ?: 0),
            onDismiss = { viewModel.setShowStockAdjustSheet(false) },
            onAdjust = { delta -> viewModel.quickAdjustStock(delta = delta) },
            onSetTo = { qty -> viewModel.quickAdjustStock(delta = null, setTo = qty) },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = barTitle,
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.saveItem() },
                            enabled = canSave,
                        ) {
                            Text("Save")
                        }
                    }
                    // §6.4: overflow menu — stock adjust / deactivate / delete.
                    Box {
                        IconButton(onClick = { showOverflowMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More actions")
                        }
                        DropdownMenu(
                            expanded = showOverflowMenu,
                            onDismissRequest = { showOverflowMenu = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Adjust stock") },
                                leadingIcon = {
                                    Icon(Icons.Default.Add, contentDescription = null)
                                },
                                onClick = {
                                    showOverflowMenu = false
                                    viewModel.setShowStockAdjustSheet(true)
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Deactivate") },
                                onClick = {
                                    showOverflowMenu = false
                                    viewModel.setShowDeactivateDialog(true)
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        "Delete",
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.DeleteOutline,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                },
                                onClick = {
                                    showOverflowMenu = false
                                    viewModel.setShowDeleteDialog(true)
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading && !state.hasInitialized -> {
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
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = { viewModel.loadItem() }) { Text("Retry") }
                    }
                }
            }
            else -> {
                InventoryFormContent(
                    padding = padding,
                    name = state.name,
                    onNameChange = viewModel::updateName,
                    sku = state.sku,
                    onSkuChange = viewModel::updateSku,
                    upcCode = state.upcCode,
                    onUpcCodeChange = viewModel::updateUpcCode,
                    itemType = state.itemType,
                    onItemTypeChange = viewModel::updateItemType,
                    costPrice = state.costPrice,
                    onCostPriceChange = viewModel::updateCostPrice,
                    retailPrice = state.retailPrice,
                    onRetailPriceChange = viewModel::updateRetailPrice,
                    inStock = state.inStock,
                    onInStockChange = viewModel::updateInStock,
                    reorderLevel = state.reorderLevel,
                    onReorderLevelChange = viewModel::updateReorderLevel,
                    description = state.description,
                    onDescriptionChange = viewModel::updateDescription,
                    // D5-6: IME Done on Description triggers the same save
                    // the toolbar Save button does, guarded by canSave.
                    onSubmit = { if (canSave) viewModel.saveItem() },
                )
            }
        }
    }
}

/**
 * §6.4: ModalBottomSheet for quick stock adjustment.
 * Offers +1 / -1 shortcuts plus a "Set to…" free-entry field.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StockAdjustSheet(
    currentStock: Int,
    onDismiss: () -> Unit,
    onAdjust: (Int) -> Unit,
    onSetTo: (Int) -> Unit,
) {
    var setToText by rememberSaveable { mutableStateOf("") }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                "Adjust stock",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "Current: $currentStock",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                FilledTonalButton(
                    onClick = { onAdjust(-1) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.Remove, contentDescription = "Decrease stock by 1")
                    Spacer(Modifier.width(4.dp))
                    Text("−1")
                }
                FilledTonalButton(
                    onClick = { onAdjust(1) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Increase stock by 1")
                    Spacer(Modifier.width(4.dp))
                    Text("+1")
                }
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                OutlinedTextField(
                    value = setToText,
                    onValueChange = { v -> if (v.isEmpty() || v.matches(Regex("^\\d+$"))) setToText = v },
                    label = { Text("Set to…") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                FilledTonalButton(
                    onClick = {
                        val qty = setToText.toIntOrNull()
                        if (qty != null) onSetTo(qty)
                    },
                    enabled = setToText.toIntOrNull() != null,
                ) { Text("Set") }
            }
        }
    }
}
