package com.bizarreelectronics.crm.ui.screens.tickets

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.theme.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.*
import com.bizarreelectronics.crm.data.remote.dto.*
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.data.repository.TicketRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import java.util.UUID
import javax.inject.Inject

// ===========================================================================================
// Constants
// ===========================================================================================

private const val DEFAULT_TAX_RATE = 0.08865
private const val SEARCH_DEBOUNCE_MS = 300L

private data class CategoryTile(val value: String, val label: String, val emoji: String)

// CROSS26 (deferred): the full sweep from emoji tiles to MaterialIcons is a
// broader design call — pick an icon family + tint + stroke weight across the
// app, not just this grid. Until that refactor lands, keep the emoji set as
// currently distinct (phone/tablet/other covered by CROSS11 + CROSS27) and
// leave the rest untouched. Do not swap individual tiles piecemeal here.
// CROSS25: removed "data_recovery" + "quick" tiles — neither is a device
// category.
//   - Data Recovery is a SERVICE (future: surface it as a repair service
//     option on the Service step, selectable regardless of device category;
//     ticket flow still needs a device chosen first so the drive/phone can
//     be tagged to the correct model).
//   - Quick Check-in is a shortcut FLOW (future: promote to a ghost button
//     on the ticket-list FAB that skips Category and lands on a pared-down
//     device + notes form; keeping it here forced users to pick a non-
//     category before the wizard could continue, and downstream steps have
//     nothing to populate from "quick").
// ISSUE_MACROS entries for both keys are retained below — harmless fallbacks
// if a pre-existing draft state with those categories is ever rehydrated.
private val CATEGORY_TILES = listOf(
    CategoryTile("phone", "Mobile", "\uD83D\uDCF1"),
    // CROSS11: tablet uses open-book glyph to visually distinguish from the phone tile.
    CategoryTile("tablet", "Tablet", "\uD83D\uDCD6"),
    CategoryTile("laptop", "Laptop / Mac", "\uD83D\uDCBB"),
    CategoryTile("tv", "TV", "\uD83D\uDCFA"),
    CategoryTile("desktop", "Desktop", "\uD83D\uDDA5\uFE0F"),
    CategoryTile("console", "Game Console", "\uD83C\uDFAE"),
    // CROSS27: neutral grey question mark ornament — red U+2753 read as "error".
    CategoryTile("other", "Other", "\u2754"),
)

private data class ManufacturerShortcut(val label: String, val names: List<String>)

private val MANUFACTURER_SHORTCUTS: Map<String, List<ManufacturerShortcut>> = mapOf(
    "phone" to listOf(
        ManufacturerShortcut("Apple", listOf("Apple")),
        ManufacturerShortcut("Samsung", listOf("Samsung")),
        ManufacturerShortcut("Google", listOf("Google")),
        ManufacturerShortcut("Motorola", listOf("Motorola")),
        ManufacturerShortcut("LG", listOf("LG")),
        ManufacturerShortcut("OnePlus", listOf("OnePlus")),
    ),
    "tablet" to listOf(
        ManufacturerShortcut("Apple iPad", listOf("Apple")),
        ManufacturerShortcut("Samsung", listOf("Samsung")),
        ManufacturerShortcut("Lenovo", listOf("Lenovo")),
        ManufacturerShortcut("Microsoft", listOf("Microsoft")),
    ),
    "laptop" to listOf(
        ManufacturerShortcut("Apple", listOf("Apple")),
        ManufacturerShortcut("Dell", listOf("Dell")),
        ManufacturerShortcut("HP", listOf("HP")),
        ManufacturerShortcut("Lenovo", listOf("Lenovo")),
        ManufacturerShortcut("Asus", listOf("Asus")),
        ManufacturerShortcut("Acer", listOf("Acer")),
    ),
    "tv" to listOf(
        ManufacturerShortcut("Samsung", listOf("Samsung")),
        ManufacturerShortcut("LG", listOf("LG")),
        ManufacturerShortcut("Sony", listOf("Sony")),
        ManufacturerShortcut("TCL", listOf("TCL")),
        ManufacturerShortcut("Hisense", listOf("Hisense")),
        ManufacturerShortcut("Vizio", listOf("Vizio")),
    ),
    "console" to listOf(
        ManufacturerShortcut("Nintendo", listOf("Nintendo")),
        ManufacturerShortcut("PlayStation", listOf("Sony PlayStation")),
        ManufacturerShortcut("Xbox", listOf("Xbox")),
        ManufacturerShortcut("Steam", listOf("Steam")),
        ManufacturerShortcut("Meta", listOf("Meta")),
    ),
)

private val COLOR_OPTIONS = listOf(
    "Black", "White", "Silver", "Gold", "Blue", "Red", "Green", "Purple", "Pink", "Other"
)

private val NETWORK_OPTIONS = listOf(
    "AT&T", "T-Mobile", "Verizon", "Sprint", "US Cellular", "Cricket", "Metro", "Boost", "Unlocked", "Other"
)

private val ISSUE_MACROS: Map<String, List<String>> = mapOf(
    "phone" to listOf("Cracked screen", "Battery replacement", "Charging port", "Water damage", "Camera not working", "Speaker issues", "Won't turn on"),
    "tablet" to listOf("Cracked screen", "Battery replacement", "Charging port", "Water damage", "Won't turn on", "Slow performance"),
    "laptop" to listOf("Won't turn on", "Slow performance", "Screen replacement", "Keyboard", "Battery replacement", "Fan noise", "No Wi-Fi"),
    "tv" to listOf("No picture", "Cracked screen", "No sound", "Won't turn on", "Backlight issue", "HDMI port"),
    "console" to listOf("HDMI port", "Disc drive", "Overheating", "Controller port", "Won't turn on", "Blue light of death"),
    "desktop" to listOf("Won't turn on", "Slow performance", "No display", "Blue screen", "Fan noise", "No Wi-Fi"),
    "other" to listOf("Won't turn on", "Physical damage", "Not charging", "Other issue"),
    "data_recovery" to listOf("Deleted files", "Drive not recognized", "Water damage", "Clicking noise"),
    "quick" to listOf("Quick diagnostic", "Data transfer", "Software issue"),
)

private val PASSCODE_LABELS: Map<String, String> = mapOf(
    "phone" to "Passcode / PIN",
    "tablet" to "Passcode / PIN",
    "laptop" to "Login Password",
    "desktop" to "Login Password",
    "console" to "Account Password",
    "tv" to "PIN Code",
)

private val DEVICE_PLACEHOLDERS: Map<String, String> = mapOf(
    "phone" to "e.g. Samsung Galaxy A15",
    "tablet" to "e.g. iPad Air 5th Gen",
    "laptop" to "e.g. Dell Latitude 5540",
    "tv" to "e.g. Samsung UN55TU7000",
    "console" to "e.g. PlayStation 5 Slim",
    "desktop" to "e.g. Dell OptiPlex 7080",
    "other" to "e.g. DJI Mavic 3",
    "data_recovery" to "e.g. WD My Passport 2TB",
    "quick" to "e.g. Samsung Galaxy A15",
)

