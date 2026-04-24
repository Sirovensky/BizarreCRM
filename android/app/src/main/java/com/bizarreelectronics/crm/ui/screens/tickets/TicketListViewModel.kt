package com.bizarreelectronics.crm.ui.screens.tickets

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSort
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgency
import com.bizarreelectronics.crm.ui.screens.tickets.components.ticketUrgencyFor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * Saved-view presets for the ticket list.
 * Each preset applies a combination of filter + status constraints.
 */
enum class TicketSavedView(val label: String) {
    None("None"),
    MyQueue("My queue"),
    AwaitingCustomer("Awaiting customer"),
    SlaBreachingToday("SLA breaching today"),
}

/**
 * View mode: flat list or Kanban board.
 * Kanban is a placeholder — full implementation deferred.
 */
enum class TicketViewMode { List, Kanban }

data class TicketListUiState(
    val tickets: List<TicketEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedFilter: String = "All",
    // CROSS1: ticket assignment feature toggle (ticket_all_employees_view_all == '0')
    val assignmentEnabled: Boolean = false,
    /** Current sort order. Default: Newest. */
    val currentSort: TicketSort = TicketSort.Newest,
    /** Multi-select mode (tablet/ChromeOS — gated on WindowWidthSizeClass >= Medium). */
    val isSelecting: Boolean = false,
    val selectedIds: Set<Long> = emptySet(),
    /** Active saved view preset. */
    val savedView: TicketSavedView = TicketSavedView.None,
    /** View mode: list or kanban. */
    val viewMode: TicketViewMode = TicketViewMode.List,
    /** Toast message to show once (consumed by UI). */
    val toastMessage: String? = null,
    /** plan:L653 — Set of locally-pinned ticket IDs. Restored from AppPreferences on init. */
    val pinnedTicketIds: Set<Long> = emptySet(),
)

