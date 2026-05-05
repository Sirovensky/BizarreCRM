package com.bizarreelectronics.crm.ui.screens.stocktake

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.remote.api.StocktakeApi
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCount
import com.bizarreelectronics.crm.data.remote.dto.StocktakeListItem
import com.bizarreelectronics.crm.data.remote.dto.StocktakeSummary
import com.bizarreelectronics.crm.data.remote.dto.StocktakeUpsertCountRequest
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────────

/**
 * UI state for the §6.6 Stocktake session detail screen.
 *
 * [session] is null until the initial load completes.
 * [counts] is the live list of count lines for this session.
 * [summary] is the variance roll-up recomputed locally after each upsert.
 * [committedSuccess] transitions to true after a successful commit —
 *   the composable navigates to the committed result view.
 */
data class StocktakeSessionDetailUiState(
    val session: StocktakeListItem? = null,
    val counts: List<StocktakeCount> = emptyList(),
    val summary: StocktakeSummary = StocktakeSummary(0, 0, 0, 0, 0),
    val isLoading: Boolean = true,
    val isUpsertingCount: Boolean = false,
    val isCommitting: Boolean = false,
    val error: String? = null,
    val committedSuccess: Boolean = false,
    val searchQuery: String = "",
    val searchResults: List<InventoryItemEntity> = emptyList(),
)

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * §6.6 Stocktake session detail.
 *
 * Loads an existing open session from [GET /stocktake/:id], shows its current
 * count lines + variance summary, allows adding / updating item counts via
 * [POST /stocktake/:id/counts], and commits the session via
 * [POST /stocktake/:id/commit].
 *
 * [sessionId] is injected from the nav argument "sessionId" via [SavedStateHandle].
 */
