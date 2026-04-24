package com.bizarreelectronics.crm.ui.screens.checkin.entry

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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

data class EntryStep2State(
    val deviceModel: String = "",
    val imeiSerial: String = "",
    val notes: String = "",
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
        val updatedRecent = (_step1.value.recent + entry)
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
    }

    fun detachCustomer() {
        _step1.update { it.copy(attachedCustomer = null) }
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
                val updatedRecent = (_step1.value.recent + entry)
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
