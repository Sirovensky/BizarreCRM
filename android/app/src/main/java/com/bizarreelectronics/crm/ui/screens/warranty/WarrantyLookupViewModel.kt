package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.WarrantyApi
import com.bizarreelectronics.crm.data.remote.api.WarrantyLookupRowDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Query type ──────────────────────────────────────────────────────────────

enum class WarrantyLookupQueryType(val label: String) {
    Imei("IMEI"),
    Serial("Serial #"),
    Phone("Phone"),
}

// ─── UI state ────────────────────────────────────────────────────────────────

data class WarrantyLookupUiState(
    val query: String = "",
    val queryType: WarrantyLookupQueryType = WarrantyLookupQueryType.Imei,
    val isLoading: Boolean = false,
    val results: List<WarrantyLookupRowDto> = emptyList(),
    val error: String? = null,
    /** Pending record for "Create warranty-return ticket" CTA confirmation. */
    val pendingCreateTicket: WarrantyLookupRowDto? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * §46.1 — Warranty lookup ViewModel.
 *
 * Drives [WarrantyLookupScreen]:
 *  1. User selects query type (IMEI / Serial / Phone) + enters value.
 *  2. Search calls [WarrantyApi.warrantyLookup]; results show warranty status.
 *  3. Tap a record → "Create warranty-return ticket" CTA (navigates to CheckIn).
 *
 * Server endpoint: GET /tickets/warranty-lookup?imei=|serial=|phone=
 * 404-tolerant: treated as empty result set.
 */
@HiltViewModel
class WarrantyLookupViewModel @Inject constructor(
    private val warrantyApi: WarrantyApi,
) : ViewModel() {

    private val _state = MutableStateFlow(WarrantyLookupUiState())
    val state: StateFlow<WarrantyLookupUiState> = _state.asStateFlow()

    fun onQueryChange(query: String) {
        _state.value = _state.value.copy(query = query, error = null)
    }

    fun onQueryTypeChange(type: WarrantyLookupQueryType) {
        _state.value = _state.value.copy(
            queryType = type,
            results = emptyList(),
            error = null,
        )
    }

    fun search() {
        val current = _state.value
        if (current.query.isBlank()) return
        _state.value = current.copy(isLoading = true, error = null, results = emptyList())

        viewModelScope.launch {
            try {
                val q = current.query.trim()
                val resp = when (current.queryType) {
                    WarrantyLookupQueryType.Imei   -> warrantyApi.warrantyLookup(imei = q)
                    WarrantyLookupQueryType.Serial -> warrantyApi.warrantyLookup(serial = q)
                    WarrantyLookupQueryType.Phone  -> warrantyApi.warrantyLookup(phone = q)
                }
                val rows = resp.data ?: emptyList()
                _state.value = _state.value.copy(
                    isLoading = false,
                    results = rows,
                    error = if (rows.isEmpty()) "No warranty records found." else null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Lookup failed: ${e.message}",
                )
            }
        }
    }

    /** User tapped a row's "Create warranty-return ticket" CTA — show confirm dialog. */
    fun requestCreateTicket(row: WarrantyLookupRowDto) {
        _state.value = _state.value.copy(pendingCreateTicket = row)
    }

    fun dismissCreateTicket() {
        _state.value = _state.value.copy(pendingCreateTicket = null)
    }
}