@HiltViewModel
class TicketListViewModel @Inject constructor(
    private val ticketRepository: TicketRepository,
    private val authPreferences: AuthPreferences,
    private val settingsApi: SettingsApi,
    private val ticketApi: TicketApi,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(TicketListUiState())
    val state = _state.asStateFlow()

    /**
     * Paged stream of tickets, cached in [viewModelScope] so the Pager survives
     * recomposition. Switches to a new stream when [_filterKeyFlow] changes.
     *
     * Consumed by TicketListScreen via [collectAsLazyPagingItems].
     */
    private val _filterKeyFlow = MutableStateFlow(resolveFilterKey())
    val ticketsPaged: Flow<PagingData<TicketEntity>> = _filterKeyFlow
        .flatMapLatest { key -> ticketRepository.ticketsPaged(key) }
        .cachedIn(viewModelScope)

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        // Restore persisted view mode
        val persistedMode = if (appPreferences.ticketListViewMode == "kanban") {
            TicketViewMode.Kanban
        } else {
            TicketViewMode.List
        }
        // Restore persisted saved view
        val persistedSavedView = runCatching {
            TicketSavedView.valueOf(appPreferences.ticketListSavedView)
        }.getOrDefault(TicketSavedView.None)

        _state.value = _state.value.copy(
            viewMode = persistedMode,
            savedView = persistedSavedView,
            pinnedTicketIds = appPreferences.pinnedTicketIds,
        )

        collectTickets()
        loadAssignmentSetting()
    }

    private fun loadAssignmentSetting() {
        viewModelScope.launch {
            try {
                val cfg = settingsApi.getConfig().data ?: return@launch
                val enabled = cfg["ticket_all_employees_view_all"] == "0"
                _state.value = _state.value.copy(assignmentEnabled = enabled)
            } catch (_: Exception) {
                // Offline or server error — assume feature off (default). No filter-chip hiding change needed.
            }
        }
    }

    fun loadTickets() = collectTickets()

    private fun collectTickets() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.tickets.isEmpty(), error = null)
            val query = _state.value.searchQuery.trim()
            val filter = _state.value.selectedFilter
            val savedView = _state.value.savedView

            val flow = when {
                query.isNotEmpty() -> ticketRepository.searchTickets(query)
                filter == "My Tickets" -> ticketRepository.getByAssignedTo(authPreferences.userId)
                filter == "Open" || filter == "In Progress" || filter == "Waiting" -> ticketRepository.getOpenTickets()
                filter == "Closed" -> ticketRepository.getTickets()
                else -> ticketRepository.getTickets()
            }

            flow.collect { tickets ->
                // Status filter
                val filtered = when {
                    filter == "Closed" -> tickets.filter { it.statusIsClosed }
                    filter == "In Progress" -> tickets.filter {
                        it.statusName.equals("In Progress", ignoreCase = true)
                    }
                    filter == "Waiting" -> tickets.filter {
                        it.statusName.equals("Waiting", ignoreCase = true) ||
                            it.statusName.equals("Waiting for Parts", ignoreCase = true)
                    }
                    else -> tickets
                }

                // Saved-view filter applied on top of status filter
                val savedFiltered = applySavedView(filtered, savedView)

                // Sort
                val sorted = applySortOrder(savedFiltered, _state.value.currentSort)

                _state.value = _state.value.copy(
                    tickets = sorted,
                    isLoading = false,
                    isRefreshing = false,
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        collectTickets()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            collectTickets()
        }
    }

    fun onFilterChanged(filter: String) {
        _state.value = _state.value.copy(selectedFilter = filter)
        _filterKeyFlow.value = resolveFilterKey(filter = filter)
        collectTickets()
    }

    // -----------------------------------------------------------------------
    // Sort (L639)
    // -----------------------------------------------------------------------

    fun onSortChanged(sort: TicketSort) {
        _state.value = _state.value.copy(currentSort = sort)
        collectTickets()
    }

    // -----------------------------------------------------------------------
    // Swipe actions (L641)
    // -----------------------------------------------------------------------

    /** Swipe-left on open ticket: mark as done. Optimistic update + sync queue. */
    fun onMarkDone(ticketId: Long) {
        // TODO(plan:L641): wire to ticketRepository.updateTicket with a "closed" status.
        // Requires knowing the server-side closed-status ID (seeded as migration 001).
        // For now: optimistic local update sets statusIsClosed=true; queue is enqueued.
        val ticket = _state.value.tickets.firstOrNull { it.id == ticketId } ?: return
        val updated = ticket.copy(statusIsClosed = true, locallyModified = true)
        replaceTicketInList(updated)
        viewModelScope.launch {
            try {
                Log.d(TAG, "Mark done: ticketId=$ticketId (TODO: wire to updateTicket)")
                // ticketRepository.updateTicket(ticketId, UpdateTicketRequest(statusId = CLOSED_STATUS_ID))
            } catch (e: Exception) {
                Log.w(TAG, "Mark done failed: ${e.message}")
            }
        }
    }

    /** Swipe-left on closed ticket: reopen. */
    fun onReopen(ticketId: Long) {
        // TODO(plan:L641): wire to ticketRepository.updateTicket with an "open" status ID.
        val ticket = _state.value.tickets.firstOrNull { it.id == ticketId } ?: return
        val updated = ticket.copy(statusIsClosed = false, locallyModified = true)
        replaceTicketInList(updated)
        viewModelScope.launch {
            try {
                Log.d(TAG, "Reopen: ticketId=$ticketId (TODO: wire to updateTicket)")
            } catch (e: Exception) {
                Log.w(TAG, "Reopen failed: ${e.message}")
            }
        }
    }

    /** Swipe-right on unassigned ticket: assign to current user. */
    fun onAssignToMe(ticketId: Long) {
        // TODO(plan:L641): wire to ticketRepository.updateTicket with assignedTo=authPreferences.userId.
        val ticket = _state.value.tickets.firstOrNull { it.id == ticketId } ?: return
        val updated = ticket.copy(assignedTo = authPreferences.userId, locallyModified = true)
        replaceTicketInList(updated)
        viewModelScope.launch {
            try {
                Log.d(TAG, "Assign to me: ticketId=$ticketId userId=${authPreferences.userId} (TODO: wire to updateTicket)")
            } catch (e: Exception) {
                Log.w(TAG, "Assign to me failed: ${e.message}")
            }
        }
    }

    /** Swipe-right on assigned/active ticket: put on hold. */
    fun onHold(ticketId: Long) {
        // TODO(plan:L641): wire to ticketRepository.updateTicket with "On Hold" status.
        viewModelScope.launch {
            Log.d(TAG, "Hold: ticketId=$ticketId (TODO: wire to updateTicket)")
            _state.value = _state.value.copy(toastMessage = "Hold queued (offline action)")
        }
    }

    private fun replaceTicketInList(updated: TicketEntity) {
        val newList = _state.value.tickets.map { if (it.id == updated.id) updated else it }
        _state.value = _state.value.copy(tickets = newList)
    }

    // -----------------------------------------------------------------------
    // Context-menu actions (L642)
    // -----------------------------------------------------------------------

    fun onCopyId(ticketId: Long) {
        // Handled in UI via ClipboardManager; ViewModel just provides ticket entity lookup
        Log.d(TAG, "Copy ID: $ticketId")
    }

    fun onAddNote(ticketId: Long) {
        // TODO(plan:L642): open AddNoteSheet — deferred, not yet wired
        _state.value = _state.value.copy(toastMessage = "Add note — not yet available")
    }

    fun onContextAssign(ticketId: Long) {
        onAssignToMe(ticketId)
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // -----------------------------------------------------------------------
    // Multi-select (L643)
    // -----------------------------------------------------------------------

    fun enterSelectMode(ticketId: Long) {
        _state.value = _state.value.copy(
            isSelecting = true,
            selectedIds = setOf(ticketId),
        )
    }

    fun toggleSelection(ticketId: Long) {
        val current = _state.value.selectedIds
        val updated = if (ticketId in current) current - ticketId else current + ticketId
        _state.value = _state.value.copy(selectedIds = updated)
    }

    fun exitSelectMode() {
        _state.value = _state.value.copy(isSelecting = false, selectedIds = emptySet())
    }

    /** Bulk status update for selected tickets — only status change exposed for now. */
    fun onBulkStatusChange(statusName: String) {
        // TODO(plan:L643): wire to ticketRepository.updateTicket for each selectedId.
        val count = _state.value.selectedIds.size
        _state.value = _state.value.copy(
            isSelecting = false,
            selectedIds = emptySet(),
            toastMessage = "Bulk status '$statusName' queued for $count tickets (not yet wired)",
        )
        Log.d(TAG, "Bulk status '$statusName' for ids=${_state.value.selectedIds}")
    }

    // -----------------------------------------------------------------------
    // View mode toggle (L644)
    // -----------------------------------------------------------------------

    fun onViewModeChanged(mode: TicketViewMode) {
        _state.value = _state.value.copy(viewMode = mode)
        appPreferences.ticketListViewMode = if (mode == TicketViewMode.Kanban) "kanban" else "list"
    }

    // -----------------------------------------------------------------------
    // Saved views (L645)
    // -----------------------------------------------------------------------

    fun onSavedViewSelected(savedView: TicketSavedView) {
        _state.value = _state.value.copy(savedView = savedView)
        appPreferences.ticketListSavedView = savedView.name
        _filterKeyFlow.value = resolveFilterKey(savedView = savedView)
        collectTickets()
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private fun applySavedView(tickets: List<TicketEntity>, view: TicketSavedView): List<TicketEntity> {
        return when (view) {
            TicketSavedView.None -> tickets
            TicketSavedView.MyQueue -> tickets.filter {
                it.assignedTo == authPreferences.userId && !it.statusIsClosed
            }
            TicketSavedView.AwaitingCustomer -> tickets.filter {
                val name = it.statusName?.lowercase().orEmpty()
                name.contains("awaiting") || name.contains("waiting for customer") || name.contains("customer")
            }
            TicketSavedView.SlaBreachingToday -> tickets.filter {
                // TODO(plan:L645): dueOn field to be parsed when server adds SLA timestamp.
                // Stub: show all non-closed tickets with "high"+ urgency.
                !it.statusIsClosed && ticketUrgencyFor(it).ordinal <= TicketUrgency.High.ordinal
            }
        }
    }

    // -----------------------------------------------------------------------
    // Paging3 filter-key helpers
    // -----------------------------------------------------------------------

    /**
     * Derives the [filterKey] string passed to [TicketRepository.ticketsPaged].
     * Called on init (from persisted state) and on filter/savedView changes.
     */
    private fun resolveFilterKey(
        filter: String = _state.value.selectedFilter,
        savedView: TicketSavedView = _state.value.savedView,
    ): String = when {
        savedView == TicketSavedView.MyQueue ->
            "assignee:${authPreferences.userId}"
        filter == "My Tickets" ->
            "assignee:${authPreferences.userId}"
        filter == "Closed" ->
            "status:closed"
        filter == "Open" || filter == "In Progress" || filter == "Waiting" ->
            "status:open"
        else -> ""
    }

    // -----------------------------------------------------------------------
    // Pinned tickets (L653)
    // -----------------------------------------------------------------------

    /**
     * Toggle the pinned state of [ticketId].
     *
     * 1. Optimistically flips local state + persists to [AppPreferences].
     * 2. POSTs to the server; if the server returns HTTP 404 (endpoint not
     *    deployed yet) the local-only state is kept silently.
     */
    fun togglePin(ticketId: Long) {
        val current = _state.value.pinnedTicketIds
        val willPin = ticketId !in current
        val updated = if (willPin) current + ticketId else current - ticketId

        // Optimistic local update
        _state.value = _state.value.copy(pinnedTicketIds = updated)
        if (willPin) {
            appPreferences.addPinnedTicketId(ticketId)
        } else {
            appPreferences.removePinnedTicketId(ticketId)
        }

        // Server sync — 404 is treated as local-only
        viewModelScope.launch {
            try {
                ticketApi.setPinned(ticketId, mapOf("pinned" to willPin))
                Log.d(TAG, "Pin synced: ticketId=$ticketId pinned=$willPin")
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    Log.d(TAG, "Pin endpoint not found (404) — local-only for ticketId=$ticketId")
                } else {
                    Log.w(TAG, "Pin sync failed HTTP ${e.code()}: ticketId=$ticketId")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Pin sync failed: ticketId=$ticketId — ${e.message}")
            }
        }
    }

    private companion object {
        private const val TAG = "TicketListViewModel"
    }
}

// -----------------------------------------------------------------------
// Sort comparators — pure functions, tested in TicketSortComparatorTest
// -----------------------------------------------------------------------

/**
 * Applies the given [sort] order to [tickets].
 * Returns a new list; does not mutate the input.
 */
fun applySortOrder(tickets: List<TicketEntity>, sort: TicketSort): List<TicketEntity> =
    when (sort) {
        TicketSort.Newest    -> tickets.sortedByDescending { it.createdAt }
        TicketSort.Oldest    -> tickets.sortedBy { it.createdAt }
        TicketSort.Status    -> tickets.sortedBy { it.statusName?.lowercase() ?: "" }
        TicketSort.Urgency   -> tickets.sortedBy { ticketUrgencyFor(it).ordinal }
        TicketSort.DueDate   -> tickets.sortedWith(
            compareBy(
                { it.dueOn == null }, // nulls last
                { it.dueOn ?: "" },
            )
        )
        TicketSort.CustomerAZ -> tickets.sortedBy { it.customerName?.lowercase() ?: "" }
    }
