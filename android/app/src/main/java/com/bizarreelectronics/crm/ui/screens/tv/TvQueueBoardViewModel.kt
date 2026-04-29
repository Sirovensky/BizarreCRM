package com.bizarreelectronics.crm.ui.screens.tv

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.DashboardApi
import com.bizarreelectronics.crm.data.remote.api.TvQueueItem
import com.bizarreelectronics.crm.service.WebSocketService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * §3.13 L565–L567 — ViewModel for [TvQueueBoardScreen].
 *
 * Fetches `GET /tv/queue` via [DashboardApi.getTvQueue] and groups the
 * result by status into [TvQueueUiState.groups]. HTTP 404 means the
 * server does not yet expose the endpoint; the ViewModel demotes the
 * failure to an empty list so the screen shows the "Connect TV mode"
 * empty-state rather than an error.
 *
 * All other errors (network, 5xx) surface via [TvQueueUiState.error]
 * so the screen can display a transient message while the periodic
 * refresh loop continues.
 *
 * ## §56.5 WebSocket live updates
 * Subscribes to [WebSocketService.events] in [viewModelScope]. When the
 * server emits `ticket:created`, `ticket:updated`, or
 * `ticket:status_changed` the ViewModel calls [refresh] immediately so
 * the board re-animates on the next frame without waiting for the
 * 30-second polling interval.
 */
@HiltViewModel
class TvQueueBoardViewModel @Inject constructor(
    private val dashboardApi: DashboardApi,
    private val webSocketService: WebSocketService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(TvQueueUiState())
    val uiState: StateFlow<TvQueueUiState> = _uiState.asStateFlow()

    /** Kick off the first load immediately when the ViewModel is created. */
    init {
        refresh()
        subscribeWebSocket()
    }

    /**
     * §56.5 — Subscribe to WebSocket ticket events so the board re-animates
     * immediately when a ticket status changes, without waiting for the 30-second
     * polling interval in [TvQueueBoardScreen].
     *
     * Only ticket-mutation events trigger a refresh; noise events (pong, sms, etc.)
     * are ignored so we do not thrash the endpoint on busy shops.
     */
    private fun subscribeWebSocket() {
        viewModelScope.launch {
            webSocketService.events.collect { event ->
                when (event.type) {
                    "ticket:created", "ticket:updated", "ticket:status_changed" -> {
                        Log.d(TAG, "WS ${event.type} — refreshing TV queue")
                        refresh()
                    }
                    else -> { /* not relevant to TV queue */ }
                }
            }
        }
    }

    /**
     * Fetch the TV queue from the server and update [uiState].
     *
     * 404 → empty groups (server not yet live).
     * Other HTTP / IO errors → [TvQueueUiState.error] set; previous groups retained.
     */
    fun refresh() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                val response = dashboardApi.getTvQueue()
                val items = response.data?.items ?: emptyList()
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    groups = groupByStatus(items),
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Endpoint not yet live — show empty state with instructions.
                    Log.d(TAG, "GET /tv/queue returned 404 — endpoint not live yet")
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        groups = emptyMap(),
                    )
                } else {
                    Log.w(TAG, "GET /tv/queue HTTP ${e.code()}: ${e.message()}")
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = "Server error (${e.code()}). Retrying…",
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "GET /tv/queue failed: ${e.message}")
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = "Connection error. Retrying…",
                )
            }
        }
    }

    /** Group a flat item list into an ordered map keyed by [TvQueueGroup]. */
    private fun groupByStatus(items: List<TvQueueItem>): Map<TvQueueGroup, List<TvQueueItem>> {
        val result = linkedMapOf<TvQueueGroup, MutableList<TvQueueItem>>()
        // Preserve display order: In Progress → Awaiting → Ready.
        TvQueueGroup.entries.forEach { result[it] = mutableListOf() }
        items.forEach { item ->
            val group = TvQueueGroup.fromStatus(item.status)
            result.getOrPut(group) { mutableListOf() }.add(item)
        }
        return result.mapValues { (_, v) -> v.toList() }
    }

    companion object {
        private const val TAG = "TvQueueBoardViewModel"
    }
}

/**
 * UI state for [TvQueueBoardScreen].
 *
 * @property isLoading True during the first fetch and each subsequent refresh.
 * @property groups    Tickets grouped by [TvQueueGroup], in display order.
 *                     Empty map when the endpoint returns 404 or no tickets.
 * @property error     Non-null when the last refresh failed (non-404). The
 *                     screen shows this transiently while the loop continues.
 */
data class TvQueueUiState(
    val isLoading: Boolean = true,
    val groups: Map<TvQueueGroup, List<TvQueueItem>> = emptyMap(),
    val error: String? = null,
) {
    /** True when there are no tickets across all groups and the endpoint is live. */
    val isEmpty: Boolean get() = !isLoading && groups.values.all { it.isEmpty() }
}

/**
 * Display groups for the TV queue board, in the order they appear on screen.
 *
 * @property label Human-readable section heading shown on the TV board.
 */
enum class TvQueueGroup(val label: String) {
    IN_PROGRESS("In Progress"),
    AWAITING("Awaiting"),
    READY("Ready for Pickup");

    companion object {
        /**
         * Map the raw `status` string from the server to a [TvQueueGroup].
         * Unknown statuses fall into [AWAITING] so they are never silently lost.
         */
        fun fromStatus(status: String): TvQueueGroup = when (status) {
            "in_progress" -> IN_PROGRESS
            "ready"       -> READY
            else          -> AWAITING
        }
    }
}
