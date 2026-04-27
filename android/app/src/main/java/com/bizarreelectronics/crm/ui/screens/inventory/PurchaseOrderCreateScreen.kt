package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.CreatePoLineItem
import com.bizarreelectronics.crm.data.remote.dto.CreatePurchaseOrderRequest
import com.bizarreelectronics.crm.data.remote.dto.SupplierListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PoLineItemForm(
    val inventoryItemId: String = "",
    val itemName: String = "",
    val qty: String = "1",
    val cost: String = "",
)

data class PoCreateUiState(
    val suppliers: List<SupplierListItem> = emptyList(),
    val selectedSupplierId: Long? = null,
    val notes: String = "",
    val expectedDate: String = "",
    val lines: List<PoLineItemForm> = listOf(PoLineItemForm()),
    val isLoadingSuppliers: Boolean = false,
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

@HiltViewModel
class PurchaseOrderCreateViewModel @Inject constructor(
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val _state = MutableStateFlow(PoCreateUiState())
    val state = _state.asStateFlow()

    init { loadSuppliers() }

    private fun loadSuppliers() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingSuppliers = true)
            try {
                val resp = inventoryApi.getSuppliers(activeOnly = true)
                _state.value = _state.value.copy(
                    suppliers = resp.data ?: emptyList(),
                    isLoadingSuppliers = false,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoadingSuppliers = false)
            }
        }
    }

    fun selectSupplier(id: Long) {
        _state.value = _state.value.copy(selectedSupplierId = id)
    }

    fun updateNotes(v: String) { _state.value = _state.value.copy(notes = v) }
    fun updateExpectedDate(v: String) { _state.value = _state.value.copy(expectedDate = v) }

    fun updateLine(index: Int, line: PoLineItemForm) {
        val lines = _state.value.lines.toMutableList()
        lines[index] = line
        _state.value = _state.value.copy(lines = lines)
    }

    fun addLine() {
        _state.value = _state.value.copy(lines = _state.value.lines + PoLineItemForm())
    }

    fun removeLine(index: Int) {
        if (_state.value.lines.size <= 1) return
        val lines = _state.value.lines.toMutableList()
        lines.removeAt(index)
        _state.value = _state.value.copy(lines = lines)
    }

    fun clearError() { _state.value = _state.value.copy(error = null) }

    fun submit() {
        val s = _state.value
        val supplierId = s.selectedSupplierId
        if (supplierId == null) {
            _state.value = s.copy(error = "Select a supplier")
            return
        }
        val validLines = s.lines.mapNotNull { line ->
            val itemId = line.inventoryItemId.toLongOrNull() ?: return@mapNotNull null
            val qty = line.qty.toIntOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
            CreatePoLineItem(
                inventoryItemId = itemId,
                quantityOrdered = qty,
                costPrice = line.cost.toDoubleOrNull(),
            )
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreatePurchaseOrderRequest(
                    supplierId = supplierId,
                    notes = s.notes.ifBlank { null },
                    expectedDate = s.expectedDate.ifBlank { null },
                    items = validLines,
                )
                val resp = inventoryApi.createPurchaseOrder(request)
                // Server may return `po` wrapper or flat row — check both.
                val id = resp.data?.po?.id ?: resp.data?.id
                _state.value = _state.value.copy(isSubmitting = false, createdId = id)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create purchase order",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurchaseOrderCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: PurchaseOrderCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.createdId) {
        val id = state.createdId ?: return@LaunchedEffect
        onCreated(id)
    }

    LaunchedEffect(state.error) {
        val e = state.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(e)
        viewModel.clearError()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_po_create),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.submit() },
                            enabled = state.selectedSupplierId != null,
                        ) { Text(stringResource(R.string.action_save)) }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Supplier picker
            SupplierDropdown(
                suppliers = state.suppliers,
                selectedId = state.selectedSupplierId,
                onSelect = viewModel::selectSupplier,
                isLoading = state.isLoadingSuppliers,
            )

            OutlinedTextField(
                value = state.expectedDate,
                onValueChange = viewModel::updateExpectedDate,
                label = { Text(stringResource(R.string.po_expected_date)) },
                placeholder = { Text("YYYY-MM-DD") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            OutlinedTextField(
                value = state.notes,
                onValueChange = viewModel::updateNotes,
                label = { Text(stringResource(R.string.po_notes)) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 2,
                maxLines = 4,
            )

            Text(
                stringResource(R.string.po_line_items),
                style = MaterialTheme.typography.titleSmall,
            )

            state.lines.forEachIndexed { index, line ->
                PoLineItemRow(
                    line = line,
                    index = index,
                    canRemove = state.lines.size > 1,
                    onChange = { viewModel.updateLine(index, it) },
                    onRemove = { viewModel.removeLine(index) },
                )
            }

            OutlinedButton(
                onClick = viewModel::addLine,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.po_add_line))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SupplierDropdown(
    suppliers: List<SupplierListItem>,
    selectedId: Long?,
    onSelect: (Long) -> Unit,
    isLoading: Boolean,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val selectedName = suppliers.firstOrNull { it.id == selectedId }?.name ?: ""

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded },
    ) {
        OutlinedTextField(
            value = if (isLoading) "Loading suppliers…" else selectedName,
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.po_supplier)) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth(),
            enabled = !isLoading,
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            suppliers.forEach { supplier ->
                DropdownMenuItem(
                    text = { Text(supplier.name ?: "Supplier ${supplier.id}") },
                    onClick = {
                        onSelect(supplier.id)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
private fun PoLineItemRow(
    line: PoLineItemForm,
    index: Int,
    canRemove: Boolean,
    onChange: (PoLineItemForm) -> Unit,
    onRemove: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Item ${index + 1}",
                    style = MaterialTheme.typography.labelMedium,
                )
                if (canRemove) {
                    IconButton(onClick = onRemove, modifier = Modifier.size(24.dp)) {
                        Icon(
                            Icons.Default.DeleteOutline,
                            contentDescription = "Remove item ${index + 1}",
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
            OutlinedTextField(
                value = line.inventoryItemId,
                onValueChange = { onChange(line.copy(inventoryItemId = it)) },
                label = { Text("Inventory item ID") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                OutlinedTextField(
                    value = line.qty,
                    onValueChange = { v -> if (v.isEmpty() || v.matches(Regex("^\\d+$"))) onChange(line.copy(qty = v)) },
                    label = { Text("Qty") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = line.cost,
                    onValueChange = { v -> if (v.isEmpty() || v.matches(Regex("^\\d*\\.?\\d*$"))) onChange(line.copy(cost = v)) },
                    label = { Text("Unit cost") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

