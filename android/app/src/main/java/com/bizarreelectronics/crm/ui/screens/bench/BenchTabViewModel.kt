package com.bizarreelectronics.crm.ui.screens.bench

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.BenchApi
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * BenchTabViewModel — §4.9 L756
 *
 * Loads the authenticated technician's "my bench" tickets via [BenchApi.myBench].
 * 404-tolerant: when the server returns 404 (pre-dates the endpoint) the state
 * falls back to an empty list rather than surfacing an error.
 *
 * iOS parallel: the same server endpoint is consumed by the iOS Swift client;
 * request/response shapes are identical.
 */
@HiltViewModel
class BenchTabViewModel @Inject constructor(
    private val benchApi: BenchApi,
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
            _state.value = _state.value.copy(isLoading = false, offline = true)
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = benchApi.myBench()
                val tickets = response.data?.tickets ?: emptyList()
                _state.value = _state.value.copy(
                    isLoading = false,
                    tickets = tickets,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Server build pre-dates the endpoint — degrade gracefully.
                    _state.value = _state.value.copy(isLoading = false, tickets = emptyList())
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Failed to load bench tickets (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load bench tickets",
                )
            }
        }
    }
}

/**
 * UI state for [BenchTabScreen].
 *
 * @param tickets   List of in-repair tickets assigned to the current technician.
 * @param isLoading True while the initial or refresh fetch is in flight.
 * @param error     Non-null when a recoverable fetch error occurred.
 * @param offline   True when the server is unreachable; tickets list may be stale.
 */
data class BenchTabUiState(
    val tickets: List<TicketListItem> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val offline: Boolean = false,
)
