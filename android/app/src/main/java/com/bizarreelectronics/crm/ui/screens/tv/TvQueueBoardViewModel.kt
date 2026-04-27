package com.bizarreelectronics.crm.ui.screens.tv

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.DashboardApi
import com.bizarreelectronics.crm.data.remote.api.TvQueueItem
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
 */
@HiltViewModel
class TvQueueBoardViewModel @Inject constructor(
    private val dashboardApi: DashboardApi,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _uiState = MutableStateFlow(TvQueueUiState(privacyMode = appPreferences.tvPrivacyMode))
    val uiState: StateFlow<TvQueueUiState> = _uiState.asStateFlow()

    /** Kick off the first load immediately when the ViewModel is created. */
    init {
        refresh()
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
 * @property isLoading   True during the first fetch and each subsequent refresh.
 * @property groups      Tickets grouped by [TvQueueGroup], in display order.
 *                       Empty map when the endpoint returns 404 or no tickets.
 * @property error       Non-null when the last refresh failed (non-404). The
 *                       screen shows this transiently while the loop continues.
 * @property privacyMode When true, customer names are masked to first-name +
 *                       last-initial ("John S.") in [TvQueueBoardScreen].
 *                       Set once from [AppPreferences.tvPrivacyMode] at VM init.
 */
data class TvQueueUiState(
    val isLoading: Boolean = true,
    val groups: Map<TvQueueGroup, List<TvQueueItem>> = emptyMap(),
    val error: String? = null,
    val privacyMode: Boolean = false,
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