// ===========================================================================================
// CROSS29 — Popular-list brand mixer
// ===========================================================================================

/**
 * When the server's Popular list is short (≤ 6) or already brand-diverse the
 * list is returned as-is. When it's long AND dominated by a single brand
 * (e.g. every one is Apple) we round-robin the brands' own top entries so
 * users can see the brand spread at a glance. Intended for new shops with
 * no ticket history whose server-side "Popular" ordering degenerates into a
 * monoculture from the seeded device_models table.
 *
 * Ordering inside each brand bucket is preserved so the server-side
 * ranking (repair count, release year, etc.) still wins within a brand.
 *
 * A device with a blank/null `manufacturerName` stays at its original
 * position as a last resort — better to show something than nothing.
 */
private fun mixBrandsIfMonolithic(
    popular: List<DeviceModelItem>,
    monolithicThreshold: Int = 6,
    perBrandCap: Int = 2,
): List<DeviceModelItem> {
    if (popular.size <= monolithicThreshold) return popular
    val distinctBrands = popular.mapNotNull { it.manufacturerName?.takeIf { n -> n.isNotBlank() } }.distinct()
    if (distinctBrands.size <= 1) return popular // nothing to mix — genuine single-brand category

    // Group by brand, preserving the server's ordering inside each bucket.
    val buckets: Map<String, List<DeviceModelItem>> = popular
        .groupBy { it.manufacturerName ?: "" }
        .mapValues { (_, items) -> items.take(perBrandCap) }

    // Round-robin across brands in the order they first appeared in `popular`.
    val mixed = mutableListOf<DeviceModelItem>()
    val iterators = distinctBrands.map { buckets[it]?.iterator() ?: emptyList<DeviceModelItem>().iterator() }
    var added = true
    while (added) {
        added = false
        for (iter in iterators) {
            if (iter.hasNext()) {
                mixed.add(iter.next())
                added = true
            }
        }
    }
    return mixed
}

// ===========================================================================================
// Cart data models
// ===========================================================================================

data class CartPart(
    val inventoryItemId: Long?,
    val name: String,
    val price: Double = 0.0,
    val quantity: Int = 1,
)

data class RepairCartItem(
    val id: String = UUID.randomUUID().toString(),
    val deviceName: String,
    val deviceModelId: Long? = null,
    val category: String,
    val serviceName: String?,
    val serviceId: Long? = null,
    val gradeId: Long? = null,
    val laborPrice: Double = 0.0,
    val parts: List<CartPart> = emptyList(),
    val imei: String = "",
    val serial: String = "",
    val securityCode: String = "",
    val color: String = "",
    val network: String = "",
    val preConditions: List<String> = emptyList(),
    val notes: String = "",
    val deviceLocation: String = "",
    val warranty: Boolean = false,
    val warrantyDays: Int = 90,
) {
    val partsTotal: Double get() = parts.sumOf { it.price * it.quantity }
    val lineTotal: Double get() = laborPrice + partsTotal
}

// ===========================================================================================
// UI State
// ===========================================================================================

enum class TicketCreateStep(val label: String) {
    CUSTOMER("Customer"),
    CATEGORY("Category"),
    DEVICE("Device"),
    SERVICE("Service"),
    DETAILS("Details"),
    CART("Cart"),
}

data class TicketCreateUiState(
    val currentStep: TicketCreateStep = TicketCreateStep.CUSTOMER,

    // Customer step
    val customerQuery: String = "",
    val customerResults: List<CustomerListItem> = emptyList(),
    val isSearching: Boolean = false,
    val selectedCustomer: CustomerListItem? = null,
    val showNewCustomerForm: Boolean = false,
    val newCustFirstName: String = "",
    val newCustLastName: String = "",
    val newCustPhone: String = "",
    val newCustEmail: String = "",
    val isCreatingCustomer: Boolean = false,

    // Category step
    val selectedCategory: String? = null,

    // Device step
    val manufacturers: List<ManufacturerItem> = emptyList(),
    val selectedManufacturerId: Long? = null,
    val deviceSearchQuery: String = "",
    val deviceSearchResults: List<DeviceModelItem> = emptyList(),
    val popularDevices: List<DeviceModelItem> = emptyList(),
    val isLoadingDevices: Boolean = false,
    val selectedDevice: DeviceModelItem? = null,
    val customDeviceName: String = "",

    // Service step
    val services: List<RepairServiceItem> = emptyList(),
    val selectedService: RepairServiceItem? = null,
    val priceLookup: RepairPriceLookup? = null,
    val isLoadingPricing: Boolean = false,
    val selectedGrade: RepairPriceGrade? = null,
    val manualPrice: String = "",

    // Details step
    val imei: String = "",
    val serial: String = "",
    val securityCode: String = "",
    val color: String = "",
    val network: String = "",
    val conditionChecks: List<ConditionCheckItem> = emptyList(),
    val selectedConditions: Set<String> = emptySet(),
    val notes: String = "",
    val warrantyEnabled: Boolean = false,
    val warrantyDays: String = "90",

    // Cart
    val cartItems: List<RepairCartItem> = emptyList(),

    // Tax
    val taxRate: Double = DEFAULT_TAX_RATE,

    // General
    val isSubmitting: Boolean = false,
    val error: String? = null,
)

// ===========================================================================================
// ViewModel
// ===========================================================================================

