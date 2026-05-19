package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.WarrantyApi
import com.bizarreelectronics.crm.data.remote.api.WarrantyClaimRequest
import com.bizarreelectronics.crm.data.remote.api.WarrantyClaimResponse
import com.bizarreelectronics.crm.data.remote.api.WarrantyRecordDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

data class WarrantyClaimUiState(
    val query: String = "",
    val queryType: QueryType = QueryType.Imei,

    val isSearching: Boolean = false,
    val searchError: String? = null,
    val searchResults: List<WarrantyRecordDto> = emptyList(),

    val selectedWarranty: WarrantyRecordDto? = null,
    val claimNotes: String = "",

    val isSubmitting: Boolean = false,
    val claimResult: WarrantyClaimResponse? = null,
    val claimError: String? = null,
)

enum class QueryType(val label: String) {
    Imei("IMEI"),
    Receipt("Receipt #"),
    Name("Customer name"),
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * §4.18 L812-L822 — Warranty claim screen ViewModel.
 *
 * Handles:
 * 1. Search: by IMEI / receipt / customer name.
 * 2. Selection: the user picks a matched warranty record.
 * 3. Claim submission: POST /warranties/:id/claim → branch decision.
 *
 * All network calls tolerate 404 — [WarrantyApi] 404s are treated as empty results.
 */
@HiltViewModel
class WarrantyClaimViewModel @Inject constructor(
    private val warrantyApi: WarrantyApi,
) : ViewModel() {

    private val _state = MutableStateFlow(WarrantyClaimUiState())
    val state: StateFlow<WarrantyClaimUiState> = _state.asStateFlow()

    // ─── Query ────────────────────────────────────────────────────────────────

    fun onQueryChange(query: String) {
        _state.update { it.copy(query = query, searchError = null) }
    }

    fun onQueryTypeChange(type: QueryType) {
        _state.update { it.copy(queryType = type, searchResults = emptyList(), searchError = null) }
    }

    fun search() {
        val current = _state.value
        if (current.query.isBlank()) return
        _state.update { it.copy(isSearching = true, searchError = null, searchResults = emptyList()) }

        viewModelScope.launch {
            try {
                val q = current.query.trim()
                val resp = when (current.queryType) {
                    QueryType.Imei    -> warrantyApi.searchWarranties(imei = q)
                    QueryType.Receipt -> warrantyApi.searchWarranties(receipt = q)
                    QueryType.Name    -> warrantyApi.searchWarranties(name = q)
                }
                val results = resp.data?.warranties ?: emptyList()
                _state.update {
                    it.copy(
                        isSearching = false,
                        searchResults = results,
                        searchError = if (results.isEmpty()) "No warranty records found." else null,
                    )
                }
            } catch (e: CancellationException) {
                // BUGHUNT-2026-05-17: re-throw so back-nav doesn't paint a
                // fake "Search failed" banner.
                throw e
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isSearching = false,
                        searchError = "Search failed: ${e.message}",
                    )
                }
            }
        }
    }

    // ─── Selection ────────────────────────────────────────────────────────────

    fun selectWarranty(warranty: WarrantyRecordDto) {
        _state.update {
            it.copy(
                selectedWarranty = warranty,
                claimResult = null,
                claimError = null,
            )
        }
    }

    fun onClaimNotesChange(notes: String) {
        _state.update { it.copy(claimNotes = notes) }
    }

    fun clearSelection() {
        _state.update {
            it.copy(
                selectedWarranty = null,
                claimNotes = "",
                claimResult = null,
                claimError = null,
            )
        }
    }

    // ─── Claim ───────────────────────────────────────────────────────────────

    /**
     * File a warranty claim against the currently selected warranty record.
     *
     * On success, [WarrantyClaimUiState.claimResult] is set with the server's
     * branch decision. The caller (WarrantyClaimScreen) inspects [branch] to decide
     * whether to navigate to the new ticket or show a "manual review" message.
     */
    fun fileClaim() {
        val selected = _state.value.selectedWarranty ?: return
        _state.update { it.copy(isSubmitting = true, claimError = null) }

        viewModelScope.launch {
            try {
                val resp = warrantyApi.fileClaim(
                    warrantyId = selected.id,
                    request = WarrantyClaimRequest(
                        warrantyId = selected.id,
                        notes = _state.value.claimNotes.ifBlank { null },
                        branch = null, // server determines branch based on install_date + duration
                    ),
                )
                val result = resp.data
                if (result != null) {
                    _state.update { it.copy(isSubmitting = false, claimResult = result) }
                } else {
                    _state.update {
                        it.copy(
                            isSubmitting = false,
                            claimError = resp.message ?: "Claim failed — no data returned.",
                        )
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isSubmitting = false,
                        claimError = "Failed to file claim: ${e.message}",
                    )
                }
            }
        }
    }

    fun clearClaimResult() {
        _state.update { it.copy(claimResult = null, claimError = null) }
    }
}
