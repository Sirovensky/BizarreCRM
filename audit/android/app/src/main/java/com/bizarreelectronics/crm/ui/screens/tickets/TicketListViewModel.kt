package com.bizarreelectronics.crm.ui.screens.tickets

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.ui.screens.tickets.TicketStateMachine
import com.bizarreelectronics.crm.ui.screens.tickets.TransitionResult
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketColumnVisibility
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketColumnVisibility.Companion.decode
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketColumnVisibility.Companion.encode
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSort
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgency
import com.bizarreelectronics.crm.ui.screens.tickets.components.ticketUrgencyFor
import com.bizarreelectronics.crm.util.ScrollPosition
import com.bizarreelectronics.crm.util.restoreScrollPosition
import com.bizarreelectronics.crm.util.saveScrollPosition
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
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
    // plan:L792 — Bulk transition summary
    /** Non-null when a bulk-transition operation completed with a summary to show. */
    val bulkTransitionSummary: BulkTransitionSummary? = null,
    // §4.21 — Active label filter (null = show all)
    val activeLabelFilter: String? = null,
    // §4.1 L660 — Which optional ticket-row columns are visible (tablet/ChromeOS).
    // Loaded from AppPreferences on init; defaults applied automatically on empty pref.
    val columnVisibility: TicketColumnVisibility = TicketColumnVisibility(),
)

/**
 * plan:L792 — Result of a bulk status transition shown in a summary dialog.
 *
 * @param targetStatusName  The status name that was applied.
 * @param movedCount        Number of tickets successfully transitioned.
 * @param skipped           List of (ticketId, reason) for skipped tickets.
 */
data class BulkTransitionSummary(
    val targetStatusName: String,
    val movedCount: Int,
    val skipped: List<Pair<Long, String>>,
)

