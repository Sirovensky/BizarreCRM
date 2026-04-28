package com.bizarreelectronics.crm.ui.screens.checkin.entry

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ── State ──────────────────────────────────────────────────────────────────────

data class EntryStep1State(
    val query: String = "",
    val results: List<CustomerListItem> = emptyList(),
    val isSearching: Boolean = false,
    val attachedCustomer: AttachedCustomerEntry? = null,
    /** In-memory only; populated by attaching a customer this session. */
    val recent: List<AttachedCustomerEntry> = emptyList(),
    val isCreatingNew: Boolean = false,
    val newFirstName: String = "",
    val newLastName: String = "",
    val newPhone: String = "",
    val newEmail: String = "",
    val createError: String? = null,
    val isCreating: Boolean = false,
)

/** Drill-down step inside Add-New-Device: pick category → manufacturer → model → fill details. */
enum class DeviceDrillStep { CATEGORY, MANUFACTURER, MODEL, DETAILS }

data class EntryStep2State(
    val deviceModel: String = "",
    val imeiSerial: String = "",
    val notes: String = "",
    /** Mockup PHONE 2 'ON FILE' rows — fetched from /customers/:id/assets. */
    val onFileDevices: List<OnFileDevice> = emptyList(),
    val selectedOnFileDeviceId: Long? = null,
    /** Toggled true when cashier taps 'Add new device' tile so the text fields reveal. */
    val showManualEntry: Boolean = false,
    /** 2026-04-26 — server-driven device-type chip-row for Add-New-Device. */
    val deviceCategories: List<com.bizarreelectronics.crm.data.remote.api.DeviceCategoryItem> = emptyList(),
    /** Selected category slug (e.g. "phone", "laptop"). null = no selection yet. */
    val selectedDeviceType: String? = null,
    /** 2026-04-27 — drill-down: where in the category → manufacturer → model flow. */
    val drillStep: DeviceDrillStep = DeviceDrillStep.CATEGORY,
    /** Manufacturers available for the selected category (filtered client-side from /catalog/devices). */
    val manufacturers: List<com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem> = emptyList(),
    /** Selected manufacturer id; null = no selection yet. */
    val selectedManufacturerId: Long? = null,
    /** Models available for the selected (category, manufacturer) pair. */
    val models: List<com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem> = emptyList(),
    val drillLoading: Boolean = false,
    val drillError: String? = null,
)

data class OnFileDevice(
    val id: Long,
    val name: String,
    val imei: String? = null,
    val serial: String? = null,
    val color: String? = null,
    val notes: String? = null,
)

