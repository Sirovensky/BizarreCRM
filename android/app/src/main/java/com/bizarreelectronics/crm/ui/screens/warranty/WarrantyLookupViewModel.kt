package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.api.WarrantyClaimRequest
import com.bizarreelectronics.crm.data.remote.api.WarrantyClaimResponse
import com.bizarreelectronics.crm.data.remote.api.WarrantyApi
import com.bizarreelectronics.crm.data.remote.dto.WarrantyResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────────

enum class WarrantyQueryType(val label: String) {
    Imei("IMEI"),
    Serial("Serial"),
    Phone("Phone"),
    Name("Last name"),
}

data class WarrantyLookupUiState(
    val query: String = "",
    val queryType: WarrantyQueryType = WarrantyQueryType.Imei,

    val isSearching: Boolean = false,
    val searchError: String? = null,
    val searchResults: List<WarrantyResult> = emptyList(),

    val selectedWarranty: WarrantyResult? = null,
    val claimNotes: String = "",

    val isSubmitting: Boolean = false,
    val claimResult: WarrantyClaimResponse? = null,
    val claimError: String? = null,
)

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * §46.1 — Warranty lookup + claim filing ViewModel.
 *
 * Uses [TicketApi.warrantyLookup] (GET /tickets/warranty-lookup) for search,
 * and [WarrantyApi.fileClaim] (POST /warranties/:id/claim) for the CTA.
 *
 * Search by IMEI / serial / phone maps to the server's query params directly.
 * "Last name" search maps to the [WarrantyApi.searchWarranties] name param as
 * a fallback (ticket warranty-lookup does not support name search).
 */
@HiltViewModel
class WarrantyLookupViewModel @Inject constructor(
    private val ticketApi: TicketApi,
    private val warrantyApi: WarrantyApi,
) : ViewModel() {

    private val _state = MutableStateFlow(WarrantyLookupUiState())
    val state: StateFlow<WarrantyLookupUiState> = _state.asStateFlow()

    fun onQueryChange(query: String) {
        _state.value = _state.value.copy(query = query, searchError = null)
    }

    fun onQueryTypeChange(type: WarrantyQueryType) {
        _state.value = _state.value.copy(
            queryType = type,
            searchResults = emptyList(),
            searchError = null,
        )
    }

    fun search() {
        val current = _state.value
        if (current.query.isBlank()) return
        _state.value = current.copy(isSearching = true, searchError = null, searchResults = emptyList())
        val q = current.query.trim()
        viewModelScope.launch {
            try {
                val results: List<WarrantyResult> = when (current.queryType) {
                    WarrantyQueryType.Imei   -> ticketApi.warrantyLookup(imei = q).data ?: emptyList()
                    WarrantyQueryType.Serial -> ticketApi.warrantyLookup(serial = q).data ?: emptyList()
                    WarrantyQueryType.Phone  -> ticketApi.warrantyLookup(phone = q).data ?: emptyList()
                    WarrantyQueryType.Name   -> {
                        // Name search goes via WarrantyApi.searchWarranties, which supports name=.
                        // Map WarrantyRecordDto → WarrantyResult for display.
                        val resp = warrantyApi.searchWarranties(name = q)
                        resp.data?.warranties?.map { dto ->
                            WarrantyResult(
                                ticketId = dto.ticketId,
                                orderId = dto.receiptNumber,
                                deviceName = null,
                                imei = dto.imei,
                                serial = dto.serial,
                                warrantyDays = null,
                                warrantyExpires = null,
                                warrantyActive = dto.eligible,
                                customerFirst = dto.customerName,
                                customerLast = null,
                                statusName = null,
                                collectedDate = null,
                                ticketCreated = dto.installDate,
                            )
                        } ?: emptyList()
                    }
                }
                _state.value = _state.value.copy(
                    isSearching = false,
                    searchResults = results,
                    searchError = if (results.isEmpty()) "No warranty records found." else null,
                )
            } catch (e: Exception) {
                val is404 = runCatching { (e as? retrofit2.HttpException)?.code() == 404 }.getOrDefault(false)
                _state.value = _state.value.copy(
                    isSearching = false,
                    searchError = if (is404) "No warranty records found." else "Search failed: ${e.message}",
                )
            }
        }
    }

    fun selectWarranty(warranty: WarrantyResult) {
        _state.value = _state.value.copy(
            selectedWarranty = warranty,
            claimResult = null,
            claimError = null,
        )
    }

    fun onClaimNotesChange(notes: String) {
        _state.value = _state.value.copy(claimNotes = notes)
    }

    fun clearSelection() {
        _state.value = _state.value.copy(
            selectedWarranty = null,
            claimNotes = "",
            claimResult = null,
            claimError = null,
        )
    }

    /**
     * Attempt to file a warranty claim via POST /warranties/:id/claim.
     *
     * NOTE: the /warranties route is not registered on the server yet. The CTA
     * is wired and visible; at runtime this will return a 404 which surfaces as
     * [WarrantyLookupUiState.claimError] with the "coming soon" message below.
     * The endpoint will be wired in a follow-up server migration.
     */
    fun fileClaim() {
        val selected = _state.value.selectedWarranty ?: return
        val ticketId = selected.ticketId ?: return
        _state.value = _state.value.copy(isSubmitting = true, claimError = null)
        viewModelScope.launch {
            try {
                val resp = warrantyApi.fileClaim(
                    warrantyId = ticketId,
                    request = WarrantyClaimRequest(
                        warrantyId = ticketId,
                        notes = _state.value.claimNotes.ifBlank { null },
                        branch = null,
                    ),
                )
                val result = resp.data
                if (result != null) {
                    _state.value = _state.value.copy(isSubmitting = false, claimResult = result)
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        claimError = resp.message ?: "Claim filed — check ticket queue.",
                    )
                }
            } catch (e: Exception) {
                val is404 = runCatching { (e as? retrofit2.HttpException)?.code() == 404 }.getOrDefault(false)
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    claimError = if (is404) "Warranty claims not yet available — server update required."
                    else "Failed to file claim: ${e.message}",
                )
            }
        }
    }

    fun clearClaimResult() {
        _state.value = _state.value.copy(claimResult = null, claimError = null)
    }
}
