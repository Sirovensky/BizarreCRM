package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.DeviceHistoryRowDto
import com.bizarreelectronics.crm.data.remote.api.WarrantyApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Query type ──────────────────────────────────────────────────────────────

enum class DeviceHistoryQueryType(val label: String) {
    Imei("IMEI"),
    Serial("Serial #"),
}

// ─── UI state ────────────────────────────────────────────────────────────────

data class DeviceHistoryUiState(
    val query: String = "",
    val queryType: DeviceHistoryQueryType = DeviceHistoryQueryType.Imei,
    val isLoading: Boolean = false,
    val rows: List<DeviceHistoryRowDto> = emptyList(),
    val error: String? = null,
    /** Pre-filled if launched from a known IMEI/serial context. */
    val prefilledQuery: String? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * §46.2 — Device history ViewModel.
 *
 * Drives [DeviceHistoryScreen]:
 *  1. Accepts optional prefill from ticket detail / customer asset tab.
 *  2. Fetches GET /tickets/device-history?imei=|serial=
 *  3. Results show all past tickets for this exact device.
 *
 * 404-tolerant: treated as empty result set.
 */
@HiltViewModel
class DeviceHistoryViewModel @Inject constructor(
    private val warrantyApi: WarrantyApi,
) : ViewModel() {

    private val _state = MutableStateFlow(DeviceHistoryUiState())
    val state: StateFlow<DeviceHistoryUiState> = _state.asStateFlow()

    /** Called from navigation on screen entry with optional pre-filled IMEI/serial. */
    fun initWithPrefill(imei: String?, serial: String?) {
        val q = imei ?: serial ?: return
        val type = if (imei != null) DeviceHistoryQueryType.Imei else DeviceHistoryQueryType.Serial
        _state.value = _state.value.copy(query = q, queryType = type, prefilledQuery = q)
        search()
    }

    fun onQueryChange(query: String) {
        _state.value = _state.value.copy(query = query, error = null)
    }

    fun onQueryTypeChange(type: DeviceHistoryQueryType) {
        _state.value = _state.value.copy(queryType = type, rows = emptyList(), error = null)
    }

    fun search() {
        val current = _state.value
        if (current.query.isBlank()) return
        _state.value = current.copy(isLoading = true, error = null, rows = emptyList())

        viewModelScope.launch {
            try {
                val q = current.query.trim()
                val resp = when (current.queryType) {
                    DeviceHistoryQueryType.Imei   -> warrantyApi.deviceHistory(imei = q)
                    DeviceHistoryQueryType.Serial -> warrantyApi.deviceHistory(serial = q)
                }
                val rows = resp.data ?: emptyList()
                _state.value = _state.value.copy(
                    isLoading = false,
                    rows = rows,
                    error = if (rows.isEmpty()) "No repair history found for this device." else null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "History lookup failed: ${e.message}",
                )
            }
        }
    }
}
