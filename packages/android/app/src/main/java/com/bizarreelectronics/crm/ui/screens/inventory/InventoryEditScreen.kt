package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

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

    init {
        loadItem()
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
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveMessage = "Inventory item updated",
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

    LaunchedEffect(state.saveMessage) {
        val msg = state.saveMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSaveMessage()
        }
    }

    LaunchedEffect(state.saved) {
        if (state.saved) {
            onSaved()
        }
    }

    val canSave = state.name.isNotBlank() &&
        (state.retailPrice.toDoubleOrNull() ?: 0.0) > 0.0 &&
        !state.isSaving

    val barTitle = state.item?.name?.ifBlank { null }
        ?: if (state.isLoading) "Loading..." else "Edit item"

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
                )
            }
        }
    }
}
