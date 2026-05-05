package com.bizarreelectronics.crm.ui.screens.devicehistory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.DeviceHistoryEntry
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────────

data class DeviceHistoryUiState(
    val query: String = "",
    val queryType: DeviceHistoryQueryType = DeviceHistoryQueryType.Imei,
    val isLoading: Boolean = false,
    val error: String? = null,
    val entries: List<DeviceHistoryEntry> = emptyList(),
)

enum class DeviceHistoryQueryType(val label: String) {
    Imei("IMEI"),
    Serial("Serial"),
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * §46.2 — Device History screen ViewModel.
 *
 * Calls GET /tickets/device-history?imei= or ?serial= and surfaces a timeline
 * of all past repairs on this device across any customer.
 */
@HiltViewModel
class DeviceHistoryViewModel @Inject constructor(
    private val ticketApi: TicketApi,
) : ViewModel() {

    private val _state = MutableStateFlow(DeviceHistoryUiState())
    val state: StateFlow<DeviceHistoryUiState> = _state.asStateFlow()

    fun onQueryChange(query: String) {
        _state.value = _state.value.copy(query = query, error = null)
    }

    fun onQueryTypeChange(type: DeviceHistoryQueryType) {
        _state.value = _state.value.copy(
            queryType = type,
            entries = emptyList(),
            error = null,
        )
    }

    fun search() {
        val current = _state.value
        if (current.query.isBlank()) return
        _state.value = current.copy(isLoading = true, error = null, entries = emptyList())
        val q = current.query.trim()
        viewModelScope.launch {
            try {
                val resp = when (current.queryType) {
                    DeviceHistoryQueryType.Imei   -> ticketApi.getDeviceHistory(imei = q)
                    DeviceHistoryQueryType.Serial -> ticketApi.getDeviceHistory(serial = q)
                }
                val entries = resp.data ?: emptyList()
                _state.value = _state.value.copy(
                    isLoading = false,
                    entries = entries,
                    error = if (entries.isEmpty()) "No repair history found for this device." else null,
                )
            } catch (e: Exception) {
                val is404 = runCatching { (e as? retrofit2.HttpException)?.code() == 404 }.getOrDefault(false)
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = if (is404) "No repair history found." else "Search failed: ${e.message}",
                )
            }
        }
    }
}
