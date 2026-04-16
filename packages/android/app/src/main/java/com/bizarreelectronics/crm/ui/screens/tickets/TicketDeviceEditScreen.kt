package com.bizarreelectronics.crm.ui.screens.tickets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.AddTicketPartRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketDevicePart
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketDeviceRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ===========================================================================================
// State
// ===========================================================================================

/** Editable in-memory snapshot of a TicketDevicePart (client-only, used before save). */
data class EditablePart(
    /** Server ID (> 0) for existing parts, negative temp ID for locally added parts. */
    val id: Long,
    val inventoryItemId: Long?,
    val name: String,
    val sku: String?,
    val quantity: Int,
    val price: Double,
    /** True when this part already exists on the server and was loaded from the API. */
    val existsOnServer: Boolean,
)

data class TicketDeviceEditUiState(
    val ticketId: Long = 0,
    val deviceId: Long = 0,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val actionMessage: String? = null,

    // Editable form fields
    val deviceName: String = "",
    val imei: String = "",
    val serial: String = "",
    val color: String = "",
    val securityCode: String = "",
    val customerComments: String = "",
    val staffComments: String = "",

    val parts: List<EditablePart> = emptyList(),

    // Inventory search dialog
    val showPartSearchDialog: Boolean = false,
    val partSearchQuery: String = "",
    val partSearchResults: List<InventoryListItem> = emptyList(),
    val isSearchingInventory: Boolean = false,

    /** Signals the screen to pop back once a successful save has completed. */
    val saveComplete: Boolean = false,
)

// ===========================================================================================
// ViewModel
// ===========================================================================================