@HiltViewModel
class StocktakeSessionDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val stocktakeApi: StocktakeApi,
    private val inventoryRepository: InventoryRepository,
) : ViewModel() {

    private val sessionId: Int = checkNotNull(savedStateHandle["sessionId"])

    private val _state = MutableStateFlow(StocktakeSessionDetailUiState())
    val state = _state.asStateFlow()

    init {
        loadSession()
    }

    // ── Load session ──────────────────────────────────────────────────────────

    fun loadSession() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val resp = stocktakeApi.getSession(sessionId)
                val detail = resp.data ?: run {
                    _state.value = _state.value.copy(isLoading = false, error = "No data returned")
                    return@launch
                }
                _state.value = _state.value.copy(
                    session = detail.session,
                    counts = detail.counts,
                    summary = detail.summary,
                    isLoading = false,
                )
            } catch (e: HttpException) {
                val msg = when (e.code()) {
                    404 -> "Session not found"
                    403 -> "Permission denied"
                    else -> "Failed to load session (HTTP ${e.code()})"
                }
                Log.w(TAG, "GET /stocktake/$sessionId HTTP ${e.code()}: ${e.message()}")
                _state.value = _state.value.copy(isLoading = false, error = msg)
            } catch (e: Exception) {
                Log.w(TAG, "GET /stocktake/$sessionId failed: ${e.message}")
                _state.value = _state.value.copy(isLoading = false, error = "Network error — check connection")
            }
        }
    }

    // ── Count upsert ──────────────────────────────────────────────────────────

    /**
     * UPSERT a count for [item] with [countedQty] into this session.
     * POSTs to [POST /stocktake/:id/counts]; on success, merges the returned
     * row into [counts] and recomputes [summary] locally.
     */
    fun upsertCount(item: InventoryItemEntity, countedQty: Int) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isUpsertingCount = true, error = null, searchQuery = "", searchResults = emptyList())
            try {
                val resp = stocktakeApi.upsertCount(
                    id = sessionId,
                    request = StocktakeUpsertCountRequest(
                        inventoryItemId = item.id,
                        countedQty = countedQty,
                    ),
                )
                val updated = resp.data ?: run {
                    _state.value = _state.value.copy(isUpsertingCount = false)
                    return@launch
                }
                val newCounts = mergeCount(_state.value.counts, updated)
                _state.value = _state.value.copy(
                    counts = newCounts,
                    summary = computeSummary(newCounts),
                    isUpsertingCount = false,
                )
            } catch (e: HttpException) {
                val msg = when (e.code()) {
                    400 -> if (_state.value.session?.status != "open") "Session is no longer open" else "Invalid request"
                    403 -> "Permission denied"
                    404 -> "Item or session not found"
                    else -> "Failed to record count (HTTP ${e.code()})"
                }
                Log.w(TAG, "POST /stocktake/$sessionId/counts HTTP ${e.code()}: ${e.message()}")
                _state.value = _state.value.copy(isUpsertingCount = false, error = msg)
            } catch (e: Exception) {
                Log.w(TAG, "upsertCount failed: ${e.message}")
                _state.value = _state.value.copy(isUpsertingCount = false, error = "Network error")
            }
        }
    }

    /**
     * Convenience: update the counted quantity for an already-listed line.
     * Posts directly without going through [upsertCount]'s entity lookup.
     */
    fun updateCountQty(inventoryItemId: Long, newQty: Int) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isUpsertingCount = true, error = null)
            try {
                val resp = stocktakeApi.upsertCount(
                    id = sessionId,
                    request = StocktakeUpsertCountRequest(
                        inventoryItemId = inventoryItemId,
                        countedQty = newQty,
                    ),
                )
                val updated = resp.data ?: run {
                    _state.value = _state.value.copy(isUpsertingCount = false)
                    return@launch
                }
                val newCounts = mergeCount(_state.value.counts, updated)
                _state.value = _state.value.copy(
                    counts = newCounts,
                    summary = computeSummary(newCounts),
                    isUpsertingCount = false,
                )
            } catch (e: HttpException) {
                Log.w(TAG, "updateCountQty HTTP ${e.code()}: ${e.message()}")
                _state.value = _state.value.copy(
                    isUpsertingCount = false,
                    error = "Failed to update count (HTTP ${e.code()})",
                )
            } catch (e: Exception) {
                Log.w(TAG, "updateCountQty failed: ${e.message}")
                _state.value = _state.value.copy(isUpsertingCount = false, error = "Network error")
            }
        }
    }

    // ── Barcode scan ──────────────────────────────────────────────────────────

    /**
     * Look up a scanned barcode in the local Room DB and, if found, upsert
     * a count of 1 (default; operator edits inline) for this session.
     */
    fun onBarcodeScanned(rawValue: String) {
        viewModelScope.launch {
            val item = inventoryRepository.lookupBarcode(rawValue)
            if (item != null) {
                val existing = _state.value.counts.firstOrNull { it.inventoryItemId == item.id }
                upsertCount(item, (existing?.countedQty ?: 0) + 1)
            } else {
                _state.value = _state.value.copy(error = "No item found for barcode: $rawValue")
            }
        }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    fun onSearchQueryChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        if (query.length >= 2) {
            viewModelScope.launch {
                inventoryRepository.searchItems(query).collect { results ->
                    _state.value = _state.value.copy(searchResults = results.take(20))
                }
            }
        } else {
            _state.value = _state.value.copy(searchResults = emptyList())
        }
    }

    fun clearSearch() {
        _state.value = _state.value.copy(searchQuery = "", searchResults = emptyList())
    }

    // ── Commit ────────────────────────────────────────────────────────────────

    /**
     * Commit this session via [POST /stocktake/:id/commit].
     * On success sets [committedSuccess] = true so the screen navigates out.
     */
    fun commitSession() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isCommitting = true, error = null)
            try {
                stocktakeApi.commitById(sessionId)
                _state.value = _state.value.copy(isCommitting = false, committedSuccess = true)
            } catch (e: HttpException) {
                val msg = when (e.code()) {
                    400 -> "Cannot commit: ${e.message()}"
                    403 -> "Admin or manager role required to commit"
                    409 -> "Session was already committed by another user"
                    else -> "Commit failed (HTTP ${e.code()})"
                }
                Log.w(TAG, "POST /stocktake/$sessionId/commit HTTP ${e.code()}: ${e.message()}")
                _state.value = _state.value.copy(isCommitting = false, error = msg)
            } catch (e: Exception) {
                Log.w(TAG, "commitSession failed: ${e.message}")
                _state.value = _state.value.copy(isCommitting = false, error = "Network error — commit not saved")
            }
        }
    }

    // ── Misc ──────────────────────────────────────────────────────────────────

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun consumeCommittedSuccess() {
        _state.value = _state.value.copy(committedSuccess = false)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Replace or append [updated] in [current] list, matched by inventoryItemId. */
    private fun mergeCount(
        current: List<StocktakeCount>,
        updated: StocktakeCount,
    ): List<StocktakeCount> {
        val idx = current.indexOfFirst { it.inventoryItemId == updated.inventoryItemId }
        return if (idx >= 0) {
            current.toMutableList().also { it[idx] = updated }
        } else {
            listOf(updated) + current // newest first, mirrors server ORDER BY counted_at DESC
        }
    }

    /** Recompute summary from the current count list (avoids extra network call). */
    private fun computeSummary(counts: List<StocktakeCount>): StocktakeSummary {
        var itemsCounted = 0
        var itemsWithVariance = 0
        var totalVariance = 0
        var surplus = 0
        var shortage = 0
        for (c in counts) {
            itemsCounted++
            totalVariance += c.variance
            if (c.variance != 0) itemsWithVariance++
            if (c.variance > 0) surplus += c.variance
            if (c.variance < 0) shortage += (-c.variance)
        }
        return StocktakeSummary(
            itemsCounted = itemsCounted,
            itemsWithVariance = itemsWithVariance,
            totalVariance = totalVariance,
            surplus = surplus,
            shortage = shortage,
        )
    }

    companion object {
        private const val TAG = "StocktakeSessionDetailVM"
    }
}