@HiltViewModel
class TicketCreateViewModel @Inject constructor(
    private val customerApi: CustomerApi,
    private val ticketRepository: TicketRepository,
    private val customerRepository: CustomerRepository,
    private val catalogApi: CatalogApi,
    private val repairPricingApi: RepairPricingApi,
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _state = MutableStateFlow(TicketCreateUiState())
    val state: StateFlow<TicketCreateUiState> = _state.asStateFlow()

    private var customerSearchJob: Job? = null
    private var deviceSearchJob: Job? = null

    init {
        loadDefaultTaxRate()
    }

    private fun loadDefaultTaxRate() {
        viewModelScope.launch {
            try {
                val response = settingsApi.getTaxClasses()
                if (response.success && response.data != null) {
                    val taxClasses = response.data.taxClasses
                    val defaultClass = taxClasses.firstOrNull { it.isDefault == 1 }
                        ?: taxClasses.firstOrNull()
                    if (defaultClass != null && defaultClass.rate > 0) {
                        _state.update { it.copy(taxRate = defaultClass.rate / 100.0) }
                    }
                }
            } catch (_: Exception) {
                // Non-critical — fall back to default rate
            }
        }
    }

    // ── Customer search ──────────────────────────────────────────────

    fun updateCustomerQuery(query: String) {
        _state.update { it.copy(customerQuery = query) }
        customerSearchJob?.cancel()
        if (query.length < 2) {
            _state.update { it.copy(customerResults = emptyList(), isSearching = false) }
            return
        }
        customerSearchJob = viewModelScope.launch {
            delay(SEARCH_DEBOUNCE_MS)
            _state.update { it.copy(isSearching = true) }
            // Use repository for offline-capable search
            customerRepository.searchCustomers(query).collect { entities ->
                val results = entities.map { e ->
                    CustomerListItem(
                        id = e.id,
                        firstName = e.firstName,
                        lastName = e.lastName,
                        email = e.email,
                        phone = e.phone,
                        mobile = e.mobile,
                        organization = e.organization,
                        city = e.city,
                        state = e.state,
                        customerGroupName = e.groupName,
                        createdAt = e.createdAt,
                        ticketCount = null,
                    )
                }
                _state.update { it.copy(customerResults = results, isSearching = false) }
            }
        }
    }

    fun selectCustomer(customer: CustomerListItem) {
        _state.update {
            it.copy(
                selectedCustomer = customer,
                customerQuery = "",
                customerResults = emptyList(),
                currentStep = TicketCreateStep.CATEGORY,
            )
        }
    }

    fun clearCustomer() {
        _state.update { it.copy(selectedCustomer = null) }
    }

    fun toggleNewCustomerForm() {
        _state.update { it.copy(showNewCustomerForm = !it.showNewCustomerForm) }
    }

    fun updateNewCustFirstName(value: String) { _state.update { it.copy(newCustFirstName = value) } }
    fun updateNewCustLastName(value: String) { _state.update { it.copy(newCustLastName = value) } }
    fun updateNewCustPhone(value: String) { _state.update { it.copy(newCustPhone = value) } }
    fun updateNewCustEmail(value: String) { _state.update { it.copy(newCustEmail = value) } }

    fun createAndSelectCustomer() {
        val s = _state.value
        val firstName = s.newCustFirstName.trim()
        val phone = s.newCustPhone.trim()
        if (firstName.isBlank() || phone.isBlank()) {
            _state.update { it.copy(error = "First name and phone are required.") }
            return
        }
        _state.update { it.copy(isCreatingCustomer = true, error = null) }
        viewModelScope.launch {
            try {
                val request = CreateCustomerRequest(
                    firstName = firstName,
                    lastName = s.newCustLastName.trim().ifBlank { null },
                    phone = phone,
                    email = s.newCustEmail.trim().ifBlank { null },
                )
                val createdId = customerRepository.createCustomer(request)
                val listItem = CustomerListItem(
                    id = createdId,
                    firstName = firstName,
                    lastName = s.newCustLastName.trim().ifBlank { null },
                    email = s.newCustEmail.trim().ifBlank { null },
                    phone = phone,
                    mobile = null,
                    organization = null,
                    city = null,
                    state = null,
                    customerGroupName = null,
                    createdAt = null,
                    ticketCount = 0,
                )
                _state.update {
                    it.copy(
                        isCreatingCustomer = false,
                        showNewCustomerForm = false,
                        newCustFirstName = "",
                        newCustLastName = "",
                        newCustPhone = "",
                        newCustEmail = "",
                        selectedCustomer = listItem,
                        customerQuery = "",
                        customerResults = emptyList(),
                        currentStep = TicketCreateStep.CATEGORY,
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(isCreatingCustomer = false, error = e.message ?: "Failed to create customer.") }
            }
        }
    }

    // ── Category selection ───────────────────────────────────────────

    fun selectCategory(category: String) {
        _state.update {
            it.copy(
                selectedCategory = category,
                currentStep = TicketCreateStep.DEVICE,
                // Reset device/service state for fresh selection
                selectedManufacturerId = null,
                deviceSearchQuery = "",
                deviceSearchResults = emptyList(),
                popularDevices = emptyList(),
                selectedDevice = null,
                customDeviceName = "",
                selectedService = null,
                priceLookup = null,
                selectedGrade = null,
                manualPrice = "",
                services = emptyList(),
            )
        }
        loadManufacturersAndPopular(category)
        loadServices(category)
    }

    private fun loadManufacturersAndPopular(category: String) {
        viewModelScope.launch {
            try {
                val mfgResponse = catalogApi.getManufacturers()
                val manufacturers = if (mfgResponse.success) mfgResponse.data ?: emptyList() else emptyList()
                _state.update { it.copy(manufacturers = manufacturers) }
            } catch (_: Exception) {
                // Non-critical, manufacturer filter just won't show
            }
        }
        viewModelScope.launch {
            try {
                val popResponse = catalogApi.searchDevices(category = category, popular = 1, limit = 20)
                val popular = if (popResponse.success) popResponse.data ?: emptyList() else emptyList()
                _state.update { it.copy(popularDevices = popular) }
            } catch (_: Exception) {
                // Non-critical
            }
        }
    }

    private fun loadServices(category: String) {
        viewModelScope.launch {
            try {
                val response = repairPricingApi.getServices(category = category)
                val services = if (response.success) response.data ?: emptyList() else emptyList()
                _state.update { it.copy(services = services.filter { s -> s.isActive == 1 }) }
            } catch (_: Exception) {
                _state.update { it.copy(services = emptyList()) }
            }
        }
    }

    // ── Manufacturer filter ──────────────────────────────────────────

    fun selectManufacturer(manufacturerId: Long?) {
        val newId = if (_state.value.selectedManufacturerId == manufacturerId) null else manufacturerId
        _state.update { it.copy(selectedManufacturerId = newId) }
        refreshDeviceSearch()
    }

    // ── Device search ────────────────────────────────────────────────

    fun updateDeviceSearch(query: String) {
        _state.update { it.copy(deviceSearchQuery = query) }
        deviceSearchJob?.cancel()
        if (query.length < 2 && _state.value.selectedManufacturerId == null) {
            _state.update { it.copy(deviceSearchResults = emptyList(), isLoadingDevices = false) }
            return
        }
        deviceSearchJob = viewModelScope.launch {
            delay(SEARCH_DEBOUNCE_MS)
            _state.update { it.copy(isLoadingDevices = true) }
            try {
                val current = _state.value
                val response = catalogApi.searchDevices(
                    query = query.ifBlank { null },
                    category = current.selectedCategory,
                    manufacturerId = current.selectedManufacturerId?.toInt(),
                    limit = 50,
                )
                val results = if (response.success) response.data ?: emptyList() else emptyList()
                _state.update { it.copy(deviceSearchResults = results, isLoadingDevices = false) }
            } catch (_: Exception) {
                _state.update { it.copy(deviceSearchResults = emptyList(), isLoadingDevices = false) }
            }
        }
    }

    private fun refreshDeviceSearch() {
        val query = _state.value.deviceSearchQuery
        if (query.length >= 2 || _state.value.selectedManufacturerId != null) {
            updateDeviceSearch(query)
        }
    }

    fun selectDevice(device: DeviceModelItem) {
        _state.update {
            it.copy(
                selectedDevice = device,
                customDeviceName = "",
                currentStep = TicketCreateStep.SERVICE,
            )
        }
    }

    fun updateCustomDeviceName(name: String) {
        _state.update { it.copy(customDeviceName = name) }
    }

    fun confirmCustomDevice() {
        val name = _state.value.customDeviceName.trim()
        if (name.isBlank()) return
        _state.update {
            it.copy(
                selectedDevice = null,
                currentStep = TicketCreateStep.SERVICE,
            )
        }
    }

    // ── Service selection + pricing ──────────────────────────────────

    fun selectService(service: RepairServiceItem) {
        _state.update {
            it.copy(
                selectedService = service,
                priceLookup = null,
                selectedGrade = null,
                isLoadingPricing = true,
                manualPrice = "",
            )
        }
        val deviceModelId = _state.value.selectedDevice?.id
        if (deviceModelId != null) {
            viewModelScope.launch {
                try {
                    val response = repairPricingApi.pricingLookup(
                        deviceModelId = deviceModelId.toInt(),
                        serviceId = service.id.toInt(),
                    )
                    if (response.success && response.data != null) {
                        val lookup = response.data
                        val defaultGrade = lookup.grades.firstOrNull { it.isDefault == 1 }
                            ?: lookup.grades.firstOrNull()
                        _state.update {
                            it.copy(
                                priceLookup = lookup,
                                selectedGrade = defaultGrade,
                                isLoadingPricing = false,
                            )
                        }
                    } else {
                        _state.update { it.copy(isLoadingPricing = false) }
                    }
                } catch (_: Exception) {
                    _state.update { it.copy(isLoadingPricing = false) }
                }
            }
        } else {
            _state.update { it.copy(isLoadingPricing = false) }
        }
    }

    fun selectGrade(grade: RepairPriceGrade) {
        _state.update { it.copy(selectedGrade = grade) }
    }

    fun updateManualPrice(price: String) {
        _state.update { it.copy(manualPrice = price) }
    }

    fun confirmService() {
        _state.update { it.copy(currentStep = TicketCreateStep.DETAILS) }
        loadConditionChecks()
    }

    // ── Details step ─────────────────────────────────────────────────

    private fun loadConditionChecks() {
        val category = _state.value.selectedCategory ?: return
        viewModelScope.launch {
            try {
                val response = settingsApi.getConditionChecks(category)
                if (response.success && response.data != null) {
                    _state.update { it.copy(conditionChecks = response.data) }
                }
            } catch (_: Exception) {
                // Non-critical, condition checks just won't show
            }
        }
    }

    fun updateImei(value: String) { _state.update { it.copy(imei = value) } }
    fun updateSerial(value: String) { _state.update { it.copy(serial = value) } }
    fun updateSecurityCode(value: String) { _state.update { it.copy(securityCode = value) } }
    fun updateColor(value: String) { _state.update { it.copy(color = value) } }
    fun updateNetwork(value: String) { _state.update { it.copy(network = value) } }
    fun updateNotes(value: String) { _state.update { it.copy(notes = value) } }
    fun updateWarrantyDays(value: String) { _state.update { it.copy(warrantyDays = value) } }

    fun toggleCondition(label: String) {
        _state.update { current ->
            val updated = if (label in current.selectedConditions) {
                current.selectedConditions - label
            } else {
                current.selectedConditions + label
            }
            current.copy(selectedConditions = updated)
        }
    }

    fun toggleWarranty() {
        _state.update { it.copy(warrantyEnabled = !it.warrantyEnabled) }
    }

    fun appendToNotes(macro: String) {
        _state.update { current ->
            val existing = current.notes.trim()
            val separator = if (existing.isNotEmpty()) ". " else ""
            current.copy(notes = existing + separator + macro)
        }
    }

    // ── Cart management ──────────────────────────────────────────────

    fun addToCart() {
        val s = _state.value
        val deviceName = s.selectedDevice?.name ?: s.customDeviceName.trim()
        if (deviceName.isBlank()) return

        val laborPrice = resolvePrice(s)
        val parts = buildCartParts(s)

        val item = RepairCartItem(
            deviceName = deviceName,
            deviceModelId = s.selectedDevice?.id,
            category = s.selectedCategory ?: "other",
            serviceName = s.selectedService?.name,
            serviceId = s.selectedService?.id,
            gradeId = s.selectedGrade?.id,
            laborPrice = laborPrice,
            parts = parts,
            imei = s.imei,
            serial = s.serial,
            securityCode = s.securityCode,
            color = s.color,
            network = s.network,
            preConditions = s.selectedConditions.toList(),
            notes = s.notes,
            warranty = s.warrantyEnabled,
            warrantyDays = s.warrantyDays.toIntOrNull() ?: 90,
        )

        _state.update { current ->
            current.copy(
                cartItems = current.cartItems + item,
                currentStep = TicketCreateStep.CART,
                // Reset for next device
                selectedDevice = null,
                customDeviceName = "",
                selectedService = null,
                priceLookup = null,
                selectedGrade = null,
                manualPrice = "",
                imei = "",
                serial = "",
                securityCode = "",
                color = "",
                network = "",
                selectedConditions = emptySet(),
                notes = "",
                warrantyEnabled = false,
                warrantyDays = "90",
                conditionChecks = emptyList(),
            )
        }
    }

    private fun resolvePrice(s: TicketCreateUiState): Double {
        val gradeLabor = s.selectedGrade?.effectiveLaborPrice
        if (gradeLabor != null && gradeLabor > 0) return gradeLabor
        val lookupLabor = s.priceLookup?.laborPrice
        if (lookupLabor != null && lookupLabor > 0) return lookupLabor
        return s.manualPrice.toDoubleOrNull() ?: 0.0
    }

    private fun buildCartParts(s: TicketCreateUiState): List<CartPart> {
        val grade = s.selectedGrade ?: return emptyList()
        if (grade.partPrice <= 0) return emptyList()
        return listOf(
            CartPart(
                inventoryItemId = grade.partInventoryItemId,
                name = grade.inventoryItemName ?: "${s.selectedService?.name ?: "Part"} (${grade.gradeLabel ?: grade.grade})",
                price = grade.partPrice,
            )
        )
    }

    fun removeFromCart(itemId: String) {
        _state.update { current ->
            current.copy(cartItems = current.cartItems.filter { it.id != itemId })
        }
    }

    fun addAnotherDevice() {
        _state.update { it.copy(currentStep = TicketCreateStep.CATEGORY) }
    }

    // ── Submit ────────────────────────────────────────────────────────

    fun submitTicket(onCreated: (Long) -> Unit) {
        val s = _state.value
        if (s.selectedCustomer == null) {
            _state.update { it.copy(error = "Please select a customer first.") }
            return
        }
        if (s.cartItems.isEmpty()) {
            _state.update { it.copy(error = "Cart is empty. Add at least one device.") }
            return
        }

        _state.update { it.copy(isSubmitting = true, error = null) }
        viewModelScope.launch {
            try {
                val devices = s.cartItems.map { item ->
                    CreateTicketDeviceRequest(
                        name = item.deviceName,
                        deviceModelId = item.deviceModelId,
                        category = item.category,
                        imei = item.imei.ifBlank { null },
                        serial = item.serial.ifBlank { null },
                        securityCode = item.securityCode.ifBlank { null },
                        color = item.color.ifBlank { null },
                        price = item.laborPrice.takeIf { p -> p > 0 },
                        additionalNotes = item.notes.ifBlank { null },
                        warranty = item.warranty,
                        warrantyDays = if (item.warranty) item.warrantyDays else null,
                        warrantyTimeframe = if (item.warranty) "${item.warrantyDays}d" else null,
                        preConditions = item.preConditions.takeIf { c -> c.isNotEmpty() },
                        parts = item.parts.takeIf { p -> p.isNotEmpty() }?.map { part ->
                            CreateTicketPartRequest(
                                inventoryItemId = part.inventoryItemId,
                                name = part.name,
                                quantity = part.quantity,
                                price = part.price,
                            )
                        },
                    )
                }
                val request = CreateTicketRequest(
                    customerId = s.selectedCustomer.id,
                    devices = devices,
                )
                val createdId = ticketRepository.createTicket(request)
                _state.update { it.copy(isSubmitting = false) }
                onCreated(createdId)
            } catch (e: Exception) {
                _state.update { it.copy(isSubmitting = false, error = e.message ?: "Network error.") }
            }
        }
    }

    // ── Navigation ────────────────────────────────────────────────────

    fun goBack() {
        val currentStep = _state.value.currentStep
        val previous = when (currentStep) {
            TicketCreateStep.CUSTOMER -> null
            TicketCreateStep.CATEGORY -> TicketCreateStep.CUSTOMER
            TicketCreateStep.DEVICE -> TicketCreateStep.CATEGORY
            TicketCreateStep.SERVICE -> TicketCreateStep.DEVICE
            TicketCreateStep.DETAILS -> TicketCreateStep.SERVICE
            TicketCreateStep.CART -> TicketCreateStep.DETAILS
        }
        if (previous != null) {
            _state.update { it.copy(currentStep = previous, error = null) }
        }
    }

    fun goToStep(step: TicketCreateStep) {
        _state.update { it.copy(currentStep = step, error = null) }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }
}

// ===========================================================================================
// Formatting
// ===========================================================================================

private val currencyFormatter: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US)