@HiltViewModel
class TicketDeviceEditViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val ticketApi: TicketApi,
    private val inventoryApi: InventoryApi,
    private val serverMonitor: ServerReachabilityMonitor,
    private val syncQueueDao: SyncQueueDao,
    private val gson: Gson,
) : ViewModel() {

    private val ticketId: Long = savedStateHandle.get<String>("ticketId")?.toLongOrNull() ?: 0L
    private val deviceId: Long = savedStateHandle.get<String>("deviceId")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(
        TicketDeviceEditUiState(ticketId = ticketId, deviceId = deviceId),
    )
    val state = _state.asStateFlow()

    private var searchJob: Job? = null

    init {
        loadDevice()
    }

    /**
     * Load the device from the server by fetching the full ticket and extracting the matching
     * device. Falls back gracefully if offline by leaving fields blank for the user to populate.
     */
    private fun loadDevice() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val response = ticketApi.getTicket(ticketId)
                val device = response.data?.devices?.firstOrNull { it.id == deviceId }
                if (device == null) {
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = "Device not found on ticket",
                        )
                    }
                    return@launch
                }
                populateFromDevice(device)
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load device",
                    )
                }
            }
        }
    }

    private fun populateFromDevice(device: TicketDevice) {
        val parts = (device.parts ?: emptyList()).map { p -> p.toEditable() }
        _state.update {
            it.copy(
                isLoading = false,
                deviceName = device.deviceName ?: device.name ?: "",
                imei = device.imei.orEmpty(),
                serial = device.serial.orEmpty(),
                color = device.color.orEmpty(),
                securityCode = device.securityCode.orEmpty(),
                customerComments = device.customerComments.orEmpty(),
                staffComments = device.staffComments.orEmpty(),
                parts = parts,
            )
        }
    }

    // ─── Field updates ───

    fun updateDeviceName(value: String) = _state.update { it.copy(deviceName = value) }
    fun updateImei(value: String) = _state.update { it.copy(imei = value) }
    fun updateSerial(value: String) = _state.update { it.copy(serial = value) }
    fun updateColor(value: String) = _state.update { it.copy(color = value) }
    fun updateSecurityCode(value: String) = _state.update { it.copy(securityCode = value) }
    fun updateCustomerComments(value: String) = _state.update { it.copy(customerComments = value) }
    fun updateStaffComments(value: String) = _state.update { it.copy(staffComments = value) }

    // ─── Part management ───

    fun openPartSearch() {
        _state.update {
            it.copy(
                showPartSearchDialog = true,
                partSearchQuery = "",
                partSearchResults = emptyList(),
            )
        }
    }

    fun closePartSearch() {
        _state.update { it.copy(showPartSearchDialog = false) }
        searchJob?.cancel()
    }

    fun updatePartSearchQuery(query: String) {
        _state.update { it.copy(partSearchQuery = query) }
        searchJob?.cancel()
        if (query.length < 2) {
            _state.update { it.copy(partSearchResults = emptyList(), isSearchingInventory = false) }
            return
        }
        searchJob = viewModelScope.launch {
            delay(SEARCH_DEBOUNCE_MS)
            _state.update { it.copy(isSearchingInventory = true) }
            try {
                val response = inventoryApi.getItems(
                    mapOf("keyword" to query, "pagesize" to "20"),
                )
                val results = response.data?.items ?: emptyList()
                _state.update {
                    it.copy(
                        partSearchResults = results,
                        isSearchingInventory = false,
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        partSearchResults = emptyList(),
                        isSearchingInventory = false,
                        actionMessage = "Search failed: ${e.message ?: "unknown"}",
                    )
                }
            }
        }
    }

    fun addPartFromInventory(item: InventoryListItem) {
        val current = _state.value.parts
        // Use a negative temp ID so we can distinguish from server IDs and safely remove later.
        val tempId = -((System.currentTimeMillis() % Int.MAX_VALUE) + current.size + 1)
        val newPart = EditablePart(
            id = tempId,
            inventoryItemId = item.id,
            name = item.name ?: "Unknown part",
            sku = item.sku,
            quantity = 1,
            price = item.price ?: 0.0,
            existsOnServer = false,
        )
        _state.update {
            it.copy(
                parts = current + newPart,
                showPartSearchDialog = false,
                partSearchQuery = "",
                partSearchResults = emptyList(),
            )
        }
    }

    fun incrementPartQuantity(partId: Long) {
        _state.update {
            it.copy(
                parts = it.parts.map { p ->
                    if (p.id == partId) p.copy(quantity = p.quantity + 1) else p
                },
            )
        }
    }

    fun decrementPartQuantity(partId: Long) {
        _state.update {
            it.copy(
                parts = it.parts.map { p ->
                    if (p.id == partId && p.quantity > 1) p.copy(quantity = p.quantity - 1) else p
                },
            )
        }
    }

    /**
     * Remove a part from the editable list. If the part already exists on the server, the
     * deletion is persisted when Save is pressed. For locally-added parts we just drop them.
     */
    fun removePart(partId: Long) {
        _state.update {
            it.copy(parts = it.parts.filterNot { p -> p.id == partId })
        }
    }

    /**
     * Save all edits: device fields, newly-added parts, and removed parts (server-side ones).
     * Online: calls APIs sequentially. Offline: queues operations to SyncQueue.
     */
    fun save() {
        val current = _state.value
        if (current.isSaving) return
        val trimmedName = current.deviceName.trim()
        if (trimmedName.isEmpty()) {
            _state.update { it.copy(actionMessage = "Device name is required") }
            return
        }

        viewModelScope.launch {
            _state.update { it.copy(isSaving = true, actionMessage = null) }

            // Re-load the device to determine which parts were removed server-side. We use the
            // initial snapshot held in state: any part with existsOnServer=true missing from the
            // current list needs to be deleted on the server.
            val originalServerParts = try {
                val response = ticketApi.getTicket(ticketId)
                response.data?.devices?.firstOrNull { it.id == current.deviceId }?.parts ?: emptyList()
            } catch (_: Exception) {
                // When offline we can't compute removals accurately; just use what we have.
                current.parts.filter { it.existsOnServer }.map { it.toDtoSnapshot() }
            }

            val currentServerPartIds = current.parts.filter { it.existsOnServer }.map { it.id }.toSet()
            val removedPartIds = originalServerParts
                .map { it.id }
                .filter { it !in currentServerPartIds }

            val newParts = current.parts.filterNot { it.existsOnServer }

            val updateRequest = UpdateTicketDeviceRequest(
                deviceName = trimmedName,
                imei = current.imei.trim().ifBlank { null },
                serial = current.serial.trim().ifBlank { null },
                color = current.color.trim().ifBlank { null },
                securityCode = current.securityCode.trim().ifBlank { null },
                customerComments = current.customerComments.trim().ifBlank { null },
                staffComments = current.staffComments.trim().ifBlank { null },
            )

            val isOnline = serverMonitor.isEffectivelyOnline.value
            if (isOnline) {
                saveOnline(updateRequest, newParts, removedPartIds)
            } else {
                saveOffline(updateRequest, newParts, removedPartIds)
            }
        }
    }

    private suspend fun saveOnline(
        updateRequest: UpdateTicketDeviceRequest,
        newParts: List<EditablePart>,
        removedPartIds: List<Long>,
    ) {
        try {
            val deviceId = _state.value.deviceId

            // 1. Update device fields.
            ticketApi.updateDevice(deviceId, updateRequest)

            // 2. Remove parts that were deleted in the editor.
            for (partId in removedPartIds) {
                runCatching { ticketApi.removePartFromDevice(partId) }
                    .onFailure { e ->
                        android.util.Log.w(TAG, "Failed to remove part $partId: ${e.message}")
                    }
            }

            // 3. Add any new parts that were added in the editor.
            for (part in newParts) {
                val inventoryItemId = part.inventoryItemId ?: continue
                val request = AddTicketPartRequest(
                    inventoryItemId = inventoryItemId,
                    quantity = part.quantity,
                    price = part.price,
                )
                runCatching { ticketApi.addPartToDevice(deviceId, request) }
                    .onFailure { e ->
                        android.util.Log.w(TAG, "Failed to add part ${part.name}: ${e.message}")
                    }
            }

            _state.update {
                it.copy(
                    isSaving = false,
                    actionMessage = "Device updated",
                    saveComplete = true,
                )
            }
        } catch (e: Exception) {
            _state.update {
                it.copy(
                    isSaving = false,
                    actionMessage = "Save failed: ${e.message ?: "unknown"}",
                )
            }
        }
    }

    private suspend fun saveOffline(
        updateRequest: UpdateTicketDeviceRequest,
        newParts: List<EditablePart>,
        removedPartIds: List<Long>,
    ) {
        val deviceId = _state.value.deviceId

        // Queue device update.
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "ticket_device",
                entityId = deviceId,
                operation = "update",
                payload = gson.toJson(updateRequest),
            ),
        )

        // Queue each added part.
        for (part in newParts) {
            val inventoryItemId = part.inventoryItemId ?: continue
            val request = AddTicketPartRequest(
                inventoryItemId = inventoryItemId,
                quantity = part.quantity,
                price = part.price,
            )
            syncQueueDao.insert(
                SyncQueueEntity(
                    entityType = "ticket_device",
                    entityId = deviceId,
                    operation = "add_part",
                    payload = gson.toJson(request),
                ),
            )
        }

        // Queue removals.
        for (partId in removedPartIds) {
            syncQueueDao.insert(
                SyncQueueEntity(
                    entityType = "ticket_device",
                    entityId = partId,
                    operation = "remove_part",
                    payload = gson.toJson(mapOf("partId" to partId)),
                ),
            )
        }

        _state.update {
            it.copy(
                isSaving = false,
                actionMessage = "Queued — will sync when online",
                saveComplete = true,
            )
        }
    }

    fun clearActionMessage() {
        _state.update { it.copy(actionMessage = null) }
    }

    companion object {
        private const val TAG = "TicketDeviceEdit"
        private const val SEARCH_DEBOUNCE_MS = 300L
    }
}