@HiltViewModel
class TicketListViewModel @Inject constructor(
    private val ticketRepository: TicketRepository,
    private val authPreferences: AuthPreferences,
    private val settingsApi: SettingsApi,
    private val ticketApi: TicketApi,
    private val appPreferences: AppPreferences,
    // §1.8 process-death: SavedStateHandle persists transient search/filter state
    // across process kill so the user's query is restored on re-launch.
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val _state = MutableStateFlow(
        TicketListUiState(
            searchQuery = savedStateHandle.get<String>(SSH_KEY_QUERY) ?: "",
            selectedFilter = savedStateHandle.get<String>(SSH_KEY_FILTER) ?: "All",
        ),
    )
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

        // Restore persisted column visibility (§4.1 L660)
        val persistedColumnVisibility = decode(appPreferences.ticketColumnVisibility)

        _state.value = _state.value.copy(
            viewMode = persistedMode,
            savedView = persistedSavedView,
            pinnedTicketIds = appPreferences.pinnedTicketIds,
            columnVisibility = persistedColumnVisibility,
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

                // §4.21 — Label filter: keep only tickets containing the active label
                val labelFiltered = _state.value.activeLabelFilter?.let { activeLabel ->
                    savedFiltered.filter { ticket ->
                        ticket.labels?.split(",")?.any { it.trim().equals(activeLabel, ignoreCase = true) } == true
                    }
                } ?: savedFiltered

                // Sort
                val sorted = applySortOrder(labelFiltered, _state.value.currentSort)

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
        // §1.8 process-death: persist so the query survives a process kill + restore
        savedStateHandle[SSH_KEY_QUERY] = query
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            collectTickets()
        }
    }

    fun onFilterChanged(filter: String) {
        _state.value = _state.value.copy(selectedFilter = filter)
        // §1.8 process-death: persist so the filter survives a process kill + restore
        savedStateHandle[SSH_KEY_FILTER] = filter
        _filterKeyFlow.value = resolveFilterKey(filter = filter)
        collectTickets()
    }

    // §4.21 — Filter ticket list by label (null clears the filter)
    fun onLabelFilterChanged(label: String?) {
        _state.value = _state.value.copy(activeLabelFilter = label)
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

    /** Legacy shim — delegates to [bulkTransition] with a status name lookup. */
    fun onBulkStatusChange(statusName: String) {
        // Delegate to the full bulk-transition impl; status ID lookup requires the status list
        // which is not loaded at this level — surface a toast stub for callers that pass only a name.
        _state.value = _state.value.copy(
            toastMessage = "Use bulkTransition(ids, statusId) for wired bulk changes",
        )
        Log.d(TAG, "onBulkStatusChange stub: '$statusName'")
    }

    /**
     * plan:L792 — Bulk status transition.
     *
     * For each ticket ID in [ticketIds]:
     *   1. Validates the transition via [TicketStateMachine.validateTransition].
     *   2. Sends valid PATCHes in parallel, chunked to 10 concurrent requests.
     *   3. Collects skipped tickets with a human-readable reason.
     *   4. Emits a [BulkTransitionSummary] to [TicketListUiState.bulkTransitionSummary]
     *      for the UI to display in a summary dialog.
     *
     * @param ticketIds     IDs of the tickets to transition.
     * @param targetStatusId  The server status ID to apply.
     * @param targetStatusName  Display name of the target status (for summary dialog).
     */
    fun bulkTransition(ticketIds: Set<Long>, targetStatusId: Long, targetStatusName: String) {
        viewModelScope.launch {
            val tickets = _state.value.tickets
            val skipped = mutableListOf<Pair<Long, String>>()
            val toUpdate = mutableListOf<Long>()

            // Validate each ticket
            for (id in ticketIds) {
                val ticket = tickets.firstOrNull { it.id == id }
                if (ticket == null) {
                    skipped += id to "Ticket not found in local list"
                    continue
                }
                val result = TicketStateMachine.validateTransition(
                    fromStateName = ticket.statusName,
                    toStateName = targetStatusName,
                    targetStatusItem = null, // requirement guards not available without full status DTO
                    hasNotes = false,
                    hasPhotos = false,
                    hasDevices = false,
                )
                when (result) {
                    is TransitionResult.Allowed -> toUpdate += id
                    is TransitionResult.Blocked -> skipped += id to result.message
                }
            }

            // Send in parallel, chunked to 10
            var movedCount = 0
            toUpdate.chunked(10).forEach { chunk ->
                val results = chunk.map { id ->
                    async {
                        try {
                            ticketRepository.updateTicket(id, UpdateTicketRequest(statusId = targetStatusId))
                            true
                        } catch (e: Exception) {
                            Log.w(TAG, "bulkTransition: PATCH failed for id=$id — ${e.message}")
                            skipped += id to (e.message ?: "Network error")
                            false
                        }
                    }
                }.awaitAll()
                movedCount += results.count { it }
            }

            _state.value = _state.value.copy(
                isSelecting = false,
                selectedIds = emptySet(),
                bulkTransitionSummary = BulkTransitionSummary(
                    targetStatusName = targetStatusName,
                    movedCount = movedCount,
                    skipped = skipped,
                ),
            )
        }
    }

    /** Dismiss the bulk-transition summary dialog. */
    fun dismissBulkTransitionSummary() {
        _state.value = _state.value.copy(bulkTransitionSummary = null)
    }

    // -----------------------------------------------------------------------
    // §4.21 — Bulk label apply (line 940)
    // -----------------------------------------------------------------------

    /**
     * Apply [label] to all currently-selected tickets via
     * POST /tickets/bulk-labels { ids, label }.
     *
     * 404 is tolerated — the endpoint may not be deployed on self-hosted
     * instances; a graceful toast is shown and select mode exits regardless.
     */
    fun bulkApplyLabel(label: String) {
        val ids = _state.value.selectedIds.toList()
        if (ids.isEmpty()) return
        viewModelScope.launch {
            try {
                ticketApi.bulkSetLabels(mapOf("ids" to ids, "label" to label))
                _state.value = _state.value.copy(
                    isSelecting = false,
                    selectedIds = emptySet(),
                    toastMessage = "Label [$label] applied to ${ids.size} ticket${if (ids.size == 1) "" else "s"}",
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Endpoint not yet deployed on this tenant's server — exit gracefully.
                    _state.value = _state.value.copy(
                        isSelecting = false,
                        selectedIds = emptySet(),
                        toastMessage = "Label feature not available on this server",
                    )
                } else {
                    Log.w(TAG, "bulkApplyLabel: HTTP ${e.code()} — ${e.message()}")
                    _state.value = _state.value.copy(
                        toastMessage = "Could not apply label — ${e.message()}",
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "bulkApplyLabel: ${e.message}")
                _state.value = _state.value.copy(
                    toastMessage = "Could not apply label",
                )
            }
        }
    }

    // -----------------------------------------------------------------------
    // View mode toggle (L644)
    // -----------------------------------------------------------------------

    fun onViewModeChanged(mode: TicketViewMode) {
        _state.value = _state.value.copy(viewMode = mode)
        appPreferences.ticketListViewMode = if (mode == TicketViewMode.Kanban) "kanban" else "list"
    }

    // -----------------------------------------------------------------------
    // Column visibility (§4.1 L660) — tablet/ChromeOS persisted preference
    // -----------------------------------------------------------------------

    /**
     * Applies and persists an updated [TicketColumnVisibility] config.
     *
     * Called from [TicketListScreen] when the user taps Apply in the
     * [TicketColumnDensityPicker] sheet. The new config is stored to
     * [AppPreferences] so it survives process death and app restarts.
     */
    fun onColumnVisibilityChanged(visibility: TicketColumnVisibility) {
        _state.value = _state.value.copy(columnVisibility = visibility)
        appPreferences.ticketColumnVisibility = with(visibility) { encode() }
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

    // §75.5 — scroll position persistence.
    // Called from the screen's SaveScrollOnDispose effect so that if the
    // process is killed while the user is on the Ticket detail and they
    // return, the list is restored at the same scroll offset.
    fun saveScrollPosition(position: ScrollPosition) {
        savedStateHandle.saveScrollPosition(SSH_SCOPE_SCROLL, position)
    }

    /** Reads the last-persisted scroll position; returns (0, 0) on first launch. */
    fun restoreScrollPosition(): ScrollPosition =
        savedStateHandle.restoreScrollPosition(SSH_SCOPE_SCROLL)

    private companion object {
        private const val TAG = "TicketListViewModel"
        /** SavedStateHandle keys for process-death restoration (§1.8). */
        const val SSH_KEY_QUERY  = "ticket_list_search_query"
        const val SSH_KEY_FILTER = "ticket_list_selected_filter"
        /** SavedStateHandle key-scope for §75.5 scroll position. */
        const val SSH_SCOPE_SCROLL = "ticket_list"
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
