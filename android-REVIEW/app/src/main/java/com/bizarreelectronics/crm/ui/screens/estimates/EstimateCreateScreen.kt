package com.bizarreelectronics.crm.ui.screens.estimates

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.EstimateApi
import com.bizarreelectronics.crm.data.remote.api.RepairPricingApi
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.CreateEstimateLineItem
import com.bizarreelectronics.crm.data.remote.dto.CreateEstimateRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.InventoryListItem
import com.bizarreelectronics.crm.data.remote.dto.RepairServiceItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.UUID
import javax.inject.Inject

// ─── Line item model ──────────────────────────────────────────────────────────

data class EstimateLineItemRow(
    val description: String = "",
    val qty: String = "1",
    val unitPrice: String = "",
    /** Set when sourced from inventory so server can link the item. */
    val inventoryItemId: Long? = null,
)

// ─── UiState ──────────────────────────────────────────────────────────────────

data class EstimateCreateUiState(
    // Customer picker
    val customerQuery: String = "",
    val customerResults: List<CustomerListItem> = emptyList(),
    val selectedCustomer: CustomerListItem? = null,
    val showCustomerDropdown: Boolean = false,

    // Line items
    val lineItems: List<EstimateLineItemRow> = listOf(EstimateLineItemRow()),

    // Validity
    /** "Valid for X days" numeric input.  */
    val validForDays: String = "30",
    /** Derived ISO date "yyyy-MM-dd" (from days field or date picker). */
    val validUntilDate: String = "",

    // Notes + prefill state
    val notes: String = "",
    /** Non-null when screen was opened with a leadId nav arg. */
    val prefillLeadId: Long? = null,
    val prefillLoading: Boolean = false,

    // Add-line bottom sheet
    val showAddLineSheet: Boolean = false,
    val addLineTab: Int = 0,           // 0=Service, 1=Part, 2=Free-form
    val serviceQuery: String = "",
    val serviceItems: List<RepairServiceItem> = emptyList(),
    val servicesLoading: Boolean = false,
    val partQuery: String = "",
    val partItems: List<InventoryListItem> = emptyList(),
    val partsLoading: Boolean = false,
    val freeFormDesc: String = "",
    val freeFormQty: String = "1",
    val freeFormPrice: String = "",

    // Submission
    val loading: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

private fun EstimateCreateUiState.subtotalCents(): Long =
    lineItems.sumOf { row ->
        val qty = row.qty.toLongOrNull() ?: 0L
        val cents = (row.unitPrice.toDoubleOrNull() ?: 0.0).let { d -> (d * 100).toLong() }
        qty * cents
    }

private fun EstimateCreateUiState.isSubmittable(): Boolean =
    selectedCustomer != null &&
        lineItems.any { it.description.isNotBlank() && (it.unitPrice.toDoubleOrNull() ?: 0.0) > 0 }

// ─── ViewModel ────────────────────────────────────────────────────────────────

@HiltViewModel
class EstimateCreateViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val estimateApi: EstimateApi,
    private val customerApi: CustomerApi,
    private val repairPricingApi: RepairPricingApi,
    private val inventoryApi: InventoryApi,
    private val leadApi: LeadApi,
) : ViewModel() {

    private val prefillLeadId: Long? =
        savedStateHandle.get<String>("leadId")?.toLongOrNull()?.takeIf { it > 0 }

    private val _state = MutableStateFlow(EstimateCreateUiState(prefillLeadId = prefillLeadId))
    val state = _state.asStateFlow()

    private var customerSearchJob: Job? = null
    private var serviceSearchJob: Job? = null
    private var partSearchJob: Job? = null

    /** Re-generated on each save attempt so retries get a fresh key. */
    private var idempotencyKey: String = UUID.randomUUID().toString()

    init {
        prefillLeadId?.let { prefillFromLead(it) }
    }

    // ── Lead prefill ─────────────────────���───────────────────────────────────

    private fun prefillFromLead(leadId: Long) {
        viewModelScope.launch {
            _state.value = _state.value.copy(prefillLoading = true)
            runCatching { leadApi.getLead(leadId) }
                .onSuccess { resp ->
                    val lead = resp.data ?: return@onSuccess
                    // Try to load the lead's customer if customerId is present
                    val customerId = lead.customerId
                    var prefillCustomer: CustomerListItem? = null
                    if (customerId != null) {
                        // Search by customer id via name — best-effort; 404-tolerant
                        val displayName = listOfNotNull(lead.firstName, lead.lastName).joinToString(" ")
                        if (displayName.isNotBlank()) {
                            runCatching { customerApi.searchCustomers(displayName) }
                                .onSuccess { cr ->
                                    prefillCustomer = cr.data?.firstOrNull { it.id == customerId }
                                        ?: cr.data?.firstOrNull()
                                }
                        }
                    }
                    val notesPrefill = lead.notes?.ifBlank { null }
                    // Prefill line items from lead's devices (each device/service becomes a row)
                    val deviceLines = lead.devices
                        ?.filter { it.repairType != null || it.deviceName != null }
                        ?.map { device ->
                            EstimateLineItemRow(
                                description = listOfNotNull(device.deviceName, device.repairType).joinToString(" - ").ifBlank { "Repair" },
                                qty = "1",
                                unitPrice = "%.2f".format(device.price ?: 0.0),
                            )
                        }
                        ?.takeIf { it.isNotEmpty() }
                    val valueLine = deviceLines ?: listOf(EstimateLineItemRow())

                    val leadName = listOfNotNull(lead.firstName, lead.lastName)
                        .joinToString(" ").ifBlank { null }
                    _state.value = _state.value.copy(
                        prefillLoading = false,
                        selectedCustomer = prefillCustomer,
                        customerQuery = prefillCustomer?.let {
                            listOfNotNull(it.firstName, it.lastName).joinToString(" ").ifBlank { it.organization ?: "" }
                        } ?: leadName ?: "",
                        notes = notesPrefill ?: "",
                        lineItems = valueLine,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(prefillLoading = false)
                }
        }
    }

    // ── Customer picker ──────────────────────────────────────────────────────

    fun onCustomerQueryChanged(query: String) {
        _state.value = _state.value.copy(
            customerQuery = query,
            selectedCustomer = null,
            showCustomerDropdown = query.isNotBlank(),
        )
        customerSearchJob?.cancel()
        if (query.isBlank()) {
            _state.value = _state.value.copy(customerResults = emptyList())
            return
        }
        customerSearchJob = viewModelScope.launch {
            delay(300)
            runCatching { customerApi.searchCustomers(query) }
                .onSuccess { resp ->
                    _state.value = _state.value.copy(
                        customerResults = resp.data ?: emptyList(),
                        showCustomerDropdown = true,
                    )
                }
                .onFailure { _state.value = _state.value.copy(customerResults = emptyList()) }
        }
    }

    fun onCustomerSelected(customer: CustomerListItem) {
        _state.value = _state.value.copy(
            selectedCustomer = customer,
            customerQuery = listOfNotNull(customer.firstName, customer.lastName)
                .joinToString(" ").ifBlank { customer.organization ?: "" },
            showCustomerDropdown = false,
            customerResults = emptyList(),
        )
    }

    fun onDismissCustomerDropdown() {
        _state.value = _state.value.copy(showCustomerDropdown = false)
    }

    // ── Validity window ──────────────────────────────────────────────────────

    fun onValidForDaysChanged(days: String) {
        val daysInt = days.toIntOrNull()
        val isoDate = if (daysInt != null && daysInt > 0) {
            val cal = Calendar.getInstance()
            cal.add(Calendar.DAY_OF_YEAR, daysInt)
            val y = cal.get(Calendar.YEAR)
            val m = (cal.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
            val d = cal.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
            "$y-$m-$d"
        } else ""
        _state.value = _state.value.copy(validForDays = days, validUntilDate = isoDate)
    }

    fun onValidUntilDatePicked(isoDate: String) {
        _state.value = _state.value.copy(validUntilDate = isoDate, validForDays = "")
    }

    // ── Line items ───────────────────────────────────────────────────────────

    fun onLineDescChanged(index: Int, value: String) {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems.mapIndexed { i, r ->
                if (i == index) r.copy(description = value) else r
            },
        )
    }

    fun onLineQtyChanged(index: Int, value: String) {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems.mapIndexed { i, r ->
                if (i == index) r.copy(qty = value) else r
            },
        )
    }

    fun onLinePriceChanged(index: Int, value: String) {
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems.mapIndexed { i, r ->
                if (i == index) r.copy(unitPrice = value) else r
            },
        )
    }

    fun removeLineItem(index: Int) {
        val updated = _state.value.lineItems.toMutableList().also { it.removeAt(index) }
        _state.value = _state.value.copy(lineItems = updated.ifEmpty { listOf(EstimateLineItemRow()) })
    }

    fun addLineItem() {
        _state.value = _state.value.copy(lineItems = _state.value.lineItems + EstimateLineItemRow())
    }

    // ── Notes ────────────────────────────────────────────────────────────────

    fun onNotesChanged(value: String) {
        _state.value = _state.value.copy(notes = value)
    }

    // ── Add-line bottom sheet ─────────────────────────────────────────────────

    fun openAddLineSheet() {
        _state.value = _state.value.copy(showAddLineSheet = true, addLineTab = 0)
        loadServices()
    }

    fun closeAddLineSheet() {
        _state.value = _state.value.copy(showAddLineSheet = false)
    }

    fun onAddLineTabChanged(tab: Int) {
        _state.value = _state.value.copy(addLineTab = tab)
        when (tab) {
            0 -> if (_state.value.serviceItems.isEmpty()) loadServices()
            1 -> if (_state.value.partItems.isEmpty()) loadParts(_state.value.partQuery)
        }
    }

    private fun loadServices(query: String? = null) {
        serviceSearchJob?.cancel()
        serviceSearchJob = viewModelScope.launch {
            _state.value = _state.value.copy(servicesLoading = true)
            runCatching { repairPricingApi.getServices(query = query) }
                .onSuccess { resp ->
                    val items = resp.data ?: DEFAULT_SERVICES
                    _state.value = _state.value.copy(serviceItems = items, servicesLoading = false)
                }
                .onFailure {
                    // 404 or network: fall back to hardcoded defaults
                    _state.value = _state.value.copy(serviceItems = DEFAULT_SERVICES, servicesLoading = false)
                }
        }
    }

    fun onServiceQueryChanged(q: String) {
        _state.value = _state.value.copy(serviceQuery = q)
        serviceSearchJob?.cancel()
        serviceSearchJob = viewModelScope.launch {
            delay(300)
            loadServices(q.ifBlank { null })
        }
    }

    fun onPartQueryChanged(q: String) {
        _state.value = _state.value.copy(partQuery = q)
        loadParts(q)
    }

    private fun loadParts(query: String) {
        partSearchJob?.cancel()
        partSearchJob = viewModelScope.launch {
            if (query.isBlank()) {
                _state.value = _state.value.copy(partItems = emptyList())
                return@launch
            }
            delay(300)
            _state.value = _state.value.copy(partsLoading = true)
            runCatching { inventoryApi.getItems(mapOf("search" to query, "pagesize" to "20")) }
                .onSuccess { resp ->
                    _state.value = _state.value.copy(
                        partItems = resp.data?.items ?: emptyList(),
                        partsLoading = false,
                    )
                }
                .onFailure { _state.value = _state.value.copy(partsLoading = false) }
        }
    }

    fun onFreeFormDescChanged(v: String) { _state.value = _state.value.copy(freeFormDesc = v) }
    fun onFreeFormQtyChanged(v: String) { _state.value = _state.value.copy(freeFormQty = v) }
    fun onFreeFormPriceChanged(v: String) { _state.value = _state.value.copy(freeFormPrice = v) }

    fun addServiceLine(service: RepairServiceItem, price: Double) {
        val row = EstimateLineItemRow(
            description = service.name,
            qty = "1",
            unitPrice = "%.2f".format(price),
        )
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems + row,
            showAddLineSheet = false,
        )
    }

    fun addPartLine(part: InventoryListItem) {
        val row = EstimateLineItemRow(
            description = part.name ?: "Part",
            qty = "1",
            unitPrice = "%.2f".format(part.price ?: 0.0),
            inventoryItemId = part.id,
        )
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems + row,
            showAddLineSheet = false,
        )
    }

    fun addFreeFormLine() {
        val desc = _state.value.freeFormDesc.trim()
        if (desc.isBlank()) return
        val row = EstimateLineItemRow(
            description = desc,
            qty = _state.value.freeFormQty.ifBlank { "1" },
            unitPrice = _state.value.freeFormPrice,
        )
        _state.value = _state.value.copy(
            lineItems = _state.value.lineItems + row,
            showAddLineSheet = false,
            freeFormDesc = "",
            freeFormQty = "1",
            freeFormPrice = "",
        )
    }

    // ── Submit ───────────────────────────────────────────────────────────────

    fun createEstimate() {
        val s = _state.value
        if (!s.isSubmittable()) return
        val customerId = s.selectedCustomer?.id ?: return

        // New idempotency key per attempt
        idempotencyKey = UUID.randomUUID().toString()

        val dtos = s.lineItems.filter { it.description.isNotBlank() }.map { row ->
            CreateEstimateLineItem(
                description = row.description,
                quantity = row.qty.toIntOrNull() ?: 1,
                unitPrice = row.unitPrice.toDoubleOrNull() ?: 0.0,
                inventoryItemId = row.inventoryItemId,
            )
        }

        val validUntil = s.validUntilDate.ifBlank { null }

        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            runCatching {
                estimateApi.createEstimate(
                    idempotencyKey = idempotencyKey,
                    request = CreateEstimateRequest(
                        customerId = customerId,
                        notes = s.notes.ifBlank { null },
                        validUntil = validUntil,
                        lineItems = dtos,
                        idempotencyKey = idempotencyKey,
                    ),
                )
            }
                .onSuccess { resp ->
                    if (resp.success && resp.data != null) {
                        _state.value = _state.value.copy(loading = false, createdId = resp.data.id)
                    } else {
                        _state.value = _state.value.copy(
                            loading = false,
                            error = resp.message ?: "Failed to create estimate",
                        )
                    }
                }
                .onFailure { ex ->
                    _state.value = _state.value.copy(
                        loading = false,
                        error = ex.message ?: "Network error - please try again",
                    )
                }
        }
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    // ── Defaults ───────────────────────────────���───────────────────────���─────

    companion object {
        /** Fallback services shown when the server's repair-pricing endpoint returns 404. */
        private val DEFAULT_SERVICES = listOf(
            RepairServiceItem(id = -1, name = "Screen Replacement", slug = "screen", category = "Display", isActive = 1, sortOrder = 0),
            RepairServiceItem(id = -2, name = "Battery Replacement", slug = "battery", category = "Power", isActive = 1, sortOrder = 1),
            RepairServiceItem(id = -3, name = "Charging Port Repair", slug = "charging-port", category = "Power", isActive = 1, sortOrder = 2),
            RepairServiceItem(id = -4, name = "Speaker Repair", slug = "speaker", category = "Audio", isActive = 1, sortOrder = 3),
            RepairServiceItem(id = -5, name = "Diagnostic Fee", slug = "diagnostic", category = "Diagnostic", isActive = 1, sortOrder = 4),
        )
    }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EstimateCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: EstimateCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    LaunchedEffect(state.createdId) {
        state.createdId?.let { id ->
            snackbarHostState.showSnackbar("Estimate created")
            onCreated(id)
        }
    }

    LaunchedEffect(state.error) {
        state.error?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    if (state.showAddLineSheet) {
        AddLineSheet(
            sheetState = sheetState,
            state = state,
            viewModel = viewModel,
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = if (state.prefillLeadId != null) "Estimate from Lead" else "New Estimate",
                navigationIcon = {
                    IconButton(onClick = onBack, modifier = Modifier.semantics { contentDescription = "Navigate back" }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        if (state.prefillLoading) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).imePadding(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Customer picker ──────────────────────────────────────────────
            item { CustomerPickerSection(state, viewModel) }

            // ── Line items header ──────────────────────────────────���─────────
            item {
                Text("Line Items", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            }

            // ── Line item rows ──────────────────────────────────���────────────
            itemsIndexed(state.lineItems, key = { i, _ -> i }) { index, row ->
                EstimateLineItemRowCard(
                    row = row,
                    index = index,
                    canDelete = state.lineItems.size > 1,
                    onDescChanged = { viewModel.onLineDescChanged(index, it) },
                    onQtyChanged = { viewModel.onLineQtyChanged(index, it) },
                    onPriceChanged = { viewModel.onLinePriceChanged(index, it) },
                    onDelete = { viewModel.removeLineItem(index) },
                )
            }

            // ── Add line button ──────────────────────────────────────────────
            item {
                OutlinedButton(
                    onClick = viewModel::openAddLineSheet,
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Add line item" },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("+ Add line")
                }
            }

            // ── Notes ──────────────────────────────────��─────────────────────
            item {
                OutlinedTextField(
                    value = state.notes,
                    onValueChange = viewModel::onNotesChanged,
                    label = { Text("Notes (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 5,
                )
            }

            // ── Validity window ──────────────────────────────────────────────
            item { ValidityWindowField(state, viewModel) }

            // ── Totals ───────────────────────────────────────────────────────
            item { EstimateTotalsFooter(subtotalCents = state.subtotalCents()) }

            // ── Submit ───────────────────────────────────────────────────────
            item {
                Button(
                    onClick = viewModel::createEstimate,
                    enabled = state.isSubmittable() && !state.loading,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                ) {
                    if (state.loading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    } else {
                        Text("Create Estimate", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
    }
}

// ─── Customer Picker ─────────────────────────���──────────────────────────���────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomerPickerSection(
    state: EstimateCreateUiState,
    viewModel: EstimateCreateViewModel,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("Customer", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        ExposedDropdownMenuBox(
            expanded = state.showCustomerDropdown && state.customerResults.isNotEmpty(),
            onExpandedChange = { if (!it) viewModel.onDismissCustomerDropdown() },
        ) {
            OutlinedTextField(
                value = state.customerQuery,
                onValueChange = viewModel::onCustomerQueryChanged,
                label = { Text("Search customer") },
                modifier = Modifier.fillMaxWidth().menuAnchor(),
                singleLine = true,
                isError = state.selectedCustomer == null && state.customerQuery.isNotBlank() && state.customerResults.isEmpty(),
                supportingText = if (state.selectedCustomer != null) {
                    { Text("Selected: ${state.selectedCustomer.email ?: state.selectedCustomer.phone ?: ""}", color = MaterialTheme.colorScheme.primary) }
                } else null,
            )
            if (state.customerResults.isNotEmpty()) {
                ExposedDropdownMenu(expanded = state.showCustomerDropdown, onDismissRequest = viewModel::onDismissCustomerDropdown) {
                    state.customerResults.forEach { customer ->
                        val displayName = listOfNotNull(customer.firstName, customer.lastName).joinToString(" ").ifBlank { customer.organization ?: "Unknown" }
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(displayName, style = MaterialTheme.typography.bodyMedium)
                                    val sub = customer.email ?: customer.phone ?: ""
                                    if (sub.isNotBlank()) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            },
                            onClick = { viewModel.onCustomerSelected(customer) },
                        )
                    }
                }
            }
        }
    }
}

// ─── Line Item Row Card ───────────────────────────────────────────────────────

@Composable
private fun EstimateLineItemRowCard(
    row: EstimateLineItemRow,
    index: Int,
    canDelete: Boolean,
    onDescChanged: (String) -> Unit,
    onQtyChanged: (String) -> Unit,
    onPriceChanged: (String) -> Unit,
    onDelete: () -> Unit,
) {
    val rowLabel = "Line item ${index + 1}"
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(rowLabel, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                if (canDelete) {
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Default.Delete, contentDescription = "Remove $rowLabel", tint = MaterialTheme.colorScheme.error)
                    }
                }
            }
            OutlinedTextField(value = row.description, onValueChange = onDescChanged, label = { Text("Description") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = row.qty, onValueChange = onQtyChanged, label = { Text("Qty") }, modifier = Modifier.weight(1f), singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                OutlinedTextField(value = row.unitPrice, onValueChange = onPriceChanged, label = { Text("Unit price") }, prefix = { Text("$") }, modifier = Modifier.weight(2f), singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            }
        }
    }
}

// ─── Validity Window ──────────────────────────────────────────────────────────

@Composable
private fun ValidityWindowField(
    state: EstimateCreateUiState,
    viewModel: EstimateCreateViewModel,
) {
    val context = LocalContext.current
    val calendar = remember { Calendar.getInstance() }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Validity Window", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = state.validForDays,
                onValueChange = viewModel::onValidForDaysChanged,
                label = { Text("Valid for days") },
                modifier = Modifier.weight(1f),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                supportingText = if (state.validUntilDate.isNotBlank()) {
                    { Text("Until ${state.validUntilDate}") }
                } else null,
            )
            OutlinedButton(
                onClick = {
                    DatePickerDialog(
                        context,
                        { _, year, month, day ->
                            val m = (month + 1).toString().padStart(2, '0')
                            val d = day.toString().padStart(2, '0')
                            viewModel.onValidUntilDatePicked("$year-$m-$d")
                        },
                        calendar.get(Calendar.YEAR),
                        calendar.get(Calendar.MONTH),
                        calendar.get(Calendar.DAY_OF_MONTH),
                    ).show()
                },
            ) {
                Icon(Icons.Default.CalendarMonth, contentDescription = "Pick date", modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("Pick date")
            }
        }
    }
}

// ─── Totals Footer ────────────────────────────────────────────────────────────

@Composable
private fun EstimateTotalsFooter(subtotalCents: Long) {
    val taxCents = 0L
    val totalCents = subtotalCents + taxCents
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            EstimateTotalsRow("Subtotal", subtotalCents.formatAsMoney())
            EstimateTotalsRow("Tax (TBD)", taxCents.formatAsMoney())
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            EstimateTotalsRow("Total", totalCents.formatAsMoney(), bold = true)
        }
    }
}

@Composable
private fun EstimateTotalsRow(label: String, value: String, bold: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = if (bold) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodySmall, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = if (bold) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodySmall, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal, color = if (bold) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// ─── Add Line Bottom Sheet ────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddLineSheet(
    sheetState: SheetState,
    state: EstimateCreateUiState,
    viewModel: EstimateCreateViewModel,
) {
    ModalBottomSheet(
        onDismissRequest = viewModel::closeAddLineSheet,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Add Line Item", style = MaterialTheme.typography.titleMedium)

            val tabs = listOf("Service", "Part", "Free-form")
            TabRow(selectedTabIndex = state.addLineTab) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = state.addLineTab == index,
                        onClick = { viewModel.onAddLineTabChanged(index) },
                        text = { Text(title) },
                    )
                }
            }

            when (state.addLineTab) {
                0 -> ServiceTab(state, viewModel)
                1 -> PartTab(state, viewModel)
                2 -> FreeFormTab(state, viewModel)
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun ServiceTab(state: EstimateCreateUiState, viewModel: EstimateCreateViewModel) {
    var priceOverrides by rememberSaveable { mutableStateOf(mapOf<Long, String>()) }
    OutlinedTextField(
        value = state.serviceQuery,
        onValueChange = viewModel::onServiceQueryChanged,
        label = { Text("Search services") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
    )
    if (state.servicesLoading) {
        Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(modifier = Modifier.size(24.dp)) }
    } else {
        state.serviceItems.forEach { service ->
            val priceText = priceOverrides[service.id] ?: ""
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(service.name, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                OutlinedTextField(
                    value = priceText,
                    onValueChange = { priceOverrides = priceOverrides + (service.id to it) },
                    label = { Text("$") },
                    modifier = Modifier.width(80.dp),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
                IconButton(onClick = {
                    val price = priceText.toDoubleOrNull() ?: 0.0
                    viewModel.addServiceLine(service, price)
                }) {
                    Icon(Icons.Default.Add, contentDescription = "Add ${service.name}", tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun PartTab(state: EstimateCreateUiState, viewModel: EstimateCreateViewModel) {
    OutlinedTextField(
        value = state.partQuery,
        onValueChange = viewModel::onPartQueryChanged,
        label = { Text("Search parts") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
    )
    if (state.partsLoading) {
        Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(modifier = Modifier.size(24.dp)) }
    } else {
        state.partItems.forEach { part ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(part.name ?: "Part", style = MaterialTheme.typography.bodyMedium)
                    Text("$%.2f | Stock: ${part.inStock ?: 0}".format(part.price ?: 0.0), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = { viewModel.addPartLine(part) }) {
                    Icon(Icons.Default.Add, contentDescription = "Add ${part.name}", tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
        if (state.partQuery.isNotBlank() && state.partItems.isEmpty() && !state.partsLoading) {
            Text("No parts found", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun FreeFormTab(state: EstimateCreateUiState, viewModel: EstimateCreateViewModel) {
    OutlinedTextField(value = state.freeFormDesc, onValueChange = viewModel::onFreeFormDescChanged, label = { Text("Description") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(value = state.freeFormQty, onValueChange = viewModel::onFreeFormQtyChanged, label = { Text("Qty") }, modifier = Modifier.weight(1f), singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        OutlinedTextField(value = state.freeFormPrice, onValueChange = viewModel::onFreeFormPriceChanged, label = { Text("Price") }, prefix = { Text("$") }, modifier = Modifier.weight(2f), singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
    }
    Button(
        onClick = viewModel::addFreeFormLine,
        enabled = state.freeFormDesc.isNotBlank(),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Add")
    }
}