private fun formatCurrency(amount: Double): String = currencyFormatter.format(amount)

// ===========================================================================================
// Main Screen Composable
// ===========================================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: TicketCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // CROSS34: system back walks the wizard backward one step instead of popping
    // the whole screen off the nav stack. Preserves selections accumulated in the
    // earlier steps. When we're already on Customer (step 1), the system back
    // pops the wizard back to the caller (which is the existing onBack behavior).
    androidx.activity.compose.BackHandler(
        enabled = state.currentStep != TicketCreateStep.CUSTOMER,
    ) {
        viewModel.goBack()
    }

    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "New Ticket",
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.currentStep == TicketCreateStep.CUSTOMER) onBack()
                        else viewModel.goBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .padding(horizontal = 16.dp),
        ) {
            StepIndicator(
                currentStep = state.currentStep,
                onGoToStep = viewModel::goToStep,
                modifier = Modifier.padding(vertical = 12.dp),
            )

            when (state.currentStep) {
                TicketCreateStep.CUSTOMER -> CustomerStep(
                    query = state.customerQuery,
                    results = state.customerResults,
                    isSearching = state.isSearching,
                    selectedCustomer = state.selectedCustomer,
                    onQueryChange = viewModel::updateCustomerQuery,
                    onSelect = viewModel::selectCustomer,
                    onClear = viewModel::clearCustomer,
                    showNewCustomerForm = state.showNewCustomerForm,
                    onToggleNewCustomerForm = viewModel::toggleNewCustomerForm,
                    newCustFirstName = state.newCustFirstName,
                    newCustLastName = state.newCustLastName,
                    newCustPhone = state.newCustPhone,
                    newCustEmail = state.newCustEmail,
                    isCreatingCustomer = state.isCreatingCustomer,
                    onNewCustFirstNameChange = viewModel::updateNewCustFirstName,
                    onNewCustLastNameChange = viewModel::updateNewCustLastName,
                    onNewCustPhoneChange = viewModel::updateNewCustPhone,
                    onNewCustEmailChange = viewModel::updateNewCustEmail,
                    onCreateAndSelect = viewModel::createAndSelectCustomer,
                )

                TicketCreateStep.CATEGORY -> CategoryStep(
                    onSelect = viewModel::selectCategory,
                )

                TicketCreateStep.DEVICE -> DeviceStep(
                    category = state.selectedCategory ?: "other",
                    manufacturers = state.manufacturers,
                    selectedManufacturerId = state.selectedManufacturerId,
                    searchQuery = state.deviceSearchQuery,
                    searchResults = state.deviceSearchResults,
                    popularDevices = state.popularDevices,
                    isLoading = state.isLoadingDevices,
                    customDeviceName = state.customDeviceName,
                    onManufacturerSelect = viewModel::selectManufacturer,
                    onSearchChange = viewModel::updateDeviceSearch,
                    onDeviceSelect = viewModel::selectDevice,
                    onCustomNameChange = viewModel::updateCustomDeviceName,
                    onCustomDeviceConfirm = viewModel::confirmCustomDevice,
                )

                TicketCreateStep.SERVICE -> ServiceStep(
                    services = state.services,
                    selectedService = state.selectedService,
                    priceLookup = state.priceLookup,
                    isLoadingPricing = state.isLoadingPricing,
                    selectedGrade = state.selectedGrade,
                    manualPrice = state.manualPrice,
                    onServiceSelect = viewModel::selectService,
                    onGradeSelect = viewModel::selectGrade,
                    onManualPriceChange = viewModel::updateManualPrice,
                    onConfirm = viewModel::confirmService,
                )

                TicketCreateStep.DETAILS -> DetailsStep(
                    state = state,
                    onImeiChange = viewModel::updateImei,
                    onSerialChange = viewModel::updateSerial,
                    onSecurityCodeChange = viewModel::updateSecurityCode,
                    onColorChange = viewModel::updateColor,
                    onNetworkChange = viewModel::updateNetwork,
                    onToggleCondition = viewModel::toggleCondition,
                    onNotesChange = viewModel::updateNotes,
                    onMacroClick = viewModel::appendToNotes,
                    onToggleWarranty = viewModel::toggleWarranty,
                    onWarrantyDaysChange = viewModel::updateWarrantyDays,
                    onAddToCart = viewModel::addToCart,
                )

                TicketCreateStep.CART -> CartStep(
                    cartItems = state.cartItems,
                    taxRate = state.taxRate,
                    isSubmitting = state.isSubmitting,
                    onRemoveItem = viewModel::removeFromCart,
                    onAddAnother = viewModel::addAnotherDevice,
                    onSubmit = { viewModel.submitTicket(onCreated) },
                )
            }
        }
    }
}

