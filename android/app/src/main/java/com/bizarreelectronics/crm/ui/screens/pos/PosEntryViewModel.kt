package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
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
    // AUDIT-006: default tax rate loaded on init so openReadyForPickup can
    // seed the CartLine with the correct rate rather than leaving it at 0.0.
    val defaultTaxRate: Double = 0.0,
)

@HiltViewModel
class PosEntryViewModel @Inject constructor(
    private val customerApi: CustomerApi,
    private val inventoryApi: InventoryApi,
    private val coordinator: PosCoordinator,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosEntryUiState())
    val uiState: StateFlow<PosEntryUiState> = _uiState.asStateFlow()

    private val _rawQuery = MutableStateFlow("")

    init {
        wireSearchDebounce()
        // AUDIT-006: pre-load the default tax rate so openReadyForPickup can
        // seed the CartLine.taxRate — same logic as PosCartViewModel.init.
        viewModelScope.launch {
            runCatching { inventoryApi.getTaxClasses() }
                .onSuccess { resp ->
                    val classes = resp.data.orEmpty()
                    val ratePercent = classes.firstOrNull { it.isDefault == 1 }?.rate
                        ?: classes.firstOrNull()?.rate
                        ?: 0.0
                    _uiState.update { it.copy(defaultTaxRate = ratePercent / 100.0) }
                }
        }
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
        loadStoreCredit(c.id)
    }

    /**
     * Search-result tap path. Avoids re-parsing the display name back into
     * firstName/lastName (which corrupted compound surnames like 'Mc Donald'
     * — see commit 6926fb80 where the substringBefore/After split lost the
     * second word). Builds the PosAttachedCustomer directly so the original
     * server-supplied fields propagate verbatim.
     */
    fun attachFromSearchResult(result: CustomerResult) {
        val attached = PosAttachedCustomer(
            id = result.id,
            name = result.name.ifBlank { "Customer #${result.id}" },
            phone = result.phone,
            email = result.email,
            ticketCount = result.ticketCount,
        )
        coordinator.attachCustomer(attached)
        _uiState.update {
            it.copy(
                attachedCustomer = attached,
                searchQuery = "",
                searchResults = SearchResultGroup(),
            )
        }
        loadCustomerHistory(result.id)
        loadStoreCredit(result.id)
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
                loadStoreCredit(detail.id)
            }.onFailure { e ->
                _uiState.update { it.copy(errorMessage = "Could not create customer: ${e.message}") }
            }
        }
    }

    /**
     * Mockup PHONE 1 hero behaviour: tapping a Ready-for-pickup row seeds a
     * single-line cart at the ticket's due amount and skips straight to the
     * tender screen so the cashier can collect payment without re-typing the
     * total. We don't try to re-hydrate every part / labor row here — the
     * customer already approved the quote at check-in time, so the relevant
     * artefact is the outstanding balance, not the line breakdown.
     *
     * AUDIT-005: attaches the customer carried on the ticket so the tender
     * screen shows the customer name and store-credit balance even when the
     * cashier reaches this path without manually attaching via search.
     * AUDIT-006: seeds CartLine.taxRate from the loaded default so the
     * Tender screen's total reflects real tax math (previously always 0.0).
     */
    fun openReadyForPickup(ticketId: Long) {
        coordinator.setLinkedTicket(ticketId)
        val ticket = _uiState.value.readyForPickupTickets.firstOrNull { it.ticketId == ticketId }
        if (ticket != null) {
            // AUDIT-005: attach the customer if not already attached or if
            // the attached customer differs from the ticket's owner.
            val currentCustomer = coordinator.session.value.customer
            if (ticket.customerId > 0L &&
                (currentCustomer == null || currentCustomer.id != ticket.customerId)
            ) {
                val customer = PosAttachedCustomer(
                    id = ticket.customerId,
                    name = ticket.customerName.ifBlank { "Customer #${ticket.customerId}" },
                )
                coordinator.attachCustomer(customer)
                _uiState.update { it.copy(attachedCustomer = customer) }
            }
            // AUDIT-006: apply the pre-loaded default tax rate to the line.
            val taxRate = _uiState.value.defaultTaxRate
            coordinator.setLines(
                listOf(
                    CartLine(
                        type = "custom",
                        itemId = null,
                        name = "Ticket #${ticket.orderId} · ${ticket.deviceName}",
                        unitPriceCents = ticket.dueCents,
                        taxRate = taxRate,
                    )
                )
            )
        }
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

    private fun loadStoreCredit(customerId: Long) {
        viewModelScope.launch {
            val cents = runCatching { customerApi.getStoreCredit(customerId) }
                .getOrNull()?.data?.amountCents ?: 0L
            _uiState.update { s ->
                val existing = s.attachedCustomer ?: return@update s
                if (existing.id != customerId) return@update s
                val updated = existing.copy(storeCreditCents = cents)
                coordinator.attachCustomer(updated)
                s.copy(attachedCustomer = updated)
            }
        }
    }

    private fun loadCustomerHistory(customerId: Long) {
        viewModelScope.launch {
            // Mockup PHONE 1 post-attach renders two buckets side-by-side:
            // a green "Ready for pickup" hero for open+ready tickets, and a
            // compact "Past repairs" list for closed+non-cancelled ones.
            // Pull a single page (size 20) and partition client-side so we
            // don't need two round-trips.
            val tickets = runCatching { customerApi.getTickets(customerId, pageSize = 20) }
                .getOrNull()?.data?.tickets
                ?: return@launch

            // AUDIT-005: capture the customer name at map time so
            // openReadyForPickup can attach without an extra API call.
            val customerName = _uiState.value.attachedCustomer?.name.orEmpty()
            val ready = tickets.filter { t ->
                val name = t.statusName?.lowercase().orEmpty()
                val isClosed = (t.status?.isClosed ?: 0) == 1
                val isCancelled = (t.status?.isCancelled ?: 0) == 1
                !isClosed && !isCancelled &&
                    (name.contains("ready") || name.contains("pickup"))
            }.map { t ->
                ReadyForPickupTicket(
                    ticketId = t.id,
                    orderId = t.orderId,
                    deviceName = t.firstDevice?.deviceName ?: "Ticket #${t.id}",
                    // Prefer the unpaid-balance aggregate (POS-DUE-001) so the
                    // hero card reflects what the customer still owes after
                    // any deposit they paid at check-in. Falls back to gross
                    // total when the JOIN returned no row (legacy tickets
                    // without an invoice attached).
                    dueCents = Math.round((t.amountDue ?: t.total ?: 0.0) * 100),
                    customerId = customerId,
                    customerName = customerName,
                )
            }

            val past = tickets.filter { t ->
                val isClosed = (t.status?.isClosed ?: 0) == 1
                val isCancelled = (t.status?.isCancelled ?: 0) == 1
                isClosed && !isCancelled
            }.take(5).map { t ->
                PastRepair(
                    ticketId = t.id,
                    description = t.firstDevice?.deviceName ?: "Ticket #${t.id}",
                    date = t.createdAt?.take(10) ?: "",
                    amountCents = Math.round((t.total ?: 0.0) * 100),
                )
            }

            _uiState.update {
                it.copy(readyForPickupTickets = ready, pastRepairs = past)
            }
        }
    }
}
