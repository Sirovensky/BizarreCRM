package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
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
    // §6.4: quick stock adjust in edit screen
    val showSetStockDialog: Boolean = false,
    val setStockValue: String = "",
    /** True while delete/deactivate is in-flight. */
    val isDeletingItem: Boolean = false,
    /** True when delete succeeded — pop back. */
    val deletedAndShouldPop: Boolean = false,
)

@HiltViewModel
class InventoryEditViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val inventoryRepository: InventoryRepository,
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

    // -----------------------------------------------------------------------
    // §6.4: Quick stock adjust (+1 / −1 / Set to…)
    // -----------------------------------------------------------------------

    /** Adjust stock by [delta] (+1 or −1) using the adjust-stock endpoint. */
    fun quickAdjustStock(delta: Int) {
        val current = _state.value.item ?: return
        val newStock = maxOf(0, current.inStock + delta)
        // Optimistic local update
        _state.value = _state.value.copy(
            item = current.copy(inStock = newStock),
            inStock = newStock.toString(),
        )
        viewModelScope.launch {
            try {
                inventoryRepository.adjustStock(
                    id = itemId,
                    request = AdjustStockRequest(
                        quantity = delta,
                        type = if (delta > 0) "received" else "adjusted",
                        reason = if (delta > 0) "Quick +1" else "Quick -1",
                    ),
                )
            } catch (e: Exception) {
                // Roll back optimistic update
                _state.value = _state.value.copy(
                    item = current,
                    inStock = current.inStock.toString(),
                    saveMessage = "Stock adjust failed: ${e.message}",
                )
            }
        }
    }

    fun showSetStockDialog() {
        _state.value = _state.value.copy(
            showSetStockDialog = true,
            setStockValue = _state.value.inStock,
        )
    }

    fun dismissSetStockDialog() {
        _state.value = _state.value.copy(showSetStockDialog = false, setStockValue = "")
    }

    fun updateSetStockValue(v: String) {
        if (v.isEmpty() || v.matches(Regex("^\\d+$"))) {
            _state.value = _state.value.copy(setStockValue = v)
        }
    }

    /** Set stock to an absolute value using a delta-based adjust call. */
    fun confirmSetStock() {
        val current = _state.value.item ?: return
        val target = _state.value.setStockValue.toIntOrNull() ?: return
        val delta = target - current.inStock
        _state.value = _state.value.copy(
            showSetStockDialog = false,
            item = current.copy(inStock = target),
            inStock = target.toString(),
        )
        viewModelScope.launch {
            try {
                inventoryRepository.adjustStock(
                    id = itemId,
                    request = AdjustStockRequest(
                        quantity = delta,
                        type = "adjusted",
                        reason = "Set to $target",
                    ),
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    item = current,
                    inStock = current.inStock.toString(),
                    saveMessage = "Set stock failed: ${e.message}",
                )
            }
        }
    }

    // -----------------------------------------------------------------------
    // §6.4: Delete (soft-deactivate) from edit screen
    // -----------------------------------------------------------------------

    /** Soft-delete (deactivate) the item. On success pops back to list. */
    fun deleteItem() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isDeletingItem = true)
            try {
                val warning = inventoryRepository.deleteItem(itemId)
                _state.value = _state.value.copy(
                    isDeletingItem = false,
                    saveMessage = warning ?: "Item deactivated",
                    deletedAndShouldPop = true,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isDeletingItem = false,
                    saveMessage = "Delete failed: ${e.message}",
                )
            }
        }
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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryEditScreen(
    onBack: () -> Unit,
    onSaved: () -> Unit,
    viewModel: InventoryEditViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

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

    // Pop back when item was deleted/deactivated from the edit screen
    LaunchedEffect(state.deletedAndShouldPop) {
        if (state.deletedAndShouldPop) onBack()
    }

    val canSave = state.name.isNotBlank() &&
        (state.retailPrice.toDoubleOrNull() ?: 0.0) > 0.0 &&
        !state.isSaving

    val barTitle = state.item?.name?.ifBlank { null }
        ?: if (state.isLoading) "Loading..." else "Edit item"

    var showDeleteDialog by rememberSaveable { mutableStateOf(false) }
    var showOverflow by remember { mutableStateOf(false) }

    // §6.4: Set-stock dialog
    if (state.showSetStockDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissSetStockDialog() },
            title = { Text("Set stock to…") },
            text = {
                OutlinedTextField(
                    value = state.setStockValue,
                    onValueChange = viewModel::updateSetStockValue,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Quantity") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Number,
                    ),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.confirmSetStock() },
                    enabled = state.setStockValue.toIntOrNull() != null,
                ) { Text("Set") }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissSetStockDialog() }) { Text("Cancel") }
            },
        )
    }

    // §6.4: Delete confirm dialog
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Deactivate item?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("This item will be marked inactive and hidden from inventory. Historical records are preserved.")
                    if (state.isDeletingItem) {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.deleteItem() },
                    enabled = !state.isDeletingItem,
                ) {
                    Text("Deactivate", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDeleteDialog = false },
                    enabled = !state.isDeletingItem,
                ) { Text("Cancel") }
            },
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
                    if (state.isSaving || state.isDeletingItem) {
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
                        // §6.4: overflow menu — quick stock adjust + deactivate
                        Box {
                            IconButton(onClick = { showOverflow = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "More actions")
                            }
                            DropdownMenu(
                                expanded = showOverflow,
                                onDismissRequest = { showOverflow = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("+1 stock") },
                                    onClick = {
                                        showOverflow = false
                                        viewModel.quickAdjustStock(+1)
                                    },
                                    leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) },
                                )
                                DropdownMenuItem(
                                    text = { Text("-1 stock") },
                                    onClick = {
                                        showOverflow = false
                                        viewModel.quickAdjustStock(-1)
                                    },
                                    leadingIcon = { Icon(Icons.Default.Remove, contentDescription = null) },
                                )
                                DropdownMenuItem(
                                    text = { Text("Set to…") },
                                    onClick = {
                                        showOverflow = false
                                        viewModel.showSetStockDialog()
                                    },
                                    leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) },
                                )
                                HorizontalDivider()
                                DropdownMenuItem(
                                    text = { Text("Deactivate", color = MaterialTheme.colorScheme.error) },
                                    onClick = {
                                        showOverflow = false
                                        showDeleteDialog = true
                                    },
                                    leadingIcon = {
                                        Icon(
                                            Icons.Default.VisibilityOff,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.error,
                                        )
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
