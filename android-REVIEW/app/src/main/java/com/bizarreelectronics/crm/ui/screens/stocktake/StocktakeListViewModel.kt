package com.bizarreelectronics.crm.ui.screens.stocktake

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.StocktakeApi
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────────

data class StocktakeListUiState(
    val sessions: List<StocktakeListItem> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    /** Non-null while the "New session" dialog is open. */
    val showNewDialog: Boolean = false,
    /** True while a POST /stocktake request is in-flight. */
    val isCreating: Boolean = false,
    /** After a successful create, the new session id is stored here so the
     *  screen can navigate into the active-count flow. Consumed once read. */
    val createdSessionId: Int? = null,
    /** True when the server returns 404 for the list endpoint (not yet deployed
     *  on older self-hosted builds). In this case we show a fallback state. */
    val serverUnsupported: Boolean = false,
)

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * §6.6 Stocktake sessions list.
 *
 * Loads [GET /stocktake] and exposes a "New session" dialog that POSTs to
 * [POST /stocktake]. Both calls are 404-tolerant: older self-hosted server
 * builds that lack the stocktake routes fall through to [serverUnsupported].
 */
@HiltViewModel
class StocktakeListViewModel @Inject constructor(
    private val stocktakeApi: StocktakeApi,
) : ViewModel() {

    private val _state = MutableStateFlow(StocktakeListUiState())
    val state = _state.asStateFlow()

    init {
        loadSessions()
    }

    // ── Load ──────────────────────────────────────────────────────────────────

    fun loadSessions() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val resp = stocktakeApi.listSessions()
                _state.value = _state.value.copy(
                    sessions = resp.data ?: emptyList(),
                    isLoading = false,
                    serverUnsupported = false,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    Log.d(TAG, "GET /stocktake 404 — server route not yet deployed")
                    _state.value = _state.value.copy(
                        isLoading = false,
                        serverUnsupported = true,
                    )
                } else {
                    Log.w(TAG, "GET /stocktake HTTP ${e.code()}: ${e.message()}")
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Failed to load sessions (HTTP ${e.code()})",
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "GET /stocktake failed: ${e.message}")
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Network error — check your connection",
                )
            }
        }
    }

    // ── New session dialog ────────────────────────────────────────────────────

    fun showNewDialog() {
        _state.value = _state.value.copy(showNewDialog = true)
    }

    fun dismissNewDialog() {
        _state.value = _state.value.copy(showNewDialog = false)
    }

    /**
     * POST /stocktake to open a new session.
     * On success, stores the new session id in [StocktakeListUiState.createdSessionId]
     * so the screen can navigate into the active-count flow.
     */
    fun createSession(name: String, location: String?, notes: String?) {
        val trimmedName = name.trim()
        if (trimmedName.isBlank()) {
            _state.value = _state.value.copy(error = "Session name is required")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isCreating = true, error = null)
            try {
                val resp = stocktakeApi.createSession(
                    StocktakeCreateRequest(
                        name = trimmedName,
                        location = location?.trim()?.takeIf { it.isNotBlank() },
                        notes = notes?.trim()?.takeIf { it.isNotBlank() },
                    )
                )
                val newItem = resp.data
                if (newItem != null) {
                    _state.value = _state.value.copy(
                        sessions = listOf(newItem) + _state.value.sessions,
                        isCreating = false,
                        showNewDialog = false,
                        createdSessionId = newItem.id,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isCreating = false,
                        error = "Server returned no data",
                    )
                }
            } catch (e: HttpException) {
                val msg = when (e.code()) {
                    400 -> "Session name is required"
                    403 -> "Admin or manager role required"
                    404 -> "Stocktake not available on this server"
                    else -> "Failed to create session (HTTP ${e.code()})"
                }
                Log.w(TAG, "POST /stocktake HTTP ${e.code()}: ${e.message()}")
                _state.value = _state.value.copy(isCreating = false, error = msg)
            } catch (e: Exception) {
                Log.w(TAG, "POST /stocktake failed: ${e.message}")
                _state.value = _state.value.copy(
                    isCreating = false,
                    error = "Network error — check your connection",
                )
            }
        }
    }

    // ── Session actions ───────────────────────────────────────────────────────

    fun cancelSession(id: Int) {
        viewModelScope.launch {
            try {
                stocktakeApi.cancelById(id)
                // Reload to reflect server status change
                loadSessions()
            } catch (e: Exception) {
                Log.w(TAG, "POST /stocktake/$id/cancel failed: ${e.message}")
                _state.value = _state.value.copy(error = "Failed to cancel session")
            }
        }
    }

    // ── One-shot navigation ───────────────────────────────────────────────────

    fun consumeCreatedSessionId() {
        _state.value = _state.value.copy(createdSessionId = null)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    companion object {
        private const val TAG = "StocktakeListVM"
    }
}