// ===========================================================================================
// Step Indicator
// ===========================================================================================

@Composable
private fun StepIndicator(
    currentStep: TicketCreateStep,
    onGoToStep: (TicketCreateStep) -> Unit,
    modifier: Modifier = Modifier,
) {
    val steps = TicketCreateStep.entries
    val currentIndex = steps.indexOf(currentStep)

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        steps.forEachIndexed { index, step ->
            val isClickable = index < currentIndex
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .weight(1f)
                    .then(
                        if (isClickable) Modifier.clickable { onGoToStep(step) }
                        else Modifier
                    ),
            ) {
                val isActive = index <= currentIndex
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = if (isActive) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.surfaceVariant,
                    modifier = Modifier.size(36.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        if (index < currentIndex) {
                            Icon(
                                Icons.Default.Check,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onPrimary,
                                modifier = Modifier.size(18.dp),
                            )
                        } else {
                            Text(
                                "${index + 1}",
                                color = if (isActive) MaterialTheme.colorScheme.onPrimary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    step.label,
                    style = MaterialTheme.typography.labelSmall,
                    fontSize = 11.sp,
                    color = if (isActive) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// ===========================================================================================
// Step 1: Customer
// ===========================================================================================

@Composable
private fun CustomerStep(
    query: String,
    results: List<CustomerListItem>,
    isSearching: Boolean,
    selectedCustomer: CustomerListItem?,
    onQueryChange: (String) -> Unit,
    onSelect: (CustomerListItem) -> Unit,
    onClear: () -> Unit,
    showNewCustomerForm: Boolean,
    onToggleNewCustomerForm: () -> Unit,
    newCustFirstName: String,
    newCustLastName: String,
    newCustPhone: String,
    newCustEmail: String,
    isCreatingCustomer: Boolean,
    onNewCustFirstNameChange: (String) -> Unit,
    onNewCustLastNameChange: (String) -> Unit,
    onNewCustPhoneChange: (String) -> Unit,
    onNewCustEmailChange: (String) -> Unit,
    onCreateAndSelect: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Select Customer", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)

        if (selectedCustomer != null) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            buildCustomerName(selectedCustomer),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        if (!selectedCustomer.phone.isNullOrBlank()) {
                            Text(selectedCustomer.phone, style = MaterialTheme.typography.bodySmall)
                        }
                        if (!selectedCustomer.email.isNullOrBlank()) {
                            Text(selectedCustomer.email, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    IconButton(onClick = onClear) {
                        Icon(Icons.Default.Close, contentDescription = "Clear selection")
                    }
                }
            }
        } else {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Search by name, phone, or email...") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    if (isSearching) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                },
                singleLine = true,
            )

            if (results.isNotEmpty()) {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    LazyColumn(modifier = Modifier.heightIn(max = 300.dp)) {
                        items(results, key = { it.id }) { customer ->
                            ListItem(
                                headlineContent = { Text(buildCustomerName(customer)) },
                                supportingContent = {
                                    val info = listOfNotNull(customer.phone, customer.email).joinToString(" | ")
                                    if (info.isNotBlank()) Text(info)
                                },
                                leadingContent = { Icon(Icons.Default.Person, contentDescription = null) },
                                modifier = Modifier.clickable { onSelect(customer) },
                            )
                            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                        }
                    }
                }
            } else if (query.length >= 2 && !isSearching) {
                Text(
                    "No customers found.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Create New Customer expandable section
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onToggleNewCustomerForm() }
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.Add,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp),
                            )
                            Text(
                                "Create New Customer",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }

                    if (showNewCustomerForm) {
                        Column(
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedTextField(
                                value = newCustFirstName,
                                onValueChange = onNewCustFirstNameChange,
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("First Name *") },
                                singleLine = true,
                            )
                            OutlinedTextField(
                                value = newCustLastName,
                                onValueChange = onNewCustLastNameChange,
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("Last Name") },
                                singleLine = true,
                            )
                            OutlinedTextField(
                                value = newCustPhone,
                                onValueChange = onNewCustPhoneChange,
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("Phone *") },
                                singleLine = true,
                            )
                            OutlinedTextField(
                                value = newCustEmail,
                                onValueChange = onNewCustEmailChange,
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("Email") },
                                singleLine = true,
                            )
                            Button(
                                onClick = onCreateAndSelect,
                                modifier = Modifier.fillMaxWidth(),
                                enabled = newCustFirstName.isNotBlank() && newCustPhone.isNotBlank() && !isCreatingCustomer,
                            ) {
                                if (isCreatingCustomer) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(18.dp),
                                        strokeWidth = 2.dp,
                                        color = MaterialTheme.colorScheme.onPrimary,
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                }
                                Text("Create & Select")
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun buildCustomerName(customer: CustomerListItem): String {
    return buildString {
        append(customer.firstName ?: "")
        if (!customer.lastName.isNullOrBlank()) append(" ${customer.lastName}")
    }.ifBlank { "Customer #${customer.id}" }
}

// ===========================================================================================
// Step 2: Category
// ===========================================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryStep(onSelect: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Select Category", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)

        // 3-column grid
        val rows = CATEGORY_TILES.chunked(3)
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            rows.forEach { rowTiles ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    rowTiles.forEach { tile ->
                        BrandCard(
                            onClick = { onSelect(tile.value) },
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 110.dp),
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(12.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center,
                            ) {
                                Text(tile.emoji, fontSize = 32.sp)
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    tile.label,
                                    style = MaterialTheme.typography.labelMedium,
                                    textAlign = TextAlign.Center,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                    // Fill remaining space if row has less than 3 tiles
                    repeat(3 - rowTiles.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

// ===========================================================================================
// Step 3: Device
// ===========================================================================================

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun DeviceStep(
    category: String,
    manufacturers: List<ManufacturerItem>,
    selectedManufacturerId: Long?,
    searchQuery: String,
    searchResults: List<DeviceModelItem>,
    popularDevices: List<DeviceModelItem>,
    isLoading: Boolean,
    customDeviceName: String,
    onManufacturerSelect: (Long?) -> Unit,
    onSearchChange: (String) -> Unit,
    onDeviceSelect: (DeviceModelItem) -> Unit,
    onCustomNameChange: (String) -> Unit,
    onCustomDeviceConfirm: () -> Unit,
) {
    val shortcuts = MANUFACTURER_SHORTCUTS[category] ?: emptyList()

    // CROSS30: add navigationBarsPadding + a trailing Spacer so the
    // "Device not listed?" card at the end of the scroll column clears
    // the gesture nav bar and is never clipped when users scroll to the
    // bottom. The Column already owns .verticalScroll, so padding must be
    // applied OUTSIDE the scroll modifier (otherwise the scroll region
    // eats the inset and the clip returns).
    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Select Device", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)

        // Manufacturer filter chips — CROSS28: trailing contentPadding so the
        // last brand chip isn't clipped flush to the screen edge, giving a
        // visible "row continues" affordance.
        if (shortcuts.isNotEmpty()) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(end = 24.dp),
            ) {
                items(shortcuts, key = { it.label }) { shortcut ->
                    val matchingMfg = manufacturers.firstOrNull { mfg ->
                        shortcut.names.any { name -> mfg.name.contains(name, ignoreCase = true) }
                    }
                    FilterChip(
                        selected = matchingMfg != null && matchingMfg.id == selectedManufacturerId,
                        onClick = { matchingMfg?.let { onManufacturerSelect(it.id) } },
                        label = { Text(shortcut.label, style = MaterialTheme.typography.labelMedium) },
                        enabled = matchingMfg != null,
                    )
                }
            }
        }

        // Search field
        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSearchChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(DEVICE_PLACEHOLDERS[category] ?: "Search device...") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            trailingIcon = {
                if (isLoading) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            },
            singleLine = true,
        )

        // Search results (non-scrollable list, parent is scrollable)
        if (searchResults.isNotEmpty()) {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column {
                    searchResults.take(15).forEachIndexed { index, device ->
                        ListItem(
                            headlineContent = { Text(device.name) },
                            supportingContent = {
                                device.manufacturerName?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                            },
                            trailingContent = {
                                if (device.repairCount > 0) {
                                    Text(
                                        "${device.repairCount} repairs",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            },
                            modifier = Modifier.clickable { onDeviceSelect(device) },
                        )
                        if (index < searchResults.size - 1 && index < 14) {
                            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                        }
                    }
                }
            }
        }

        // Popular device pills — CROSS29: fall back to a brand-mixed order
        // when the server's "Popular" list is dominated by a single brand so
        // new shops (with no ticket history to inform Popular) don't see 15
        // iPhones in a row.
        val displayedPopular = remember(popularDevices) {
            mixBrandsIfMonolithic(popularDevices)
        }
        if (displayedPopular.isNotEmpty() && searchQuery.isBlank()) {
            Text("Popular", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                displayedPopular.forEach { device ->
                    SuggestionChip(
                        onClick = { onDeviceSelect(device) },
                        label = { Text(device.name, style = MaterialTheme.typography.labelMedium) },
                    )
                }
            }
        }

        // Custom device input
        HorizontalDivider(
            modifier = Modifier.padding(vertical = 4.dp),
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
        )
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Text(
                "Device not listed?",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 12.dp, top = 12.dp, end = 12.dp),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = customDeviceName,
                    onValueChange = onCustomNameChange,
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Custom device name") },
                    singleLine = true,
                )
                Button(
                    onClick = onCustomDeviceConfirm,
                    enabled = customDeviceName.isNotBlank(),
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Add")
                }
            }
        }

        // CROSS30: trailing breathing room so the "Device not listed?" card
        // isn't flush with the navigation bar even when no IME is open.
        Spacer(modifier = Modifier.height(16.dp))
    }
}

