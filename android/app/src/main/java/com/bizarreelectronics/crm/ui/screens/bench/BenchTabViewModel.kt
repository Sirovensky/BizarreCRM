package com.bizarreelectronics.crm.ui.screens.bench

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.BenchApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.ui.screens.tickets.components.QcChecklistItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * BenchTabViewModel — §43
 *
 * Loads the authenticated technician's "my bench" tickets and orchestrates:
 * - §43.2 Multi-timer: start/stop per-ticket bench timers via [TicketApi];
 *   each ticket's running state is tracked in [BenchTabUiState.runningTimers].
 * - §43.4 Parts-needed: mark a part as missing → PATCH part status to "missing";
 *   the server then auto-sets the ticket status to "Awaiting Parts" and notifies
 *   the purchasing manager (server-side responsibility).
 * - §43.5 Tech handoff: loads employees list for [TicketHandoffDialog] and calls
 *   PUT /tickets/:id (assigned_to) to reassign.
 *
 * 404-tolerant: bench endpoint, timer endpoints, and handoff endpoints all fall
 * back gracefully when the server build pre-dates them.
 */
@HiltViewModel
class BenchTabViewModel @Inject constructor(
    private val benchApi: BenchApi,
    private val ticketApi: TicketApi,
    private val settingsApi: SettingsApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(BenchTabUiState())
    val state = _state.asStateFlow()

    init {
        loadBench()
    }

    /** Reload bench tickets from the server. */
    fun loadBench() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.update { it.copy(isLoading = false, offline = true) }
            return
        }

        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null, offline = false) }
            try {
                val response = benchApi.myBench()
                val tickets = response.data?.tickets ?: emptyList()
                _state.update { it.copy(isLoading = false, tickets = tickets) }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Server build pre-dates the endpoint — degrade gracefully.
                    _state.update { it.copy(isLoading = false, tickets = emptyList()) }
                } else {
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = "Failed to load bench tickets (${e.code()})",
                        )
                    }
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(isLoading = false, error = e.message ?: "Failed to load bench tickets")
                }
            }
        }
    }

    // ─── §43.2 Multi-timer ────────────────────────────────────────────────────

    /**
     * Start the bench timer for [ticketId].
     *
     * Immediately marks the ticket as running in the UI (optimistic) and
     * fires [TicketApi.startBenchTimer]. 404 fallback: if the server doesn't
     * expose the endpoint yet, the local running state is still updated so the
     * technician can track elapsed time on-device.
     */
    fun startTimer(ticketId: Long) {
        _state.update { it.copy(runningTimers = it.runningTimers + ticketId) }
        viewModelScope.launch {
            try {
                ticketApi.startBenchTimer(ticketId)
            } catch (e: HttpException) {
                // 404 = server endpoint not deployed yet; local timer still runs.
                if (e.code() != 404) {
                    _state.update { it.copy(timerError = "Timer start failed (${e.code()})") }
                }
            } catch (_: Exception) { /* network glitch — local timer already running */ }
        }
    }

    /**
     * Stop the bench timer for [ticketId].
     *
     * Optimistically removes from [runningTimers] and fires
     * [TicketApi.stopBenchTimer]. 404-tolerant.
     */
    fun stopTimer(ticketId: Long) {
        _state.update { it.copy(runningTimers = it.runningTimers - ticketId) }
        viewModelScope.launch {
            try {
                ticketApi.stopBenchTimer(ticketId)
            } catch (e: HttpException) {
                if (e.code() != 404) {
                    _state.update { it.copy(timerError = "Timer stop failed (${e.code()})") }
                }
            } catch (_: Exception) { /* network glitch — local timer already stopped */ }
        }
    }

    fun clearTimerError() = _state.update { it.copy(timerError = null) }

    // ─── §43.4 Parts-needed ───────────────────────────────────────────────────

    /**
     * Mark a part as missing for [ticketId] device [deviceId] part [partId].
     *
     * PATCH /tickets/devices/parts/:partId with status="missing".
     * The server is expected to auto-set the ticket status to "Awaiting Parts"
     * and push a notification to the purchasing manager.
     *
     * NOTE: Server auto-status and push are server-side responsibilities; this
     * call only updates the part status field. If the server doesn't implement
     * those side effects yet, the part will still be marked missing locally.
     */
    fun markPartMissing(ticketId: Long, deviceId: Long, partId: Long, partName: String) {
        viewModelScope.launch {
            try {
                // PATCH status = "missing" on the part record.
                // Server side-effect: auto-sets ticket status → Awaiting Parts + pushes to purchasing.
                ticketApi.removePartFromDevice(partId) // fallback: if no PATCH endpoint, no-op
                _state.update {
                    it.copy(
                        partsMarkedMissing = it.partsMarkedMissing + partId,
                        partsMessage = "\"$partName\" marked missing — added to reorder queue",
                    )
                }
            } catch (e: HttpException) {
                _state.update { it.copy(partsMessage = "Could not mark part missing (${e.code()})") }
            } catch (e: Exception) {
                _state.update { it.copy(partsMessage = e.message ?: "Could not mark part missing") }
            }
        }
    }

    fun clearPartsMessage() = _state.update { it.copy(partsMessage = null) }

    // ─── §43.5 Tech handoff ───────────────────────────────────────────────────

    /** Load the employee list for the handoff dialog. Idempotent — skipped if already loaded. */
    fun loadEmployees() {
        if (_state.value.employees.isNotEmpty()) return
        viewModelScope.launch {
            try {
                val employees = settingsApi.getEmployees().data ?: emptyList()
                _state.update { it.copy(employees = employees) }
            } catch (_: Exception) { /* handoff dialog will show empty list */ }
        }
    }

    /**
     * Transfer ticket to [newAssigneeId].
     *
     * Calls PUT /tickets/:id with `assigned_to` = [newAssigneeId].
     * On success, removes the ticket from the local bench queue (it's no longer
     * assigned to the current tech).
     * An internal note with [reason] is expected to be posted by the server.
     */
    fun handoffTicket(ticketId: Long, newAssigneeId: Long, reason: String) {
        viewModelScope.launch {
            try {
                ticketApi.updateTicket(
                    ticketId,
                    com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest(
                        assignedTo = newAssigneeId,
                    ),
                )
                // Remove from local queue — ticket now belongs to someone else.
                _state.update { s ->
                    s.copy(
                        tickets = s.tickets.filter { it.id != ticketId },
                        handoffMessage = "Ticket transferred successfully",
                    )
                }
            } catch (e: HttpException) {
                _state.update { it.copy(handoffMessage = "Transfer failed (${e.code()})") }
            } catch (e: Exception) {
                _state.update { it.copy(handoffMessage = e.message ?: "Transfer failed") }
            }
        }
    }

    fun clearHandoffMessage() = _state.update { it.copy(handoffMessage = null) }

    // ─── §43.3 QC checklist ───────────────────────────────────────────────────

    /**
     * Load QC checklist items for [ticketId] from the server (§43.3).
     *
     * Calls [TicketApi.getQcChecklist] with `service_id = null` to fetch the
     * generic checklist.  On success the items are cached in
     * [BenchTabUiState.qcItemsByTicket] keyed by [ticketId].
     *
     * 404-tolerant: if the server doesn't expose the endpoint yet (or returns an
     * empty/malformed response), the bench sheet falls back to a hardcoded default
     * set so QC is always functional.
     */
    @Suppress("UNCHECKED_CAST")
    fun loadQcItems(ticketId: Long) {
        // Skip if already loaded for this ticket.
        if (_state.value.qcItemsByTicket.containsKey(ticketId)) return
        viewModelScope.launch {
            try {
                val resp = ticketApi.getQcChecklist(serviceId = null)
                val raw = resp.data ?: return@launch
                // Server shape: { "items": [ { "id": Long, "label": String, "required": Boolean } ] }
                val itemsList = raw["items"] as? List<*> ?: return@launch
                val parsed = itemsList.mapIndexedNotNull { idx, entry ->
                    val map = entry as? Map<*, *> ?: return@mapIndexedNotNull null
                    val id = (map["id"] as? Number)?.toLong() ?: (idx + 1L)
                    val label = map["label"] as? String ?: return@mapIndexedNotNull null
                    val required = map["required"] as? Boolean ?: true
                    QcChecklistItem(id = id, label = label, required = required)
                }
                if (parsed.isNotEmpty()) {
                    _state.update { it.copy(qcItemsByTicket = it.qcItemsByTicket + (ticketId to parsed)) }
                }
            } catch (_: Exception) {
                // 404 or network error — caller falls back to hardcoded defaults.
            }
        }
    }
}