// ─── DTO ↔ Editable mappers ───

private fun TicketDevicePart.toEditable(): EditablePart = EditablePart(
    id = id,
    inventoryItemId = inventoryItemId,
    name = name ?: "Part",
    sku = sku,
    quantity = quantity ?: 1,
    price = price ?: 0.0,
    existsOnServer = true,
)

/** Used only for the offline fallback during save to avoid crashing when we can't refetch. */
private fun EditablePart.toDtoSnapshot(): TicketDevicePart = TicketDevicePart(
    id = id,
    ticketDeviceId = 0,
    inventoryItemId = inventoryItemId,
    name = name,
    sku = sku,
    quantity = quantity,
    price = price,
    total = quantity * price,
    status = null,
    catalogItemId = null,
    supplierUrl = null,
)

// ===========================================================================================
// Composable
// ===========================================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketDeviceEditScreen(
    ticketId: Long,
    deviceId: Long,
    onBack: () -> Unit,
    viewModel: TicketDeviceEditViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearActionMessage()
        }
    }

    LaunchedEffect(state.saveComplete) {
        if (state.saveComplete) {
            onBack()
        }
    }

    if (state.showPartSearchDialog) {
        PartSearchDialog(
            query = state.partSearchQuery,
            results = state.partSearchResults,
            isSearching = state.isSearchingInventory,
            onQueryChange = { viewModel.updatePartSearchQuery(it) },
            onPartSelected = { viewModel.addPartFromInventory(it) },
            onDismiss = { viewModel.closePartSearch() },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Edit device",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.save() },
                        enabled = !state.isSaving && !state.isLoading,
                    ) {
                        if (state.isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        } else {
                            Icon(
                                Icons.Default.Check,
                                contentDescription = "Save",
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier.padding(padding).padding(top = 8.dp),
                )
            }
            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            state.error ?: "Error",
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
            else -> {
                DeviceEditContent(
                    state = state,
                    padding = padding,
                    onDeviceNameChange = viewModel::updateDeviceName,
                    onImeiChange = viewModel::updateImei,
                    onSerialChange = viewModel::updateSerial,
                    onColorChange = viewModel::updateColor,
                    onSecurityCodeChange = viewModel::updateSecurityCode,
                    onCustomerCommentsChange = viewModel::updateCustomerComments,
                    onStaffCommentsChange = viewModel::updateStaffComments,
                    onAddPartClick = viewModel::openPartSearch,
                    onIncrementPart = viewModel::incrementPartQuantity,
                    onDecrementPart = viewModel::decrementPartQuantity,
                    onRemovePart = viewModel::removePart,
                )
            }
        }
    }
}

