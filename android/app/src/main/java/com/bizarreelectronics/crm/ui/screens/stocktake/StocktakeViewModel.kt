package com.bizarreelectronics.crm.ui.screens.stocktake

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.StocktakeApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCommitRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCountLine
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

/** Three-phase session lifecycle (§60.1). */
enum class StocktakePhase {
    DRAFT,       // Session created locally; server start not yet attempted
    ACTIVE,      // Session started (server notified or offline)
    COMMITTED,   // Count committed and adjustments applied
}

/**
 * §60 Stocktake UI state.
 *
 * [lines] is the live count sheet. Only items that have been explicitly
 * counted (scanned or manually entered) appear here. System quantities
 * are snapshotted at session-start time.
 *
 * [approvalPending] is true after commit: manager approval queue (§60.4) is
 * a server-side concept; the client shows a "pending approval" banner until
 * the server acknowledges variance clearance. (Currently informational only —
 * no server endpoint yet.)
 */
data class StocktakeUiState(
    val phase: StocktakePhase = StocktakePhase.DRAFT,
    val lines: List<StocktakeCountLine> = emptyList(),
    val sessionId: String? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val commitSuccess: Boolean = false,
    val approvalPending: Boolean = false,
    val searchQuery: String = "",
    /** Items matching [searchQuery] loaded from the local DB for scan lookup. */
    val searchResults: List<InventoryItemEntity> = emptyList(),
    val isOffline: Boolean = false,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class StocktakeViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository,
    private val stocktakeApi: StocktakeApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) : ViewModel() {

    private val _state = MutableStateFlow(StocktakeUiState())
    val state = _state.asStateFlow()

    // ── Session start ─────────────────────────────────────────────────────────

    /**
     * Advance from DRAFT → ACTIVE. Attempts to notify the server (§60.3 multi-
     * scanner sync). Falls back silently on 404 (server route not yet deployed).
     */
    fun startSession() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val sessionId = tryStartOnServer()
            _state.value = _state.value.copy(
                phase = StocktakePhase.ACTIVE,
                sessionId = sessionId,
                isLoading = false,
                isOffline = !serverMonitor.isEffectivelyOnline.value,
            )
        }
    }

    /**
     * Returns the server-assigned session ID, or null if the endpoint 404d
     * or the device is offline (both are acceptable — session continues locally).
     */
    private suspend fun tryStartOnServer(): String? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            stocktakeApi.startSession().data?.sessionId
        } catch (e: HttpException) {
            if (e.code() == 404) {
                Log.d(TAG, "stocktake/start 404 — continuing offline (server not yet deployed)")
            } else {
                Log.w(TAG, "stocktake/start HTTP ${e.code()}: ${e.message()}")
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "stocktake/start failed: ${e.message}")
            null
        }
    }

    // ── Count entry ───────────────────────────────────────────────────────────

    /**
     * Record a count for an item (§60.2). If the item is already on the sheet,
     * overwrites its [StocktakeCountLine.countedQty]. Otherwise adds a new line.
     *
     * [systemQty] should be the current [InventoryItemEntity.inStock] value.
     */
    fun setCount(
        itemId: Long,
        itemName: String,
        sku: String?,
        upcCode: String?,
        systemQty: Int,
        countedQty: Int,
    ) {
        val existing = _state.value.lines.indexOfFirst { it.itemId == itemId }
        val newLine = StocktakeCountLine(
            itemId = itemId,
            itemName = itemName,
            sku = sku,
            upcCode = upcCode,
            systemQty = systemQty,
            countedQty = countedQty,
        )
        val updated = if (existing >= 0) {
            _state.value.lines.toMutableList().also { it[existing] = newLine }
        } else {
            _state.value.lines + newLine
        }
        _state.value = _state.value.copy(lines = updated)
    }

    /** Remove a line from the count sheet. */
    fun removeLine(itemId: Long) {
        _state.value = _state.value.copy(
            lines = _state.value.lines.filter { it.itemId != itemId },
        )
    }

    // ── Barcode scan ──────────────────────────────────────────────────────────

    /** Look up a scanned barcode in the local DB and add to count sheet. */
    fun onBarcodeScanned(rawValue: String) {
        viewModelScope.launch {
            val item = inventoryRepository.lookupBarcode(rawValue)
            if (item != null) {
                setCount(
                    itemId = item.id,
                    itemName = item.name,
                    sku = item.sku,
                    upcCode = item.upcCode,
                    systemQty = item.inStock,
                    countedQty = 1, // default 1; operator edits inline
                )
            } else {
                _state.value = _state.value.copy(
                    error = "No item found for barcode: $rawValue",
                )
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
     * Commit the count sheet (§60.1 ACTIVE → COMMITTED).
     *
     * Strategy:
     * 1. Try POST /inventory/stocktake/commit (404-tolerant).
     * 2. On 404 or offline: apply each variance as an individual
     *    [InventoryRepository.adjustStock] call (or enqueue to SyncQueue).
     * 3. Mark phase COMMITTED regardless.
     */
    fun commitSession(note: String? = null) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val lines = _state.value.lines.filter { it.variance != 0 }
            val committed = tryCommitOnServer(lines, note)
            if (!committed) {
                applyAdjustmentsLocally(lines)
            }
            _state.value = _state.value.copy(
                phase = StocktakePhase.COMMITTED,
                isLoading = false,
                commitSuccess = true,
                approvalPending = true, // §60.4 — server-side approval not yet implemented
            )
        }
    }

    /**
     * Attempt a single-call commit via [StocktakeApi.commitSession].
     * Returns true if the server accepted it. Returns false on 404 / offline.
     */
    private suspend fun tryCommitOnServer(
        lines: List<StocktakeCountLine>,
        note: String?,
    ): Boolean {
        if (!serverMonitor.isEffectivelyOnline.value) return false
        return try {
            stocktakeApi.commitSession(
                StocktakeCommitRequest(
                    sessionId = _state.value.sessionId,
                    lines = lines,
                    note = note,
                )
            )
            true
        } catch (e: HttpException) {
            if (e.code() == 404) {
                Log.d(TAG, "stocktake/commit 404 — applying adjustments individually")
            } else {
                Log.w(TAG, "stocktake/commit HTTP ${e.code()}: ${e.message()}")
            }
            false
        } catch (e: Exception) {
            Log.w(TAG, "stocktake/commit failed: ${e.message}")
            false
        }
    }

    /**
     * Fallback: apply each variance line as an individual stock-adjustment.
     * Positive variance = "received" movement; negative = "adjusted" (shrinkage).
     * Offline lines go to SyncQueue via [InventoryRepository.adjustStock].
     */
    private suspend fun applyAdjustmentsLocally(lines: List<StocktakeCountLine>) {
        for (line in lines) {
            val delta = line.variance
            if (delta == 0) continue
            try {
                inventoryRepository.adjustStock(
                    id = line.itemId,
                    request = AdjustStockRequest(
                        quantity = delta,
                        type = if (delta > 0) "received" else "adjusted",
                        reason = "Stocktake variance",
                        reference = _state.value.sessionId,
                    ),
                )
            } catch (e: Exception) {
                Log.w(TAG, "Fallback adjust failed for item ${line.itemId}: ${e.message}")
                // Last-resort: push directly to SyncQueue
                syncQueueDao.insert(
                    SyncQueueEntity(
                        entityType = "inventory",
                        entityId = line.itemId,
                        operation = "adjust_stock",
                        payload = gson.toJson(
                            AdjustStockRequest(
                                quantity = delta,
                                type = if (delta > 0) "received" else "adjusted",
                                reason = "Stocktake variance",
                                reference = _state.value.sessionId,
                            )
                        ),
                    )
                )
            }
        }
    }

    // ── Discard ───────────────────────────────────────────────────────────────

    /** Discard the current session — wipes all count lines, returns to DRAFT. */
    fun discardSession() {
        _state.value = StocktakeUiState()
    }

    // ── Misc ──────────────────────────────────────────────────────────────────

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun consumeCommitSuccess() {
        _state.value = _state.value.copy(commitSuccess = false)
    }

    companion object {
        private const val TAG = "StocktakeViewModel"
    }
}
