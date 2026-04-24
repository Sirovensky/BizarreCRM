package com.bizarreelectronics.crm.ui.screens.audit

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuditApi
import com.bizarreelectronics.crm.data.remote.api.AuditEntry
import com.bizarreelectronics.crm.ui.screens.audit.components.AuditFilter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * §52 — ViewModel for the Audit Logs screen.
 *
 * Features:
 *  - Cursor-paginated load via [AuditApi.getAuditLog].
 *  - Filter state ([AuditFilter]) drives reload on change.
 *  - Search query applied client-side against already-loaded items (server
 *    doesn't expose a free-text search param; filters are server-side).
 *  - 404 from the server is handled gracefully: empty state, no error toast.
 *  - Admin-role gate is enforced in [AuditLogsScreen]; VM itself is role-agnostic.
 */
@HiltViewModel
class AuditLogsViewModel @Inject constructor(
    private val auditApi: AuditApi,
) : ViewModel() {

    companion object {
        private const val TAG = "AuditLogsVM"
        private const val PAGE_SIZE = 50
    }

    // ─── Public state ────────────────────────────────────────────────────────

    private val _items = MutableStateFlow<List<AuditEntry>>(emptyList())
    val items: StateFlow<List<AuditEntry>> = _items.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _hasMore = MutableStateFlow(true)
    val hasMore: StateFlow<Boolean> = _hasMore.asStateFlow()

    private val _filter = MutableStateFlow(AuditFilter())
    val filter: StateFlow<AuditFilter> = _filter.asStateFlow()

    private val _search = MutableStateFlow("")
    val search: StateFlow<String> = _search.asStateFlow()

    /** Entry selected for full-diff dialog; null = dialog closed. */
    private val _selectedEntry = MutableStateFlow<AuditEntry?>(null)
    val selectedEntry: StateFlow<AuditEntry?> = _selectedEntry.asStateFlow()

    // ─── Pagination cursor ───────────────────────────────────────────────────

    private var nextCursor: String? = null
    private var loadJob: Job? = null

    // ─── Init ────────────────────────────────────────────────────────────────

    init {
        loadFirstPage()
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    fun updateFilter(newFilter: AuditFilter) {
        if (newFilter == _filter.value) return
        _filter.value = newFilter
        loadFirstPage()
    }

    fun updateSearch(query: String) {
        _search.value = query
    }

    fun selectEntry(entry: AuditEntry?) {
        _selectedEntry.value = entry
    }

    fun loadFirstPage() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            nextCursor = null
            _hasMore.value = true
            try {
                val f = _filter.value
                val response = auditApi.getAuditLog(
                    actor = f.actor.ifBlank { null },
                    entityType = f.entityType.ifBlank { null },
                    action = f.action.ifBlank { null },
                    from = f.from.ifBlank { null },
                    to = f.to.ifBlank { null },
                    cursor = null,
                    limit = PAGE_SIZE,
                )
                val page = response.data ?: run {
                    _items.value = emptyList()
                    _hasMore.value = false
                    return@launch
                }
                _items.value = page.items
                nextCursor = page.nextCursor
                _hasMore.value = page.nextCursor != null
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Endpoint not yet deployed — show empty state silently.
                    _items.value = emptyList()
                    _hasMore.value = false
                } else {
                    _error.value = "Failed to load audit log (HTTP ${e.code()})"
                    Log.w(TAG, "loadFirstPage HTTP ${e.code()}", e)
                }
            } catch (e: Exception) {
                _error.value = "Failed to load audit log"
                Log.e(TAG, "loadFirstPage error", e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun loadNextPage() {
        val cursor = nextCursor ?: return
        if (_isLoadingMore.value) return
        viewModelScope.launch {
            _isLoadingMore.value = true
            try {
                val f = _filter.value
                val response = auditApi.getAuditLog(
                    actor = f.actor.ifBlank { null },
                    entityType = f.entityType.ifBlank { null },
                    action = f.action.ifBlank { null },
                    from = f.from.ifBlank { null },
                    to = f.to.ifBlank { null },
                    cursor = cursor,
                    limit = PAGE_SIZE,
                )
                val page = response.data ?: return@launch
                _items.value = _items.value + page.items
                nextCursor = page.nextCursor
                _hasMore.value = page.nextCursor != null
            } catch (e: HttpException) {
                if (e.code() != 404) {
                    Log.w(TAG, "loadNextPage HTTP ${e.code()}", e)
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadNextPage error", e)
            } finally {
                _isLoadingMore.value = false
            }
        }
    }
}
