package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.PurchaseOrderApi
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.remote.dto.SupplierRow
import com.bizarreelectronics.crm.data.remote.dto.TaxClassOption
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
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
    /** Set to true after a "Save & add another" submit so the screen resets instead of navigating. */
    val savedAndAddAnother: Boolean = false,
    // §6.3: supplier picker
    val suppliers: List<SupplierRow> = emptyList(),
    val selectedSupplierId: Long? = null,
    val selectedSupplierName: String = "",
    // §6.3: tax class picker + tax-inclusive toggle
    val taxClasses: List<TaxClassOption> = emptyList(),
    val selectedTaxClassId: Long? = null,
    val selectedTaxClassName: String = "",
    val taxInclusive: Boolean = false,
)

@HiltViewModel
class InventoryCreateViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository,
    private val purchaseOrderApi: PurchaseOrderApi,
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val _state = MutableStateFlow(InventoryCreateUiState())
    val state = _state.asStateFlow()

    init {
        // §6.3: prefetch supplier and tax-class lists for pickers.
        viewModelScope.launch {
            try {
                val suppliersResponse = purchaseOrderApi.listSuppliers()
                if (suppliersResponse.success) {
                    _state.value = _state.value.copy(suppliers = suppliersResponse.data ?: emptyList())
                }
            } catch (_: Exception) { /* list remains empty — pickers still operable as free text */ }
        }
        viewModelScope.launch {
            try {
                val taxResponse = inventoryApi.getTaxClasses()
                if (taxResponse.success) {
                    _state.value = _state.value.copy(taxClasses = taxResponse.data ?: emptyList())
                }
            } catch (_: Exception) { /* list remains empty */ }
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

    // §6.3: supplier picker selection
    fun selectSupplier(supplier: SupplierRow?) {
        _state.value = _state.value.copy(
            selectedSupplierId = supplier?.id,
            selectedSupplierName = supplier?.name ?: "",
        )
    }

    // §6.3: tax class picker selection
    fun selectTaxClass(taxClass: TaxClassOption?) {
        _state.value = _state.value.copy(
            selectedTaxClassId = taxClass?.id,
            selectedTaxClassName = taxClass?.name ?: "",
        )
    }

    // §6.3: tax-inclusive toggle
    fun toggleTaxInclusive() {
        _state.value = _state.value.copy(taxInclusive = !_state.value.taxInclusive)
    }

    /** Called from the Scanner screen result (savedStateHandle "scanned_barcode"). */
    fun applyScannedBarcode(code: String) {
        val current = _state.value
        // Fill UPC if empty, otherwise fill SKU; prefer whichever is blank.
        _state.value = when {
            current.upcCode.isBlank() -> current.copy(upcCode = code)
            current.sku.isBlank()     -> current.copy(sku = code)
            else                      -> current.copy(upcCode = code)
        }
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    private fun validateForm(): String? {
        val current = _state.value
        if (current.name.isBlank()) return "Name is required"
        val retail = current.retailPrice.toDoubleOrNull()
        if (retail == null || retail <= 0.0) return "Retail price must be greater than 0"
        val costStr = current.costPrice
        if (costStr.isNotBlank() && costStr.toDoubleOrNull() == null) return "Cost price is not a valid number"
        val stockStr = current.inStock
        if (stockStr.isNotBlank() && stockStr.toIntOrNull() == null) return "Stock qty must be a whole number"
        val reorderStr = current.reorderLevel
        if (reorderStr.isNotBlank() && reorderStr.toIntOrNull() == null) return "Reorder level must be a whole number"
        return null
    }

    fun save(addAnother: Boolean = false) {
        val validationError = validateForm()
        if (validationError != null) {
            _state.value = _state.value.copy(error = validationError)
            return
        }
        val current = _state.value
        val retail = current.retailPrice.toDouble()

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
                    // §6.3: supplier, tax class, tax-inclusive
                    supplierId = current.selectedSupplierId,
                    taxClassId = current.selectedTaxClassId,
                    taxInclusive = if (current.taxInclusive) 1 else 0,
                )
                val createdId = inventoryRepository.createItem(request)
                if (addAnother) {
                    // Reset form fields; keep itemType and loaded picker lists as convenience for the user.
                    _state.value = InventoryCreateUiState(
                        itemType = current.itemType,
                        isSubmitting = false,
                        savedAndAddAnother = true,
                        suppliers = current.suppliers,
                        taxClasses = current.taxClasses,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        createdId = createdId,
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create inventory item",
                )
            }
        }
    }

    fun clearSavedAndAddAnother() {
        _state.value = _state.value.copy(savedAndAddAnother = false)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    /** Navigate to the shared BarcodeScanScreen; result arrives via [scannedBarcode]. */
    onScanBarcode: () -> Unit = {},
    /** Barcode delivered from BarcodeScanScreen via savedStateHandle. */
    scannedBarcode: String? = null,
    /** Called after the scanned barcode has been consumed so the caller can clear it. */
    onBarcodeLookupConsumed: () -> Unit = {},
    viewModel: InventoryCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Consume a scanned barcode delivered via savedStateHandle.
    LaunchedEffect(scannedBarcode) {
        val code = scannedBarcode ?: return@LaunchedEffect
        viewModel.applyScannedBarcode(code)
        onBarcodeLookupConsumed()
    }

    // Navigate on successful creation.
    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) {
            onCreated(id)
        }
    }

    // "Save & add another" feedback — show snackbar then clear flag.
    LaunchedEffect(state.savedAndAddAnother) {
        if (state.savedAndAddAnother) {
            snackbarHostState.showSnackbar("Item saved. Form cleared for next item.")
            viewModel.clearSavedAndAddAnother()
        }
    }

    // Show error via snackbar.
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
            BrandTopAppBar(
                title = "New Inventory Item",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // §6.3: inline barcode scan icon to fill UPC/SKU fields.
                    IconButton(onClick = onScanBarcode) {
                        Icon(
                            Icons.Filled.QrCodeScanner,
                            contentDescription = "Scan barcode to fill SKU / UPC",
                        )
                    }
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
            onSubmit = { if (canSave) viewModel.save() },
            // §6.3: "Save & add another" secondary CTA shown at the bottom.
            onSaveAndAddAnother = { if (canSave) viewModel.save(addAnother = true) },
            canSave = canSave,
            // §6.3: supplier picker
            suppliers = state.suppliers,
            selectedSupplierName = state.selectedSupplierName,
            onSupplierSelected = viewModel::selectSupplier,
            // §6.3: tax class picker + toggle
            taxClasses = state.taxClasses,
            selectedTaxClassName = state.selectedTaxClassName,
            onTaxClassSelected = viewModel::selectTaxClass,
            taxInclusive = state.taxInclusive,
            onTaxInclusiveToggle = viewModel::toggleTaxInclusive,
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
    // D5-6: caller-provided submit action fired by the IME Done key on the
    // final (Description) field. Callers pass their own save/guard logic so
    // Create and Edit can reuse this shared form.
    onSubmit: () -> Unit = {},
    /** §6.3: "Save & add another" secondary CTA. Null = not shown (Edit screen). */
    onSaveAndAddAnother: (() -> Unit)? = null,
    canSave: Boolean = true,
    // §6.3: supplier picker — empty list = picker not shown (e.g. Edit screen before wiring)
    suppliers: List<SupplierRow> = emptyList(),
    selectedSupplierName: String = "",
    onSupplierSelected: (SupplierRow?) -> Unit = {},
    // §6.3: tax class picker + tax-inclusive toggle
    taxClasses: List<TaxClassOption> = emptyList(),
    selectedTaxClassName: String = "",
    onTaxClassSelected: (TaxClassOption?) -> Unit = {},
    taxInclusive: Boolean = false,
    onTaxInclusiveToggle: () -> Unit = {},
) {
    // D5-6: IME Next advances focus, Done clears focus and invokes onSubmit.
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSubmit = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            onSubmit()
        },
    )

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
            keyboardActions = onNext,
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
                keyboardActions = onNext,
            )
            OutlinedTextField(
                value = upcCode,
                onValueChange = onUpcCodeChange,
                modifier = Modifier.weight(1f),
                label = { Text("UPC / Barcode") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
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
                leadingIcon = {
                    Text(
                        "$",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                placeholder = { Text("0.00") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )
            OutlinedTextField(
                value = retailPrice,
                onValueChange = onRetailPriceChange,
                modifier = Modifier.weight(1f),
                label = { Text("Retail Price *") },
                leadingIcon = {
                    Text(
                        "$",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                placeholder = { Text("0.00") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
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
                keyboardActions = onNext,
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
                keyboardActions = onNext,
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
            keyboardActions = onDoneSubmit,
        )

        // §6.3: Supplier picker — shown only when the list has loaded.
        if (suppliers.isNotEmpty()) {
            InventoryDropdownPicker(
                label = "Supplier",
                selectedLabel = selectedSupplierName.ifBlank { "None" },
                options = listOf(null to "None") + suppliers.map { it to it.name },
                onOptionSelected = { onSupplierSelected(it) },
            )
        }

        // §6.3: Tax class picker + tax-inclusive toggle.
        if (taxClasses.isNotEmpty()) {
            InventoryDropdownPicker(
                label = "Tax Class",
                selectedLabel = selectedTaxClassName.ifBlank { "None" },
                options = listOf(null to "None") + taxClasses.map { it to "${it.name} (${it.rate}%)" },
                onOptionSelected = { onTaxClassSelected(it) },
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "Price is tax-inclusive",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Switch(
                    checked = taxInclusive,
                    onCheckedChange = { onTaxInclusiveToggle() },
                )
            }
        }

        // §6.3: "Save & add another" secondary CTA — only shown on the Create screen.
        if (onSaveAndAddAnother != null) {
            androidx.compose.material3.OutlinedButton(
                onClick = onSaveAndAddAnother,
                enabled = canSave,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Save & add another")
            }
        }
    }
}

/**
 * Generic single-select dropdown picker used for Supplier and Tax Class in §6.3.
 * [options] is a list of (value, displayLabel) pairs; null value = "None" sentinel.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> InventoryDropdownPicker(
    label: String,
    selectedLabel: String,
    options: List<Pair<T?, String>>,
    onOptionSelected: (T?) -> Unit,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded },
    ) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = { },
            readOnly = true,
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth(),
            label = { Text(label) },
            trailingIcon = {
                Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
            },
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { (value, display) ->
                DropdownMenuItem(
                    text = { Text(display) },
                    onClick = {
                        onOptionSelected(value)
                        expanded = false
                    },
                )
            }
        }
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
                // decorative — dropdown chevron inside a labeled ExposedDropdownMenuBox TextField; the label "Item Type" announces the purpose
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
