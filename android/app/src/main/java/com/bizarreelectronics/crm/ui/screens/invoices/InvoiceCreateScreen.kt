package com.bizarreelectronics.crm.ui.screens.invoices

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.CreateInvoiceRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateLineItemDto
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Calendar
import javax.inject.Inject

// ─── UiState ─────────────────────────────────────────────────────────────────

data class LineItemRow(
    val description: String = "",
    val qty: String = "1",
    val unitPrice: String = "",
)

data class InvoiceCreateUiState(
    val customerSearchQuery: String = "",
    val customerSearchResults: List<CustomerListItem> = emptyList(),
    val selectedCustomer: CustomerListItem? = null,
    val showCustomerDropdown: Boolean = false,
    val lineItems: List<LineItemRow> = listOf(LineItemRow()),
    val notes: String = "",
    val dueDate: String = "",
    val loading: Boolean = false,
    val error: String? = null,
    val created: Long? = null,           // non-null after successful creation
)

private fun InvoiceCreateUiState.subtotalCents(): Long =
    lineItems.sumOf { row ->
        val qty = row.qty.toLongOrNull() ?: 0L
        val cents = (row.unitPrice.toDoubleOrNull() ?: 0.0)
            .let { d -> (d * 100).toLong() }
        qty * cents
    }