@Composable
private fun DeviceEditContent(
    state: TicketDeviceEditUiState,
    padding: PaddingValues,
    onDeviceNameChange: (String) -> Unit,
    onImeiChange: (String) -> Unit,
    onSerialChange: (String) -> Unit,
    onColorChange: (String) -> Unit,
    onSecurityCodeChange: (String) -> Unit,
    onCustomerCommentsChange: (String) -> Unit,
    onStaffCommentsChange: (String) -> Unit,
    onAddPartClick: () -> Unit,
    onIncrementPart: (Long) -> Unit,
    onDecrementPart: (Long) -> Unit,
    onRemovePart: (Long) -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            SectionHeader("Device Info")
        }
        item {
            OutlinedTextField(
                value = state.deviceName,
                onValueChange = onDeviceNameChange,
                label = { Text("Device name *") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            OutlinedTextField(
                value = state.imei,
                onValueChange = onImeiChange,
                label = { Text("IMEI") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            OutlinedTextField(
                value = state.serial,
                onValueChange = onSerialChange,
                label = { Text("Serial") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            OutlinedTextField(
                value = state.color,
                onValueChange = onColorChange,
                label = { Text("Color") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            OutlinedTextField(
                value = state.securityCode,
                onValueChange = onSecurityCodeChange,
                label = { Text("Security code / passcode") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            SectionHeader("Comments")
        }
        item {
            OutlinedTextField(
                value = state.customerComments,
                onValueChange = onCustomerCommentsChange,
                label = { Text("Customer comments") },
                minLines = 2,
                maxLines = 5,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            OutlinedTextField(
                value = state.staffComments,
                onValueChange = onStaffCommentsChange,
                label = { Text("Staff comments") },
                minLines = 2,
                maxLines = 5,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Parts",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                FilledTonalButton(onClick = onAddPartClick) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Add Part")
                }
            }
        }

        if (state.parts.isEmpty()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "No parts yet. Tap \"Add Part\" to search inventory.",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(state.parts, key = { it.id }) { part ->
                PartRow(
                    part = part,
                    onIncrement = { onIncrementPart(part.id) },
                    onDecrement = { onDecrementPart(part.id) },
                    onRemove = { onRemovePart(part.id) },
                )
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

@Composable
private fun PartRow(
    part: EditablePart,
    onIncrement: () -> Unit,
    onDecrement: () -> Unit,
    onRemove: () -> Unit,
) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    part.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                if (!part.sku.isNullOrBlank()) {
                    Text(
                        "SKU: ${part.sku}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    "$${String.format("%.2f", part.price)} each",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Quantity stepper
            Row(
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = onDecrement,
                    enabled = part.quantity > 1,
                    modifier = Modifier.size(32.dp),
                ) {
                    Icon(Icons.Default.Remove, contentDescription = "Decrease", modifier = Modifier.size(18.dp))
                }
                Text(
                    "${part.quantity}",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.width(24.dp),
                    textAlign = TextAlign.Center,
                )
                IconButton(
                    onClick = onIncrement,
                    modifier = Modifier.size(32.dp),
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Increase", modifier = Modifier.size(18.dp))
                }
            }

            IconButton(onClick = onRemove) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Remove part",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun PartSearchDialog(
    query: String,
    results: List<InventoryListItem>,
    isSearching: Boolean,
    onQueryChange: (String) -> Unit,
    onPartSelected: (InventoryListItem) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Part") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    label = { Text("Search inventory") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(modifier = Modifier.height(12.dp))
                Box(
                    modifier = Modifier.fillMaxWidth().heightIn(max = 300.dp),
                ) {
                    when {
                        isSearching -> {
                            Box(
                                modifier = Modifier.fillMaxWidth(),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(32.dp))
                            }
                        }
                        query.length < 2 -> {
                            Text(
                                "Type at least 2 characters to search",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        results.isEmpty() -> {
                            Text(
                                "No matches",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        else -> {
                            LazyColumn(
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                items(results, key = { it.id }) { item ->
                                    PartSearchResultRow(
                                        item = item,
                                        onClick = { onPartSelected(item) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
    )
}

@Composable
private fun PartSearchResultRow(
    item: InventoryListItem,
    onClick: () -> Unit,
) {
    BrandCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    item.name ?: "Unknown",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (!item.sku.isNullOrBlank()) {
                        Text(
                            item.sku,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        "Stock: ${item.inStock ?: 0}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                "$${String.format("%.2f", item.price ?: 0.0)}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