// ===========================================================================================
// Step 4: Service
// ===========================================================================================

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun ServiceStep(
    services: List<RepairServiceItem>,
    selectedService: RepairServiceItem?,
    priceLookup: RepairPriceLookup?,
    isLoadingPricing: Boolean,
    selectedGrade: RepairPriceGrade?,
    manualPrice: String,
    onServiceSelect: (RepairServiceItem) -> Unit,
    onGradeSelect: (RepairPriceGrade) -> Unit,
    onManualPriceChange: (String) -> Unit,
    onConfirm: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Select Service", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)

        // Service pills
        if (services.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                services.forEach { service ->
                    val isSelected = selectedService?.id == service.id
                    ElevatedFilterChip(
                        selected = isSelected,
                        onClick = { onServiceSelect(service) },
                        label = { Text(service.name) },
                        leadingIcon = if (isSelected) {
                            { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                        } else null,
                    )
                }
            }
        } else {
            Text(
                "No services configured for this category.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Pricing / Grade selector
        if (selectedService != null) {
            HorizontalDivider()

            if (isLoadingPricing) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text("Looking up pricing...", style = MaterialTheme.typography.bodySmall)
                }
            } else if (priceLookup != null && priceLookup.grades.isNotEmpty()) {
                // Grade selector
                Text("Select Grade", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    priceLookup.grades.forEach { grade ->
                        val isSelected = selectedGrade?.id == grade.id
                        Card(
                            onClick = { onGradeSelect(grade) },
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer
                                else MaterialTheme.colorScheme.surface,
                            ),
                            border = if (isSelected) BorderStroke(1.dp, MaterialTheme.colorScheme.primary) else null,
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                RadioButton(
                                    selected = isSelected,
                                    onClick = { onGradeSelect(grade) },
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        grade.gradeLabel ?: grade.grade,
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = FontWeight.Medium,
                                    )
                                    if (grade.inventoryItemName != null) {
                                        Text(
                                            grade.inventoryItemName,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    val totalPrice = grade.effectiveLaborPrice + grade.partPrice
                                    Text(
                                        formatCurrency(totalPrice),
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    val stockColor = if ((grade.inventoryInStock ?: 0) > 0)
                                        SuccessGreen else OutOfStockOrange
                                    val stockText = if ((grade.inventoryInStock ?: 0) > 0)
                                        "In stock (${grade.inventoryInStock})" else "Out of stock"
                                    Text(
                                        stockText,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = stockColor,
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                // No pricing found, manual entry
                Text(
                    "No pricing configured. Enter price manually:",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = manualPrice,
                    onValueChange = onManualPriceChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Price") },
                    prefix = { Text("$") },
                    placeholder = { Text("0.00") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Decimal,
                        imeAction = ImeAction.Next,
                    ),
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Button(
                onClick = onConfirm,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Continue to Details")
            }
        }
    }
}

// ===========================================================================================
// Step 5: Details
// ===========================================================================================

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun DetailsStep(
    state: TicketCreateUiState,
    onImeiChange: (String) -> Unit,
    onSerialChange: (String) -> Unit,
    onSecurityCodeChange: (String) -> Unit,
    onColorChange: (String) -> Unit,
    onNetworkChange: (String) -> Unit,
    onToggleCondition: (String) -> Unit,
    onNotesChange: (String) -> Unit,
    onMacroClick: (String) -> Unit,
    onToggleWarranty: () -> Unit,
    onWarrantyDaysChange: (String) -> Unit,
    onAddToCart: () -> Unit,
) {
    val category = state.selectedCategory ?: "other"
    val deviceName = state.selectedDevice?.name ?: state.customDeviceName
    val serviceName = state.selectedService?.name
    val price = resolveDisplayPrice(state)

    var colorExpanded by remember { mutableStateOf(false) }
    var networkExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Device details", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

        // Summary banner
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        deviceName.ifBlank { "Custom Device" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (serviceName != null) {
                        Text(serviceName, style = MaterialTheme.typography.bodySmall)
                    }
                }
                if (price > 0) {
                    Text(
                        formatCurrency(price),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }

        // IMEI / Serial
        val showImei = category in listOf("phone", "tablet")
        if (showImei) {
            OutlinedTextField(
                value = state.imei,
                onValueChange = onImeiChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("IMEI") },
                singleLine = true,
            )
        }

        OutlinedTextField(
            value = state.serial,
            onValueChange = onSerialChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Serial Number") },
            singleLine = true,
        )

        // Passcode
        OutlinedTextField(
            value = state.securityCode,
            onValueChange = onSecurityCodeChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(PASSCODE_LABELS[category] ?: "Passcode") },
            singleLine = true,
        )

        // Color dropdown
        ExposedDropdownMenuBox(
            expanded = colorExpanded,
            onExpandedChange = { colorExpanded = it },
        ) {
            OutlinedTextField(
                value = state.color,
                onValueChange = onColorChange,
                readOnly = false,
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(),
                label = { Text("Color") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = colorExpanded) },
                singleLine = true,
            )
            ExposedDropdownMenu(
                expanded = colorExpanded,
                onDismissRequest = { colorExpanded = false },
            ) {
                COLOR_OPTIONS.forEach { color ->
                    DropdownMenuItem(
                        text = { Text(color) },
                        onClick = {
                            onColorChange(color)
                            colorExpanded = false
                        },
                    )
                }
            }
        }

        // Network dropdown (phones only)
        if (category == "phone") {
            ExposedDropdownMenuBox(
                expanded = networkExpanded,
                onExpandedChange = { networkExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.network,
                    onValueChange = onNetworkChange,
                    readOnly = false,
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                    label = { Text("Network / Carrier") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = networkExpanded) },
                    singleLine = true,
                )
                ExposedDropdownMenu(
                    expanded = networkExpanded,
                    onDismissRequest = { networkExpanded = false },
                ) {
                    NETWORK_OPTIONS.forEach { net ->
                        DropdownMenuItem(
                            text = { Text(net) },
                            onClick = {
                                onNetworkChange(net)
                                networkExpanded = false
                            },
                        )
                    }
                }
            }
        }

        // Pre-existing conditions
        if (state.conditionChecks.isNotEmpty()) {
            Text(
                "Pre-existing Conditions",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                state.conditionChecks.forEach { check ->
                    val isSelected = check.label in state.selectedConditions
                    FilterChip(
                        selected = isSelected,
                        onClick = { onToggleCondition(check.label) },
                        label = { Text(check.label) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = ConditionAmberBg,
                            selectedLabelColor = ConditionAmberText,
                        ),
                        leadingIcon = if (isSelected) {
                            { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                        } else null,
                    )
                }
            }
        }

        // Notes with quick-issue macros
        Text("Issue / Notes", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium)

        val macros = ISSUE_MACROS[category] ?: ISSUE_MACROS["other"] ?: emptyList()
        if (macros.isNotEmpty()) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(macros) { macro ->
                    AssistChip(
                        onClick = { onMacroClick(macro) },
                        label = { Text(macro, style = MaterialTheme.typography.labelSmall) },
                    )
                }
            }
        }

        OutlinedTextField(
            value = state.notes,
            onValueChange = onNotesChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 100.dp),
            label = { Text("Problem description & notes") },
            placeholder = { Text("What's wrong with the device?") },
            maxLines = 6,
        )

        // Warranty toggle
        HorizontalDivider()
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Warranty", style = MaterialTheme.typography.bodyMedium)
            Switch(
                checked = state.warrantyEnabled,
                onCheckedChange = { onToggleWarranty() },
            )
        }
        if (state.warrantyEnabled) {
            OutlinedTextField(
                value = state.warrantyDays,
                onValueChange = onWarrantyDaysChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Warranty Period (days)") },
                singleLine = true,
            )
        }

        // Add to Cart
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = onAddToCart,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = SuccessGreen,
            ),
        ) {
            Icon(Icons.Default.ShoppingCart, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("Add to Cart")
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

private fun resolveDisplayPrice(state: TicketCreateUiState): Double {
    val gradeLabor = state.selectedGrade?.effectiveLaborPrice
    val gradePart = state.selectedGrade?.partPrice ?: 0.0
    if (gradeLabor != null && gradeLabor > 0) return gradeLabor + gradePart
    val lookupLabor = state.priceLookup?.laborPrice
    if (lookupLabor != null && lookupLabor > 0) return lookupLabor
    return state.manualPrice.toDoubleOrNull() ?: 0.0
}

// ===========================================================================================
// Step 6: Cart
// ===========================================================================================

@Composable
private fun CartStep(
    cartItems: List<RepairCartItem>,
    taxRate: Double,
    isSubmitting: Boolean,
    onRemoveItem: (String) -> Unit,
    onAddAnother: () -> Unit,
    onSubmit: () -> Unit,
) {
    val subtotal = cartItems.sumOf { it.lineTotal }
    val tax = subtotal * taxRate
    val total = subtotal + tax
    // @audit-fixed: was String.format("%.3f", ...) without Locale, which produces
    // a comma decimal separator on EU locales (e.g. "8,865") and visually breaks
    // the "%" suffix. Pinning to Locale.US matches the rest of the screen which
    // uses formatCurrency() under Locale.US.
    val taxPercent = String.format(Locale.US, "%.3f", taxRate * 100)

    // Delete confirmation dialog state
    var itemToDelete by remember { mutableStateOf<RepairCartItem?>(null) }

    if (itemToDelete != null) {
        AlertDialog(
            onDismissRequest = { itemToDelete = null },
            title = { Text("Remove Item") },
            text = { Text("Remove ${itemToDelete!!.deviceName} from the cart?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRemoveItem(itemToDelete!!.id)
                        itemToDelete = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("Remove")
                }
            },
            dismissButton = {
                TextButton(onClick = { itemToDelete = null }) {
                    Text("Cancel")
                }
            },
        )
    }

    Column(
        modifier = Modifier.fillMaxSize(),
    ) {
        // Scrollable items section
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Cart", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)

            if (cartItems.isEmpty()) {
                // Empty cart state with centered icon and message
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        Icons.Default.ShoppingCart,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                    )
                    Text(
                        "No items yet",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "Go back to add a device.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    FilledTonalButton(onClick = onAddAnother) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Add a Device")
                    }
                }
            } else {
                cartItems.forEach { item ->
                    BrandCard(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    item.deviceName,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                if (item.serviceName != null) {
                                    Text(
                                        item.serviceName,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (item.imei.isNotBlank()) {
                                    Text("IMEI: ${item.imei}", style = MaterialTheme.typography.bodySmall)
                                }
                                if (item.serial.isNotBlank()) {
                                    Text("Serial: ${item.serial}", style = MaterialTheme.typography.bodySmall)
                                }
                                if (item.notes.isNotBlank()) {
                                    Text(
                                        item.notes,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                                if (item.parts.isNotEmpty()) {
                                    item.parts.forEach { part ->
                                        Text(
                                            "  + ${part.name}: ${formatCurrency(part.price)}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    formatCurrency(item.lineTotal),
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                IconButton(
                                    onClick = { itemToDelete = item },
                                    modifier = Modifier.size(32.dp),
                                ) {
                                    Icon(
                                        Icons.Default.Delete,
                                        contentDescription = "Remove",
                                        tint = MaterialTheme.colorScheme.error,
                                        modifier = Modifier.size(20.dp),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Sticky bottom section: totals + action buttons
        if (cartItems.isNotEmpty()) {
            HorizontalDivider()
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Subtotal", style = MaterialTheme.typography.bodyMedium)
                    Text(formatCurrency(subtotal), style = MaterialTheme.typography.bodyMedium)
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Tax ($taxPercent%)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(formatCurrency(tax), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                HorizontalDivider()
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Total", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(
                        formatCurrency(total),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                FilledTonalButton(
                    onClick = onAddAnother,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Add Another Device")
                }

                Button(
                    onClick = onSubmit,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isSubmitting,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = SuccessGreen,
                    ),
                ) {
                    if (isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text("Create Ticket")
                }
            }
        }
    }
}