data class AttachedCustomerEntry(
    val id: Long,
    val name: String,
    val phone: String? = null,
    val email: String? = null,
    val ticketCount: Int = 0,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class CheckInEntryViewModel @Inject constructor(
    private val customerApi: CustomerApi,
    private val appPreferences: AppPreferences,
    private val deviceCategoryRepository: com.bizarreelectronics.crm.data.repository.DeviceCategoryRepository,
    private val catalogApi: com.bizarreelectronics.crm.data.remote.api.CatalogApi,
) : ViewModel() {

    private val _step1 = MutableStateFlow(EntryStep1State())
    val step1: StateFlow<EntryStep1State> = _step1.asStateFlow()

    private val _step2 = MutableStateFlow(EntryStep2State())
    val step2: StateFlow<EntryStep2State> = _step2.asStateFlow()

    private val _currentStep = MutableStateFlow(0)
    val currentStep: StateFlow<Int> = _currentStep.asStateFlow()

    private val _rawQuery = MutableStateFlow("")

    init {
        wireSearchDebounce()
        hydrateRecentCustomers()
        observeDeviceCategories()
    }

    /** Subscribe to server-driven category list (refreshed at app start). */
    private fun observeDeviceCategories() {
        viewModelScope.launch {
            deviceCategoryRepository.categories.collect { list ->
                _step2.update { it.copy(deviceCategories = list) }
            }
        }
    }

    /**
     * Cashier taps a device-category tile on the Add-New-Device form. Null
     * clears the selection back to root. Selecting a category triggers
     * a server fetch of all models in that category and groups them by
     * manufacturer for the next tile grid.
     */
    fun onDeviceTypeSelected(slug: String?) {
        if (slug == null) {
            // Clear back to root.
            _step2.update {
                it.copy(
                    selectedDeviceType = null,
                    drillStep = DeviceDrillStep.CATEGORY,
                    manufacturers = emptyList(),
                    selectedManufacturerId = null,
                    models = emptyList(),
                    drillError = null,
                )
            }
            return
        }
        _step2.update {
            it.copy(
                selectedDeviceType = slug,
                drillStep = DeviceDrillStep.MANUFACTURER,
                drillLoading = true,
                drillError = null,
                manufacturers = emptyList(),
                selectedManufacturerId = null,
                models = emptyList(),
            )
        }
        viewModelScope.launch {
            runCatching { catalogApi.searchDevices(category = slug, limit = 200) }
                .onSuccess { resp ->
                    val all = resp.data ?: emptyList()
                    val grouped = all
                        .filter { it.manufacturerId != null && it.manufacturerName != null }
                        .groupBy { it.manufacturerId!! to (it.manufacturerName ?: "") }
                        .map { (key, devices) ->
                            com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem(
                                id = key.first,
                                name = key.second,
                                modelCount = devices.size,
                            )
                        }
                        .sortedBy { it.name.lowercase() }
                    _step2.update { it.copy(manufacturers = grouped, drillLoading = false) }
                }
                .onFailure { t ->
                    _step2.update { it.copy(drillLoading = false, drillError = t.message) }
                }
        }
    }

    /** Cashier taps a manufacturer tile. Loads the model list for (category, manufacturer). */
    fun onManufacturerSelected(id: Long?) {
        if (id == null) {
            _step2.update {
                it.copy(
                    selectedManufacturerId = null,
                    drillStep = DeviceDrillStep.MANUFACTURER,
                    models = emptyList(),
                )
            }
            return
        }
        val category = _step2.value.selectedDeviceType ?: return
        _step2.update {
            it.copy(
                selectedManufacturerId = id,
                drillStep = DeviceDrillStep.MODEL,
                drillLoading = true,
                drillError = null,
                models = emptyList(),
            )
        }
        viewModelScope.launch {
            runCatching {
                catalogApi.searchDevices(category = category, manufacturerId = id.toInt(), limit = 200)
            }
                .onSuccess { resp ->
                    val list = resp.data ?: emptyList()
                    val sorted = list.sortedWith(
                        compareByDescending<com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem> { it.releaseYear ?: 0 }
                            .thenBy { it.name.lowercase() },
                    )
                    _step2.update { it.copy(models = sorted, drillLoading = false) }
                }
                .onFailure { t ->
                    _step2.update { it.copy(drillLoading = false, drillError = t.message) }
                }
        }
    }

    /** Cashier taps a model tile. Pre-fills `deviceModel` and advances to DETAILS. */
    fun onModelSelected(model: com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem) {
        _step2.update {
            it.copy(
                drillStep = DeviceDrillStep.DETAILS,
                deviceModel = model.name,
            )
        }
    }

    /** Back button inside the drill: MODEL → MANUFACTURER → CATEGORY. */
    fun onDrillBack() {
        _step2.update {
            when (it.drillStep) {
                DeviceDrillStep.DETAILS -> it.copy(drillStep = DeviceDrillStep.MODEL)
                DeviceDrillStep.MODEL -> it.copy(
                    drillStep = DeviceDrillStep.MANUFACTURER,
                    selectedManufacturerId = null,
                    models = emptyList(),
                )
                DeviceDrillStep.MANUFACTURER -> it.copy(
                    drillStep = DeviceDrillStep.CATEGORY,
                    selectedDeviceType = null,
                    manufacturers = emptyList(),
                )
                DeviceDrillStep.CATEGORY -> it
            }
        }
    }

    /**
     * Fetch the most-recently attached customer detail rows from the server
     * using ids persisted in SharedPreferences. Failures are swallowed — the
     * chip strip just shows fewer entries.
     */
    private fun hydrateRecentCustomers() {
        val ids = appPreferences.recentCheckinCustomerIds
        if (ids.isEmpty()) return
        viewModelScope.launch {
            val fetched = ids.mapNotNull { id ->
                runCatching { customerApi.getCustomer(id) }
                    .getOrNull()
                    ?.data
                    ?.let { d ->
                        AttachedCustomerEntry(
                            id = d.id,
                            name = listOfNotNull(d.firstName, d.lastName)
                                .joinToString(" ")
                                .ifBlank { "Customer #${d.id}" },
                            phone = d.phone ?: d.mobile,
                            email = d.email,
                        )
                    }
            }
            if (fetched.isNotEmpty()) {
                _step1.update { it.copy(recent = fetched) }
            }
        }
    }

    // ── Step navigation ────────────────────────────────────────────────────────

    fun advance() {
        if (_currentStep.value == 0 && _step1.value.attachedCustomer != null) {
            _currentStep.value = 1
        }
    }

    fun goBack() {
        if (_currentStep.value == 1) _currentStep.value = 0
    }

    val canAdvanceStep1: Boolean
        get() = _step1.value.attachedCustomer != null

    val canAdvanceStep2: Boolean
        get() = _step2.value.deviceModel.isNotBlank()

    // ── Step 1: Customer search ────────────────────────────────────────────────

    fun onQueryChange(query: String) {
        _step1.update { it.copy(query = query) }
        _rawQuery.value = query
    }

    fun attachCustomer(customer: CustomerListItem) {
        val entry = AttachedCustomerEntry(
            id = customer.id,
            name = listOfNotNull(customer.firstName, customer.lastName)
                .joinToString(" ")
                .ifBlank { "Customer #${customer.id}" },
            phone = customer.phone ?: customer.mobile,
            email = customer.email,
            ticketCount = customer.ticketCount ?: 0,
        )
        val updatedRecent = (listOf(entry) + _step1.value.recent)
            .distinctBy { it.id }
            .take(MAX_RECENT)
        _step1.update {
            it.copy(
                attachedCustomer = entry,
                recent = updatedRecent,
                query = "",
                results = emptyList(),
                isCreatingNew = false,
            )
        }
        appPreferences.addRecentCheckinCustomerId(entry.id)
        loadOnFileDevices(entry.id)
    }

    /**
     * Mockup PHONE 2 'ON FILE' devices: fetch /customers/:id/assets. Errors
     * silently degrade (the picker just shows 'ADD NEW' without a list).
     */
    private fun loadOnFileDevices(customerId: Long) {
        if (customerId <= 0L) {
            _step2.update { it.copy(onFileDevices = emptyList(), showManualEntry = true) }
            return
        }
        viewModelScope.launch {
            runCatching { customerApi.getAssets(customerId) }
                .onSuccess { resp ->
                    val devices = resp.data.orEmpty().map { a ->
                        OnFileDevice(
                            id = a.id,
                            name = a.name?.takeIf { it.isNotBlank() } ?: "Device #${a.id}",
                            imei = a.imei,
                            serial = a.serial,
                            color = a.color,
                            notes = a.notes,
                        )
                    }
                    _step2.update {
                        it.copy(
                            onFileDevices = devices,
                            // If customer has no devices on file, default to manual-entry mode
                            // so the cashier doesn't see an empty 'ON FILE' header.
                            showManualEntry = devices.isEmpty(),
                        )
                    }
                }
                .onFailure {
                    _step2.update { it.copy(onFileDevices = emptyList(), showManualEntry = true) }
                }
        }
    }

    fun selectOnFileDevice(deviceId: Long) {
        val device = _step2.value.onFileDevices.firstOrNull { it.id == deviceId } ?: return
        _step2.update {
            it.copy(
                selectedOnFileDeviceId = deviceId,
                deviceModel = device.name,
                imeiSerial = device.imei ?: device.serial ?: "",
                notes = device.color ?: device.notes ?: "",
                showManualEntry = false,
            )
        }
    }

    fun toggleManualEntry() {
        _step2.update {
            it.copy(
                showManualEntry = true,
                selectedOnFileDeviceId = null,
                deviceModel = "",
                imeiSerial = "",
                notes = "",
            )
        }
    }

    fun attachWalkIn() {
        val walkIn = AttachedCustomerEntry(id = 0L, name = "Walk-in customer")
        _step1.update {
            it.copy(
                attachedCustomer = walkIn,
                query = "",
                results = emptyList(),
                isCreatingNew = false,
            )
        }
        // Walk-in has no on-file devices — go straight to manual entry.
        _step2.update { it.copy(onFileDevices = emptyList(), showManualEntry = true) }
    }

    fun detachCustomer() {
        _step1.update { it.copy(attachedCustomer = null) }
    }

    /**
     * Pre-fill the attached customer from an ID. Called once on entry when
     * the nav route carries `?customerId=N`. Silent no-op if the id is
     * non-positive or the fetch fails — user can still search manually.
     */
    fun preFillCustomer(customerId: Long) {
        if (_step1.value.attachedCustomer != null) return
        // Walk-in sentinel: customerId == 0 means POS attached a walk-in
        // customer earlier; mirror that here and advance to step 2 so the
        // cashier doesn't pick the customer twice (UX feedback 2026-04-24).
        if (customerId == 0L) {
            attachWalkIn()
            advance()
            return
        }
        if (customerId < 0L) return
        loadOnFileDevices(customerId)
        viewModelScope.launch {
            runCatching { customerApi.getCustomer(customerId) }
                .onSuccess { resp ->
                    val detail = resp.data ?: return@onSuccess
                    val entry = AttachedCustomerEntry(
                        id = detail.id,
                        name = listOfNotNull(detail.firstName, detail.lastName)
                            .joinToString(" ")
                            .ifBlank { "Customer #${detail.id}" },
                        phone = detail.phone ?: detail.mobile,
                        email = detail.email,
                    )
                    _step1.update { it.copy(attachedCustomer = entry) }
                    appPreferences.addRecentCheckinCustomerId(entry.id)
                    // Auto-advance to step 2 (Device) — when CheckInEntry is
                    // launched with a customerId pre-fill, the cashier already
                    // picked the customer in POS; making them re-tap Next on
                    // step 1 reads as a duplicate gate.
                    advance()
                }
        }
    }

    fun showCreateNewForm() {
        _step1.update { it.copy(isCreatingNew = true, createError = null) }
    }

    fun hideCreateNewForm() {
        _step1.update {
            it.copy(
                isCreatingNew = false,
                newFirstName = "",
                newLastName = "",
                newPhone = "",
                newEmail = "",
                createError = null,
            )
        }
    }

    fun onNewFirstNameChange(v: String) = _step1.update { it.copy(newFirstName = v) }
    fun onNewLastNameChange(v: String) = _step1.update { it.copy(newLastName = v) }
    fun onNewPhoneChange(v: String) = _step1.update { it.copy(newPhone = v) }
    fun onNewEmailChange(v: String) = _step1.update { it.copy(newEmail = v) }

    fun submitNewCustomer() {
        val s = _step1.value
        if (s.newFirstName.isBlank()) {
            _step1.update { it.copy(createError = "First name is required") }
            return
        }
        _step1.update { it.copy(isCreating = true, createError = null) }
        viewModelScope.launch {
            runCatching {
                customerApi.createCustomer(
                    CreateCustomerRequest(
                        firstName = s.newFirstName.trim(),
                        lastName = s.newLastName.trim().ifBlank { null },
                        phone = s.newPhone.trim().ifBlank { null },
                        email = s.newEmail.trim().ifBlank { null },
                    )
                )
            }.onSuccess { resp ->
                val detail = resp.data
                if (detail == null) {
                    _step1.update { it.copy(isCreating = false, createError = "Server returned no data") }
                    return@onSuccess
                }
                val entry = AttachedCustomerEntry(
                    id = detail.id,
                    name = listOfNotNull(detail.firstName, detail.lastName)
                        .joinToString(" ")
                        .ifBlank { "New customer" },
                    phone = detail.phone ?: detail.mobile,
                    email = detail.email,
                )
                val updatedRecent = (listOf(entry) + _step1.value.recent)
                    .distinctBy { it.id }
                    .take(MAX_RECENT)
                _step1.update {
                    it.copy(
                        isCreating = false,
                        isCreatingNew = false,
                        attachedCustomer = entry,
                        recent = updatedRecent,
                        newFirstName = "",
                        newLastName = "",
                        newPhone = "",
                        newEmail = "",
                    )
                }
                appPreferences.addRecentCheckinCustomerId(entry.id)
            }.onFailure { e ->
                _step1.update { it.copy(isCreating = false, createError = "Could not create: ${e.message}") }
            }
        }
    }

    // ── Step 2: Device info ────────────────────────────────────────────────────

    fun onDeviceModelChange(v: String) = _step2.update { it.copy(deviceModel = v) }
    fun onImeiSerialChange(v: String) = _step2.update { it.copy(imeiSerial = v) }
    fun onNotesChange(v: String) = _step2.update { it.copy(notes = v) }

    // ── Internal search debounce ───────────────────────────────────────────────

    @OptIn(FlowPreview::class)
    private fun wireSearchDebounce() {
        viewModelScope.launch {
            _rawQuery
                .debounce(SEARCH_DEBOUNCE_MS)
                .distinctUntilChanged()
                .collect { q ->
                    if (q.isNotBlank()) runSearch(q) else clearResults()
                }
        }
    }

    private fun runSearch(query: String) {
        _step1.update { it.copy(isSearching = true) }
        viewModelScope.launch {
            val results = runCatching { customerApi.searchCustomers(query) }
                .getOrNull()
                ?.data
                ?: emptyList()
            _step1.update { it.copy(isSearching = false, results = results) }
        }
    }

    private fun clearResults() {
        _step1.update { it.copy(results = emptyList(), isSearching = false) }
    }

    companion object {
        private const val SEARCH_DEBOUNCE_MS = 300L
        private const val MAX_RECENT = 3
    }
}

// Stable distinct-by helper (list-scope, avoids importing a full util)
private fun <T, K> List<T>.distinctBy(selector: (T) -> K): List<T> {
    val seen = mutableSetOf<K>()
    return filter { seen.add(selector(it)) }
}
