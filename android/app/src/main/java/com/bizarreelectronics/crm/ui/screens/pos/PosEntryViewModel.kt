package com.bizarreelectronics.crm.ui.screens.pos

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

data class PosEntryUiState(
    val attachedCustomer: PosAttachedCustomer? = null,
    val searchQuery: String = "",
    val searchResults: SearchResultGroup = SearchResultGroup(),
    val isSearching: Boolean = false,
    val recentActivities: List<String> = emptyList(),
    val readyForPickupTickets: List<ReadyForPickupTicket> = emptyList(),
    val pastRepairs: List<PastRepair> = emptyList(),
    val errorMessage: String? = null,
)

@HiltViewModel
class PosEntryViewModel @Inject constructor(
    private val customerApi: CustomerApi,
    private val coordinator: PosCoordinator,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosEntryUiState())
    val uiState: StateFlow<PosEntryUiState> = _uiState.asStateFlow()

    private val _rawQuery = MutableStateFlow("")

    init {
        wireSearchDebounce()
    }

    @OptIn(FlowPreview::class)
    private fun wireSearchDebounce() {
        viewModelScope.launch {
            _rawQuery
                .debounce(300)
                .distinctUntilChanged()
                .collect { q -> if (q.isNotBlank()) runSearch(q) else clearResults() }
        }
    }

    fun onQueryChange(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        _rawQuery.value = query
    }

    fun attachWalkIn() {
        val walkIn = PosAttachedCustomer(id = 0L, name = "Walk-in customer")
        coordinator.attachCustomer(walkIn)
        _uiState.update { it.copy(attachedCustomer = walkIn) }
    }

    fun attachExistingCustomer(c: CustomerListItem) {
        val attached = PosAttachedCustomer(
            id = c.id,
            name = listOfNotNull(c.firstName, c.lastName).joinToString(" ").ifBlank { "Customer #${c.id}" },
            phone = c.phone ?: c.mobile,
            email = c.email,
            ticketCount = c.ticketCount ?: 0,
        )
        coordinator.attachCustomer(attached)
        _uiState.update {
            it.copy(
                attachedCustomer = attached,
                searchQuery = "",
                searchResults = SearchResultGroup(),
            )
        }
        loadCustomerHistory(c.id)
    }

    fun createCustomerAndAttach(firstName: String, lastName: String?, phone: String?, email: String?) {
        viewModelScope.launch {
            runCatching {
                customerApi.createCustomer(
                    CreateCustomerRequest(
                        firstName = firstName,
                        lastName = lastName,
                        phone = phone,
                        email = email,
                    )
                )
            }.onSuccess { resp ->
                val detail = resp.data ?: return@onSuccess
                val attached = PosAttachedCustomer(
                    id = detail.id,
                    name = listOfNotNull(detail.firstName, detail.lastName).joinToString(" ").ifBlank { "New customer" },
                    phone = detail.phone ?: detail.mobile,
                    email = detail.email,
                )
                coordinator.attachCustomer(attached)
                _uiState.update { it.copy(attachedCustomer = attached, searchQuery = "", searchResults = SearchResultGroup()) }
            }.onFailure { e ->
                _uiState.update { it.copy(errorMessage = "Could not create customer: ${e.message}") }
            }
        }
    }

    fun openReadyForPickup(ticketId: Long) {
        coordinator.setLinkedTicket(ticketId)
    }

    fun clearError() = _uiState.update { it.copy(errorMessage = null) }

    private fun runSearch(query: String) {
        _uiState.update { it.copy(isSearching = true) }
        viewModelScope.launch {
            val customers = runCatching { customerApi.searchCustomers(query) }
                .getOrNull()?.data
                ?.map { c ->
                    CustomerResult(
                        id = c.id,
                        name = listOfNotNull(c.firstName, c.lastName).joinToString(" ").ifBlank { "Customer #${c.id}" },
                        phone = c.phone ?: c.mobile,
                        email = c.email,
                        ticketCount = c.ticketCount ?: 0,
                    )
                } ?: emptyList()

            _uiState.update {
                it.copy(
                    isSearching = false,
                    searchResults = SearchResultGroup(customers = customers),
                )
            }
        }
    }

    private fun clearResults() {
        _uiState.update { it.copy(searchResults = SearchResultGroup(), isSearching = false) }
    }

    private fun loadCustomerHistory(customerId: Long) {
        viewModelScope.launch {
            runCatching { customerApi.getTickets(customerId, pageSize = 5) }
                .getOrNull()?.data?.tickets?.let { tickets ->
                    val repairs = tickets.map { t ->
                        PastRepair(
                            ticketId = t.id,
                            description = t.firstDevice?.deviceName ?: "Ticket #${t.id}",
                            date = t.createdAt?.take(10) ?: "",
                            amountCents = ((t.total ?: 0.0) * 100).toLong(),
                        )
                    }
                    _uiState.update { it.copy(pastRepairs = repairs) }
                }
        }
    }
}
