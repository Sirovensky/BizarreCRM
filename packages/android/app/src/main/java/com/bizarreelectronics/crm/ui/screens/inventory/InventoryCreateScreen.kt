package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InventoryCreateUiState(
    val name: String = "",
    val sku: String = "",
    val upcCode: String = "",
    val itemType: String = "product",
    val costPrice: String = "",
    val retailPrice: String = "",
    val inStock: String = "",
    val reorderLevel: String = "",
    val description: String = "",
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

@HiltViewModel
class InventoryCreateViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(InventoryCreateUiState())
    val state = _state.asStateFlow()

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

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun save() {
        val current = _state.value
        if (current.name.isBlank()) {
            _state.value = current.copy(error = "Name is required")
            return
        }
        val retail = current.retailPrice.toDoubleOrNull()
        if (retail == null || retail <= 0.0) {
            _state.value = current.copy(error = "Retail price must be greater than 0")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
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
                val createdId = inventoryRepository.createItem(request)
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create inventory item",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: InventoryCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate on successful creation
    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) {
            onCreated(id)
        }
    }

    // Show error via snackbar
    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    val canSave = state.name.isNotBlank() &&
        (state.retailPrice.toDoubleOrNull() ?: 0.0) > 0.0

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("New Inventory Item") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = canSave,
                        ) {
                            Text("Save")
                        }
                    }
                },
            )
        },
    ) { padding ->
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

/**
 * Shared composable used by both Create and Edit screens to render the inventory form.
 * Keeps form UI in one place so future edits don't drift between the two screens.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun InventoryFormContent(
    padding: PaddingValues,
    name: String,
    onNameChange: (String) -> Unit,
    sku: String,
    onSkuChange: (String) -> Unit,
    upcCode: String,
    onUpcCodeChange: (String) -> Unit,
    itemType: String,
    onItemTypeChange: (String) -> Unit,
    costPrice: String,
    onCostPriceChange: (String) -> Unit,
    retailPrice: String,
    onRetailPriceChange: (String) -> Unit,
    inStock: String,
    onInStockChange: (String) -> Unit,
    reorderLevel: String,
    onReorderLevelChange: (String) -> Unit,
    description: String,
    onDescriptionChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .imePadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        OutlinedTextField(
            value = name,
            onValueChange = onNameChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Name *") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        )

        ItemTypeDropdown(
            value = itemType,
            onValueChange = onItemTypeChange,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = sku,
                onValueChange = onSkuChange,
                modifier = Modifier.weight(1f),
                label = { Text("SKU") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )
            OutlinedTextField(
                value = upcCode,
                onValueChange = onUpcCodeChange,
                modifier = Modifier.weight(1f),
                label = { Text("UPC / Barcode") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = costPrice,
                onValueChange = onCostPriceChange,
                modifier = Modifier.weight(1f),
                label = { Text("Cost Price") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
            )
            OutlinedTextField(
                value = retailPrice,
                onValueChange = onRetailPriceChange,
                modifier = Modifier.weight(1f),
                label = { Text("Retail Price *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = inStock,
                onValueChange = onInStockChange,
                modifier = Modifier.weight(1f),
                label = { Text("Stock") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
            )
            OutlinedTextField(
                value = reorderLevel,
                onValueChange = onReorderLevelChange,
                modifier = Modifier.weight(1f),
                label = { Text("Reorder Level") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
            )
        }

        OutlinedTextField(
            value = description,
            onValueChange = onDescriptionChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Description") },
            minLines = 3,
            maxLines = 6,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ItemTypeDropdown(
    value: String,
    onValueChange: (String) -> Unit,
) {
    val options = listOf("product", "part", "service")
    // U7 fix: dropdown state saved across rotation.
    var expanded by rememberSaveable { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded },
    ) {
        OutlinedTextField(
            value = value.replaceFirstChar { it.uppercase() },
            onValueChange = { },
            readOnly = true,
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth(),
            label = { Text("Item Type") },
            trailingIcon = {
                Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
            },
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.replaceFirstChar { it.uppercase() }) },
                    onClick = {
                        onValueChange(option)
                        expanded = false
                    },
                )
            }
        }
    }
}
