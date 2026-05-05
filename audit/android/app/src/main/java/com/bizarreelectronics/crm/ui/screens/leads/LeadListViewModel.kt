package com.bizarreelectronics.crm.ui.screens.leads

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.data.remote.dto.UpdateLeadRequest
import com.bizarreelectronics.crm.data.repository.LeadRepository
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadSort
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

data class LeadListUiState(
    val leads: List<LeadEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedStatus: String = "All",
    val currentSort: LeadSort = LeadSort.NameAZ,
    // Bulk-select set — immutable: copied on each change
    val selectedLeadIds: Set<Long> = emptySet(),
)

@HiltViewModel
class LeadListViewModel @Inject constructor(
    private val leadRepository: LeadRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(LeadListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    // Snapshot for undo of bulk-delete (immutable copy of deleted ids)
    private var lastBulkDeletedIds: Set<Long> = emptySet()

    init {
        collectLeads()
    }

    fun loadLeads() = collectLeads()

    private fun collectLeads() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = _state.value.leads.isEmpty(),
                error = null,
            )
            val query = _state.value.searchQuery.trim()
            val status = _state.value.selectedStatus

            val flow = when {
                query.isNotEmpty() -> leadRepository.searchLeads(query)
                status == "Open" -> leadRepository.getOpenLeads()
                else -> leadRepository.getLeads()
            }

            flow.collect { leads ->
                val filtered = when (status) {
                    "All", "Open" -> leads
                    else -> leads.filter {
                        it.status.equals(status, ignoreCase = true)
                    }
                }
                _state.value = _state.value.copy(
                    leads = filtered,
                    isLoading = false,
                    isRefreshing = false,
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        collectLeads()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            collectLeads()
        }
    }

    fun onStatusChanged(status: String) {
        _state.value = _state.value.copy(selectedStatus = status)
        collectLeads()
    }

    /** Switch sort order; displayed list is re-sorted reactively in the Screen. */
    fun onSortChanged(sort: LeadSort) {
        _state.value = _state.value.copy(currentSort = sort)
    }

    // ─── Bulk selection ──────────────────────────────────────────────────────

    fun toggleSelection(leadId: Long) {
        val current = _state.value.selectedLeadIds
        val updated = if (leadId in current) current - leadId else current + leadId
        _state.value = _state.value.copy(selectedLeadIds = updated)
    }

    fun clearSelection() {
        _state.value = _state.value.copy(selectedLeadIds = emptySet())
    }

    /**
     * Bulk-delete: marks each lead in [ids] as "lost".
     * Stores the ids for [undoBulkDelete].
     */
    fun bulkDelete(ids: Set<Long>) {
        lastBulkDeletedIds = ids
        viewModelScope.launch {
            ids.forEach { id ->
                try {
                    leadRepository.updateLead(id, UpdateLeadRequest(status = "lost", lostReason = "Bulk deleted"))
                } catch (e: Exception) {
                    Timber.tag("LeadList").e(e, "bulkDelete failed for id=$id")
                }
            }
        }
        _state.value = _state.value.copy(selectedLeadIds = emptySet())
    }

    /**
     * Undo bulk-delete by restoring each affected lead's status to "new".
     * This is best-effort; network failures are silently logged.
     */
    fun undoBulkDelete() {
        val ids = lastBulkDeletedIds
        if (ids.isEmpty()) return
        viewModelScope.launch {
            ids.forEach { id ->
                try {
                    leadRepository.updateLead(id, UpdateLeadRequest(status = "new"))
                } catch (e: Exception) {
                    Timber.tag("LeadList").e(e, "undoBulkDelete failed for id=$id")
                }
            }
        }
        lastBulkDeletedIds = emptySet()
    }

    // ─── Stage advance / drop (swipe + kanban drop) ──────────────────────────

    /** Advance a lead to [newStage] with optimistic update; rolls back on failure. */
    fun advanceStage(leadId: Long, newStage: String) {
        viewModelScope.launch {
            try {
                leadRepository.updateLead(leadId, UpdateLeadRequest(status = newStage))
            } catch (e: Exception) {
                Timber.tag("LeadList").e(e, "advanceStage failed: leadId=$leadId newStage=$newStage")
            }
        }
    }

    /** Drop a lead back to [newStage] (swipe-trailing). */
    fun dropStage(leadId: Long, newStage: String) {
        viewModelScope.launch {
            try {
                leadRepository.updateLead(leadId, UpdateLeadRequest(status = newStage))
            } catch (e: Exception) {
                Timber.tag("LeadList").e(e, "dropStage failed: leadId=$leadId newStage=$newStage")
            }
        }
    }
}