private fun InvoiceCreateUiState.isSubmittable(): Boolean =
    selectedCustomer != null &&
        lineItems.any { it.description.isNotBlank() && (it.unitPrice.toDoubleOrNull() ?: 0.0) > 0 }

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class InvoiceCreateViewModel @Inject constructor(
    private val invoiceApi: InvoiceApi,
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val _state = MutableStateFlow(InvoiceCreateUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null

    fun onCustomerQueryChanged(query: String) {
        _state.value = _state.value.copy(
            customerSearchQuery = query,
            selectedCustomer = null,
            showCustomerDropdown = query.isNotBlank(),
        )
        searchJob?.cancel()
        if (query.isBlank()) {
            _state.value = _state.value.copy(customerSearchResults = emptyList())
            return
        }
        searchJob = viewModelScope.launch {
            delay(300)
            runCatching { customerApi.searchCustomers(query) }
                .onSuccess { resp ->
                    _state.value = _state.value.copy(
                        customerSearchResults = resp.data ?: emptyList(),
                        showCustomerDropdown = true,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(customerSearchResults = emptyList())
                }
        }
    }

    fun onCustomerSelected(customer: CustomerListItem) {
        _state.value = _state.value.copy(
            selectedCustomer = customer,
            customerSearchQuery = listOfNotNull(customer.firstName, customer.lastName)
                .joinToString(" ").ifBlank { customer.organization ?: "" },
            showCustomerDropdown = false,
            customerSearchResults = emptyList(),
        )
    }

    fun onDismissDropdown() {
        _state.value = _state.value.copy(showCustomerDropdown = false)
    }

    // ── Line items ────────────────────────────────────────────────────────────

    fun onLineDescriptionChanged(index: Int, value: String) {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems.mapIndexed { i, row ->
                if (i == index) row.copy(description = value) else row
            },
        )
    }

    fun onLineQtyChanged(index: Int, value: String) {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems.mapIndexed { i, row ->
                if (i == index) row.copy(qty = value) else row
            },
        )
    }

    fun onLineUnitPriceChanged(index: Int, value: String) {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems.mapIndexed { i, row ->
                if (i == index) row.copy(unitPrice = value) else row
            },
        )
    }

    fun addLineItem() {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems + LineItemRow(),
        )
    }

    fun removeLineItem(index: Int) {
        val updated = _state.value.lineItems.toMutableList().also { it.removeAt(index) }
        _state.value = _state.value.copy(lineItems = updated.ifEmpty { listOf(LineItemRow()) })
    }

    // ── Other fields ─────────────────────────────────────────────────────────

    fun onNotesChanged(value: String) {
        _state.value = _state.value.copy(notes = value)
    }

    fun onDueDateChanged(value: String) {
        _state.value = _state.value.copy(dueDate = value)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    // ── Submit ────────────────────────────────────────────────────────────────

    fun createInvoice() {
        val s = _state.value
        if (!s.isSubmittable()) return
        val customerId = s.selectedCustomer?.id ?: return

        val lineItemDtos = s.lineItems
            .filter { it.description.isNotBlank() }
            .map { row ->
                CreateLineItemDto(
                    name = row.description,
                    description = row.description,
                    quantity = row.qty.toIntOrNull() ?: 1,
                    unitPrice = row.unitPrice.toDoubleOrNull() ?: 0.0,
                )
            }

        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            runCatching {
                invoiceApi.createInvoice(
                    CreateInvoiceRequest(
                        customerId = customerId,
                        lineItems = lineItemDtos,
                        notes = s.notes.ifBlank { null },
                        dueDate = s.dueDate.ifBlank { null },
                    ),
                )
            }
                .onSuccess { resp ->
                    if (resp.success && resp.data != null) {
                        _state.value = _state.value.copy(
                            loading = false,
                            created = resp.data.invoice.id,
                        )
                    } else {
                        _state.value = _state.value.copy(
                            loading = false,
                            error = resp.message ?: "Failed to create invoice",
                        )
                    }
                }
                .onFailure { ex ->
                    _state.value = _state.value.copy(
                        loading = false,
                        error = ex.message ?: "Network error — please try again",
                    )
                }
        }
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvoiceCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: InvoiceCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate out once creation succeeds
    LaunchedEffect(state.created) {
        state.created?.let { id ->
            snackbarHostState.showSnackbar("Invoice created successfully")
            onCreated(id)
        }
    }

    // Show errors in snackbar
    LaunchedEffect(state.error) {
        state.error?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "New Invoice",
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics { contentDescription = "Navigate back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Customer picker ──────────────────────────────────────────────
            item {
                CustomerPickerSection(
                    query = state.customerSearchQuery,
                    results = state.customerSearchResults,
                    selectedCustomer = state.selectedCustomer,
                    showDropdown = state.showCustomerDropdown,
                    onQueryChanged = viewModel::onCustomerQueryChanged,
                    onCustomerSelected = viewModel::onCustomerSelected,
                    onDismiss = viewModel::onDismissDropdown,
                )
            }

            // ── Line items ───────────────────────────────────────────────────
            item {
                Text(
                    "Line Items",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            itemsIndexed(state.lineItems, key = { index, _ -> index }) { index, row ->
                LineItemRowCard(
                    row = row,
                    index = index,
                    canDelete = state.lineItems.size > 1,
                    onDescriptionChanged = { viewModel.onLineDescriptionChanged(index, it) },
                    onQtyChanged = { viewModel.onLineQtyChanged(index, it) },
                    onUnitPriceChanged = { viewModel.onLineUnitPriceChanged(index, it) },
                    onDelete = { viewModel.removeLineItem(index) },
                )
            }

            item {
                OutlinedButton(
                    onClick = viewModel::addLineItem,
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Add line item" },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("Add line")
                }
            }

            // ── Notes ────────────────────────────────────────────────────────
            item {
                OutlinedTextField(
                    value = state.notes,
                    onValueChange = viewModel::onNotesChanged,
                    label = { Text("Notes (optional)") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Invoice notes" },
                    minLines = 2,
                    maxLines = 5,
                )
            }

            // ── Due date ─────────────────────────────────────────────────────
            item {
                DueDateField(
                    dueDate = state.dueDate,
                    onDueDateChanged = viewModel::onDueDateChanged,
                )
            }

            // ── Totals ───────────────────────────────────────────────────────
            item {
                InvoiceTotalsFooter(subtotalCents = state.subtotalCents())
            }

            // ── Submit ───────────────────────────────────────────────────────
            item {
                Button(
                    onClick = viewModel::createInvoice,
                    enabled = state.isSubmittable() && !state.loading,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .semantics { contentDescription = "Create invoice" },
                ) {
                    if (state.loading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    } else {
                        Text("Create Invoice", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
    }
}

// ─── Customer Picker ─────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomerPickerSection(
    query: String,
    results: List<CustomerListItem>,
    selectedCustomer: CustomerListItem?,
    showDropdown: Boolean,
    onQueryChanged: (String) -> Unit,
    onCustomerSelected: (CustomerListItem) -> Unit,
    onDismiss: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            "Customer",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )

        ExposedDropdownMenuBox(
            expanded = showDropdown && results.isNotEmpty(),
            onExpandedChange = { if (!it) onDismiss() },
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChanged,
                label = { Text("Search customer") },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor()
                    .semantics { contentDescription = "Search for customer" },
                singleLine = true,
                isError = selectedCustomer == null && query.isNotBlank() && results.isEmpty(),
                supportingText = if (selectedCustomer != null) {
                    {
                        Text(
                            "Selected: ${selectedCustomer.email ?: selectedCustomer.phone ?: ""}",
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                } else null,
            )

            if (results.isNotEmpty()) {
                ExposedDropdownMenu(
                    expanded = showDropdown,
                    onDismissRequest = onDismiss,
                ) {
                    results.forEach { customer ->
                        val displayName = listOfNotNull(customer.firstName, customer.lastName)
                            .joinToString(" ").ifBlank { customer.organization ?: "Unknown" }
                        val subtitle = customer.email ?: customer.phone ?: ""
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(displayName, style = MaterialTheme.typography.bodyMedium)
                                    if (subtitle.isNotBlank()) {
                                        Text(
                                            subtitle,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            },
                            onClick = { onCustomerSelected(customer) },
                            modifier = Modifier.semantics {
                                contentDescription = "Select customer $displayName"
                            },
                        )
                    }
                }
            }
        }
    }
}

// ─── Line Item Row ────────────────────────────────────────────────────────────

@Composable
private fun LineItemRowCard(
    row: LineItemRow,
    index: Int,
    canDelete: Boolean,
    onDescriptionChanged: (String) -> Unit,
    onQtyChanged: (String) -> Unit,
    onUnitPriceChanged: (String) -> Unit,
    onDelete: () -> Unit,
) {
    val rowLabel = "Line item ${index + 1}"
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = rowLabel },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    rowLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (canDelete) {
                    IconButton(
                        onClick = onDelete,
                        modifier = Modifier.semantics {
                            contentDescription = "Remove $rowLabel"
                        },
                    ) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }

            OutlinedTextField(
                value = row.description,
                onValueChange = onDescriptionChanged,
                label = { Text("Description") },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Description for $rowLabel" },
                singleLine = true,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = row.qty,
                    onValueChange = onQtyChanged,
                    label = { Text("Qty") },
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Quantity for $rowLabel" },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    value = row.unitPrice,
                    onValueChange = onUnitPriceChanged,
                    label = { Text("Unit price") },
                    prefix = { Text("$") },
                    modifier = Modifier
                        .weight(2f)
                        .semantics { contentDescription = "Unit price for $rowLabel" },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
            }
        }
    }
}

// ─── Due Date Field ───────────────────────────────────────────────────────────

@Composable
private fun DueDateField(
    dueDate: String,
    onDueDateChanged: (String) -> Unit,
) {
    val context = LocalContext.current
    val calendar = remember { Calendar.getInstance() }

    OutlinedTextField(
        value = dueDate,
        onValueChange = {},
        label = { Text("Due date (optional)") },
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Select due date" },
        readOnly = true,
        trailingIcon = {
            IconButton(
                onClick = {
                    DatePickerDialog(
                        context,
                        { _, year, month, day ->
                            val m = (month + 1).toString().padStart(2, '0')
                            val d = day.toString().padStart(2, '0')
                            onDueDateChanged("$year-$m-$d")
                        },
                        calendar.get(Calendar.YEAR),
                        calendar.get(Calendar.MONTH),
                        calendar.get(Calendar.DAY_OF_MONTH),
                    ).show()
                },
                modifier = Modifier.semantics { contentDescription = "Open date picker" },
            ) {
                Icon(Icons.Default.CalendarMonth, contentDescription = null)
            }
        },
    )
}

// ─── Totals Footer ────────────────────────────────────────────────────────────

@Composable
private fun InvoiceTotalsFooter(subtotalCents: Long) {
    // Tax calc is deferred — wave 7 scope is 0 tax.
    val taxCents = 0L
    val totalCents = subtotalCents + taxCents

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "Invoice totals: subtotal ${subtotalCents.formatAsMoney()}, " +
                    "tax ${taxCents.formatAsMoney()}, total ${totalCents.formatAsMoney()}"
            },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            TotalsRow("Subtotal", subtotalCents.formatAsMoney())
            TotalsRow("Tax", taxCents.formatAsMoney())
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            TotalsRow(
                label = "Total",
                value = totalCents.formatAsMoney(),
                bold = true,
            )
        }
    }
}

@Composable
private fun TotalsRow(label: String, value: String, bold: Boolean = false) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = if (bold) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodySmall,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = if (bold) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodySmall,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
            color = if (bold) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
