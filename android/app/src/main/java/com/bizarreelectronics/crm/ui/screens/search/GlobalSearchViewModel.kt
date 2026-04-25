package com.bizarreelectronics.crm.ui.screens.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.InventoryDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.AppointmentApi
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.api.SearchApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.util.CurrencyFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Domain models
// ---------------------------------------------------------------------------

data class SearchResult(
    val type: String,          // customer | ticket | invoice | inventory | employee | appointment | lead | sms
    val id: Long,
    val secondaryKey: String? = null, // for sms: phone number (route key)
    val title: String,
    val subtitle: String,
)

data class SavedQuery(
    val id: String,            // UUID string
    val name: String,
    val query: String,
)

data class GlobalSearchUiState(
    val query: String = "",
    val results: Map<String, List<SearchResult>> = emptyMap(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val hasSearched: Boolean = false,
    val isOnline: Boolean = true,
    // §18.1 recent searches (max 10, LRU)
    val recentSearches: List<String> = emptyList(),
    // item 8 — saved/pinned queries
    val savedQueries: List<SavedQuery> = emptyList(),
    val showSaveQueryDialog: Boolean = false,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@OptIn(FlowPreview::class)
@HiltViewModel
class GlobalSearchViewModel @Inject constructor(
    private val searchApi: SearchApi,
    private val ticketApi: TicketApi,
    private val customerApi: CustomerApi,
    private val invoiceApi: InvoiceApi,
    private val inventoryApi: InventoryApi,
    private val settingsApi: SettingsApi,
    private val leadApi: LeadApi,
    private val appointmentApi: AppointmentApi,
    private val smsApi: SmsApi,
    private val serverMonitor: ServerReachabilityMonitor,
    private val ticketDao: TicketDao,
    private val customerDao: CustomerDao,
    private val inventoryDao: InventoryDao,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        GlobalSearchUiState(
            recentSearches = appPreferences.recentSearches,
            savedQueries = loadSavedQueries(),
        ),
    )
    val state = _state.asStateFlow()

    private val _queryFlow = MutableStateFlow("")

    init {
        viewModelScope.launch {
            serverMonitor.isEffectivelyOnline.collect { online ->
                _state.value = _state.value.copy(isOnline = online)
            }
        }
        viewModelScope.launch {
            _queryFlow
                .debounce(300L)
                .distinctUntilChanged()
                .filter { it.isNotBlank() }
                .collectLatest { query -> performSearch(query) }
        }
    }

    // ── Query management ──────────────────────────────────────────────────

    fun updateQuery(value: String) {
        _state.value = _state.value.copy(query = value)
        _queryFlow.value = value
        if (value.isBlank()) {
            _state.value = _state.value.copy(
                results = emptyMap(),
                hasSearched = false,
                error = null,
            )
        }
    }

    /** Bypass debounce — fires immediately (IME Search key, voice result). */
    fun executeSearch() {
        val q = _state.value.query.trim()
        if (q.isBlank()) return
        viewModelScope.launch { performSearch(q) }
    }

    // ── Recents ───────────────────────────────────────────────────────────

    fun onRecentTapped(query: String) {
        updateQuery(query)
        executeSearch()
    }

    fun clearRecentSearches() {
        appPreferences.clearRecentSearches()
        _state.value = _state.value.copy(recentSearches = emptyList())
    }

    // ── Saved / pinned queries (item 8) ───────────────────────────────────

    fun requestSaveCurrentQuery() {
        if (_state.value.query.isBlank()) return
        _state.value = _state.value.copy(showSaveQueryDialog = true)
    }

    fun dismissSaveQueryDialog() {
        _state.value = _state.value.copy(showSaveQueryDialog = false)
    }

    fun saveQuery(name: String) {
        val q = _state.value.query.trim()
        if (q.isBlank() || name.isBlank()) return
        val entry = SavedQuery(
            id = java.util.UUID.randomUUID().toString(),
            name = name.trim(),
            query = q,
        )
        val updated = _state.value.savedQueries + entry
        persistSavedQueries(updated)
        _state.value = _state.value.copy(
            savedQueries = updated,
            showSaveQueryDialog = false,
        )
    }

    fun removeSavedQuery(id: String) {
        val updated = _state.value.savedQueries.filterNot { it.id == id }
        persistSavedQueries(updated)
        _state.value = _state.value.copy(savedQueries = updated)
    }

    fun onSavedQueryTapped(saved: SavedQuery) {
        updateQuery(saved.query)
        executeSearch()
    }

    // ── Core search ───────────────────────────────────────────────────────

    private suspend fun performSearch(query: String) {
        _state.value = _state.value.copy(isLoading = true, error = null)
        val online = serverMonitor.isEffectivelyOnline.value
        if (online) {
            runCatching { performOnlineSearch(query) }
                .onFailure { performOfflineSearch(query) }
        } else {
            performOfflineSearch(query)
        }
    }

    private suspend fun performOnlineSearch(query: String) = coroutineScope {
        // 1. Unified /search endpoint for the core 4 entity types.
        val unifiedDeferred = async {
            runCatching { searchApi.globalSearch(query).data }.getOrNull()
        }

        // 2. APIs that don't accept ?q — client-side filter on a capped batch.
        //    TODO: Phase 2 — add ?q server-side for appointments and leads.
        val leadsDeferred = async {
            runCatching {
                leadApi.getLeads(mapOf("keyword" to query)).data?.leads
                    ?.take(50)
                    ?.filter { item ->
                        val haystack = listOfNotNull(
                            item.firstName, item.lastName, item.email, item.phone,
                            item.orderId, item.status,
                        ).joinToString(" ")
                        haystack.contains(query, ignoreCase = true)
                    }
                    ?.take(5)
            }.getOrNull()
        }

        val appointmentsDeferred = async {
            runCatching {
                appointmentApi.getAppointments().data
                    ?.take(50)
                    ?.filter { item ->
                        val haystack = listOfNotNull(
                            item.title, item.customerName, item.employeeName,
                            item.status, item.type, item.notes,
                        ).joinToString(" ")
                        haystack.contains(query, ignoreCase = true)
                    }
                    ?.take(5)
            }.getOrNull()
        }

        val employeesDeferred = async {
            runCatching { settingsApi.searchEmployees(query).data?.take(5) }.getOrNull()
        }

        val smsDeferred = async {
            runCatching { smsApi.getConversations(keyword = query).data?.conversations?.take(5) }.getOrNull()
        }

        val unifiedData = unifiedDeferred.await()
        val leadsData = leadsDeferred.await()
        val appointmentsData = appointmentsDeferred.await()
        val employeesData = employeesDeferred.await()
        val smsData = smsDeferred.await()

        val grouped = linkedMapOf<String, List<SearchResult>>()

        if (unifiedData != null) {
            parseUnifiedMap(unifiedData)?.forEach { (type, list) ->
                if (list.isNotEmpty()) grouped[type] = list
            }
        } else {
            // Unified failed — fan out for core 4
            coroutineScope {
                val ticketsD = async {
                    runCatching {
                        ticketApi.getTickets(mapOf("q" to query, "limit" to "5")).data?.tickets
                    }.getOrNull()
                }
                val customersD = async {
                    runCatching { customerApi.searchCustomers(query).data?.take(5) }.getOrNull()
                }
                val invoicesD = async {
                    runCatching {
                        invoiceApi.getInvoices(mapOf("q" to query, "limit" to "5")).data?.invoices
                    }.getOrNull()
                }
                val inventoryD = async {
                    runCatching {
                        inventoryApi.getItems(mapOf("q" to query, "limit" to "5")).data?.items
                    }.getOrNull()
                }

                ticketsD.await()?.map { t ->
                    SearchResult(
                        type = "ticket", id = t.id,
                        title = t.orderId.ifBlank { "T-${t.id}" },
                        subtitle = listOfNotNull(t.status?.name, t.customer?.fullName)
                            .filter { it.isNotBlank() }.joinToString(" - ").ifBlank { "Ticket" },
                    )
                }?.takeIf { it.isNotEmpty() }?.let { grouped["ticket"] = it }

                customersD.await()?.map { c ->
                    val name = listOfNotNull(c.firstName, c.lastName).joinToString(" ").trim()
                        .ifBlank { "Customer #${c.id}" }
                    SearchResult(
                        type = "customer", id = c.id, title = name,
                        subtitle = listOfNotNull(
                            (c.phone ?: c.mobile)?.let { formatPhoneDisplay(it) }?.takeIf { it.isNotBlank() },
                            c.email,
                        ).joinToString(" | ").ifBlank { "No contact info" },
                    )
                }?.takeIf { it.isNotEmpty() }?.let { grouped["customer"] = it }

                invoicesD.await()?.map { inv ->
                    SearchResult(
                        type = "invoice", id = inv.id,
                        title = inv.orderId ?: "INV-${inv.id}",
                        subtitle = listOfNotNull(
                            inv.status?.ifBlank { null },
                            inv.total?.let { CurrencyFormatter.format(it) },
                            inv.customerName.ifBlank { null },
                        ).joinToString(" - ").ifBlank { "Invoice" },
                    )
                }?.takeIf { it.isNotEmpty() }?.let { grouped["invoice"] = it }

                inventoryD.await()?.map { item ->
                    SearchResult(
                        type = "inventory", id = item.id,
                        title = item.name ?: "Item #${item.id}",
                        subtitle = listOfNotNull(
                            item.sku?.let { "SKU: $it" },
                            item.inStock?.let { "Stock: $it" },
                        ).joinToString(" | ").ifBlank { "Inventory item" },
                    )
                }?.takeIf { it.isNotEmpty() }?.let { grouped["inventory"] = it }
            }
        }

        employeesData?.map { emp ->
            SearchResult(
                type = "employee", id = emp.id,
                title = listOfNotNull(emp.firstName, emp.lastName).joinToString(" ")
                    .ifBlank { emp.username ?: "Employee #${emp.id}" },
                subtitle = listOfNotNull(emp.role, emp.email).joinToString(" | ").ifBlank { "Employee" },
            )
        }?.takeIf { it.isNotEmpty() }?.let { grouped["employee"] = it }

        leadsData?.map { lead ->
            SearchResult(
                type = "lead", id = lead.id,
                title = listOfNotNull(lead.firstName, lead.lastName).joinToString(" ")
                    .ifBlank { lead.orderId ?: "Lead #${lead.id}" },
                subtitle = listOfNotNull(lead.status, lead.email, lead.phone)
                    .joinToString(" | ").ifBlank { "Lead" },
            )
        }?.takeIf { it.isNotEmpty() }?.let { grouped["lead"] = it }

        // Appointments — no detail route; tapping navigates to appointment list
        appointmentsData?.map { appt ->
            SearchResult(
                type = "appointment", id = appt.id,
                title = appt.title ?: "Appointment #${appt.id}",
                subtitle = listOfNotNull(appt.customerName, appt.startTime, appt.status)
                    .joinToString(" | ").ifBlank { "Appointment" },
            )
        }?.takeIf { it.isNotEmpty() }?.let { grouped["appointment"] = it }

        // SMS threads — routed by phone, not numeric id
        smsData?.map { conv ->
            val customerLabel = conv.customer?.let {
                listOfNotNull(it.firstName, it.lastName).joinToString(" ")
                    .ifBlank { it.phone ?: it.mobile ?: "" }
            }
            SearchResult(
                type = "sms", id = 0L,
                secondaryKey = conv.convPhone,
                title = customerLabel?.ifBlank { null } ?: formatPhoneDisplay(conv.convPhone),
                subtitle = conv.lastMessage?.take(80) ?: "No messages",
            )
        }?.takeIf { it.isNotEmpty() }?.let { grouped["sms"] = it }

        appPreferences.addRecentSearch(query)
        _state.value = _state.value.copy(
            results = grouped,
            isLoading = false,
            hasSearched = true,
            recentSearches = appPreferences.recentSearches,
        )
    }

    private suspend fun performOfflineSearch(query: String) {
        try {
            val grouped = linkedMapOf<String, List<SearchResult>>()

            customerDao.search(query).firstOrNull()?.map { c ->
                val name = listOfNotNull(c.firstName, c.lastName).joinToString(" ").trim()
                    .ifBlank { "Customer #${c.id}" }
                SearchResult(
                    type = "customer", id = c.id, title = name,
                    subtitle = listOfNotNull(
                        (c.phone ?: c.mobile)?.let { formatPhoneDisplay(it) }?.takeIf { it.isNotBlank() },
                        c.email,
                    ).joinToString(" | ").ifBlank { "No contact info" },
                )
            }?.takeIf { it.isNotEmpty() }?.let { grouped["customer"] = it }

            ticketDao.search(query).firstOrNull()?.map { t ->
                SearchResult(
                    type = "ticket", id = t.id,
                    title = t.orderId.ifBlank { "T-${t.id}" },
                    subtitle = listOfNotNull(t.statusName, t.customerName)
                        .filter { it.isNotBlank() }.joinToString(" - ").ifBlank { "Ticket" },
                )
            }?.takeIf { it.isNotEmpty() }?.let { grouped["ticket"] = it }

            inventoryDao.search(query).firstOrNull()?.map { i ->
                SearchResult(
                    type = "inventory", id = i.id,
                    title = i.name.ifBlank { "Item #${i.id}" },
                    subtitle = listOfNotNull(
                        i.sku?.let { "SKU: $it" },
                        "Stock: ${i.inStock}",
                    ).joinToString(" | ").ifBlank { "Inventory item" },
                )
            }?.takeIf { it.isNotEmpty() }?.let { grouped["inventory"] = it }

            appPreferences.addRecentSearch(query)
            _state.value = _state.value.copy(
                results = grouped,
                isLoading = false,
                hasSearched = true,
                recentSearches = appPreferences.recentSearches,
            )
        } catch (e: Exception) {
            _state.value = _state.value.copy(
                isLoading = false,
                error = e.message ?: "Search failed",
                hasSearched = true,
            )
        }
    }

    // ── Unified search endpoint parser ────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun parseUnifiedMap(data: Map<String, Any>): LinkedHashMap<String, List<SearchResult>>? {
        val result = linkedMapOf<String, List<SearchResult>>()
        fun parseSection(key: String, type: String) {
            val raw = data[key] as? List<*> ?: return
            val items = raw.mapNotNull { item ->
                val map = item as? Map<String, Any> ?: return@mapNotNull null
                val id = when (val rid = map["id"]) {
                    is Number -> rid.toLong()
                    is String -> rid.toLongOrNull()
                    else -> null
                } ?: return@mapNotNull null
                val title: String
                val subtitle: String
                when (type) {
                    "customer" -> {
                        val first = map["first_name"]?.toString().orEmpty()
                        val last = map["last_name"]?.toString().orEmpty()
                        title = "$first $last".trim().ifBlank { "Customer #$id" }
                        val phone = (map["phone"]?.toString() ?: map["mobile"]?.toString())
                            ?.let { formatPhoneDisplay(it) }?.takeIf { it.isNotBlank() }
                        subtitle = listOfNotNull(phone, map["email"]?.toString())
                            .joinToString(" | ").ifBlank { "No contact info" }
                    }
                    "ticket" -> {
                        title = map["order_id"]?.toString() ?: "T-$id"
                        val status = map["status_name"]?.toString() ?: map["status"]?.toString() ?: ""
                        subtitle = listOf(status, map["customer_name"]?.toString() ?: "")
                            .filter { it.isNotBlank() }.joinToString(" - ").ifBlank { "Ticket" }
                    }
                    "inventory" -> {
                        title = map["name"]?.toString() ?: "Item #$id"
                        subtitle = listOfNotNull(
                            map["sku"]?.toString()?.let { "SKU: $it" },
                            map["in_stock"]?.toString()?.let { "Stock: $it" },
                        ).joinToString(" | ").ifBlank { "Inventory item" }
                    }
                    "invoice" -> {
                        title = map["order_id"]?.toString() ?: "INV-$id"
                        subtitle = listOfNotNull(
                            map["status"]?.toString()?.ifBlank { null },
                            (map["total"] as? Number)?.toDouble()?.let { CurrencyFormatter.format(it) },
                        ).joinToString(" - ").ifBlank { "Invoice" }
                    }
                    else -> {
                        title = map["name"]?.toString() ?: "#$id"
                        subtitle = type
                    }
                }
                SearchResult(type = type, id = id, title = title, subtitle = subtitle)
            }
            if (items.isNotEmpty()) result[type] = items
        }
        parseSection("customers", "customer")
        parseSection("tickets", "ticket")
        parseSection("invoices", "invoice")
        parseSection("inventory", "inventory")
        return result.ifEmpty { null }
    }

    // ── Saved queries persistence via AppPreferences ──────────────────────

    private fun loadSavedQueries(): List<SavedQuery> =
        appPreferences.deserializeSavedQueries(appPreferences.rawSavedQueries)
            .map { (id, name, query) -> SavedQuery(id = id, name = name, query = query) }

    private fun persistSavedQueries(queries: List<SavedQuery>) {
        val triples = queries.map { Triple(it.id, it.name, it.query) }
        appPreferences.rawSavedQueries = appPreferences.serializeSavedQueries(triples)
    }
}