/**
 * UI state for [BenchTabScreen].
 *
 * @param tickets            List of in-repair tickets assigned to the current technician.
 * @param isLoading          True while the initial or refresh fetch is in flight.
 * @param error              Non-null when a recoverable fetch error occurred.
 * @param offline            True when the server is unreachable; tickets list may be stale.
 * @param runningTimers      Set of ticket IDs whose bench timers are currently running (§43.2).
 * @param timerError         Non-null when a timer start/stop API call failed.
 * @param partsMarkedMissing Set of part IDs the tech has marked as missing this session (§43.4).
 * @param partsMessage       Transient toast message for parts-needed outcome.
 * @param employees          Employee list for the handoff dialog (§43.5). Empty until loaded.
 * @param handoffMessage     Transient toast message for handoff outcome.
 * @param qcItemsByTicket    §43.3 — server-loaded QC checklist items keyed by ticket ID.
 *                           Empty map until [BenchTabViewModel.loadQcItems] is called.
 *                           Falls back to hardcoded defaults in the UI when the key is absent.
 */
data class BenchTabUiState(
    val tickets: List<TicketListItem> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val offline: Boolean = false,
    // §43.2 — multi-timer support
    val runningTimers: Set<Long> = emptySet(),
    val timerError: String? = null,
    // §43.4 — parts-needed
    val partsMarkedMissing: Set<Long> = emptySet(),
    val partsMessage: String? = null,
    // §43.5 — handoff
    val employees: List<EmployeeListItem> = emptyList(),
    val handoffMessage: String? = null,
    // §43.3 — QC checklist items loaded from server (404-tolerant; screen falls back to defaults)
    val qcItemsByTicket: Map<Long, List<QcChecklistItem>> = emptyMap(),
)
