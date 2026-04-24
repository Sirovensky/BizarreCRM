package com.bizarreelectronics.crm.ui.screens.activity

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ActivityApi
import com.bizarreelectronics.crm.data.remote.dto.ActivityEventDto
import com.bizarreelectronics.crm.service.WebSocketService
import com.bizarreelectronics.crm.ui.screens.activity.components.ActivityFilter
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §3.16 L592-L599 — ViewModel for the full Activity Feed screen.
 *
 * Features:
 *  - Cursor-based infinite scroll via [ActivityApi.getActivity].
 *  - Real-time prepend via WebSocket `activity:new` event.
 *  - [ActivityFilter] multi-select filtering (types + myActivityOnly).
 *  - Emoji reactions via [ActivityApi.postReaction]; 404 silently tolerated.
 *  - Defense-in-depth PII redaction via [redactText] (server sends pre-rendered text).
 */
@HiltViewModel
class ActivityFeedViewModel @Inject constructor(
    private val activityApi: ActivityApi,
    private val webSocketService: WebSocketService,
    private val authPreferences: AuthPreferences,
    private val gson: Gson,
) : ViewModel() {

    // ─── UI state ────────────────────────────────────────────────────────────

    private val _items = MutableStateFlow<List<ActivityEventDto>>(emptyList())
    val items: StateFlow<List<ActivityEventDto>> = _items.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _filter = MutableStateFlow(ActivityFilter())
    val filter: StateFlow<ActivityFilter> = _filter.asStateFlow()

    private val _hasMore = MutableStateFlow(true)
    val hasMore: StateFlow<Boolean> = _hasMore.asStateFlow()

    // ─── Pagination state ────────────────────────────────────────────────────

    private var nextCursor: String? = null
    private var loadMoreJob: Job? = null

    // ─── Init ────────────────────────────────────────────────────────────────

    init {
        loadFirstPage()
        subscribeToWebSocket()
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    /** Called when the user changes the filter chip selection. */
    fun updateFilter(newFilter: ActivityFilter) {
        if (newFilter == _filter.value) return
        _filter.value = newFilter
        loadFirstPage()
    }

    /** Load the first page (or reload after filter change). */
    fun refresh() = loadFirstPage()

    /**
     * Called when the LazyColumn is near the bottom.
     * No-op if already loading, no more pages, or a load is in flight.
     */
    fun loadMore() {
        if (_isLoadingMore.value || !_hasMore.value || _isLoading.value) return
        val cursor = nextCursor ?: return // null means we haven't loaded first page yet
        loadMoreJob?.cancel()
        loadMoreJob = viewModelScope.launch {
            _isLoadingMore.value = true
            try {
                val f = _filter.value
                val response = activityApi.getActivity(
                    cursor = cursor,
                    limit = PAGE_SIZE,
                    types = f.typesParam(),
                    employee = if (f.myActivityOnly) authPreferences.username else null,
                )
                val page = response.data
                if (page == null) {
                    _hasMore.value = false
                    return@launch
                }
                val redacted = page.items.map { it.withRedactedText() }
                _items.value = _items.value + redacted
                nextCursor = page.nextCursor
                _hasMore.value = page.nextCursor != null
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _hasMore.value = false
                } else {
                    Log.w(TAG, "loadMore error ${e.code()}: ${e.message()}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "loadMore error: ${e.message}")
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    /**
     * §3.16 L596 — Post a reaction emoji for a specific event.
     *
     * Optimistically updates the local count.
     * 404 is silently tolerated (server predates reactions endpoint).
     */
    fun react(eventId: Long, emoji: String) {
        // Optimistic update
        _items.value = _items.value.map { event ->
            if (event.id != eventId) return@map event
            val updated = event.reactions.toMutableMap()
            updated[emoji] = (updated[emoji] ?: 0) + 1
            event.copy(reactions = updated)
        }

        viewModelScope.launch {
            try {
                activityApi.postReaction(eventId, mapOf("emoji" to emoji))
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) return@launch // Silently tolerated
                // Roll back optimistic update on other errors
                rollBackReaction(eventId, emoji)
                Log.w(TAG, "react error ${e.code()}")
            } catch (_: Exception) {
                rollBackReaction(eventId, emoji)
            }
        }
    }

    fun clearError() {
        _error.value = null
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    private fun loadFirstPage() {
        loadMoreJob?.cancel()
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            _items.value = emptyList()
            nextCursor = null
            _hasMore.value = true
            try {
                val f = _filter.value
                val response = activityApi.getActivity(
                    cursor = null,
                    limit = PAGE_SIZE,
                    types = f.typesParam(),
                    employee = if (f.myActivityOnly) authPreferences.username else null,
                )
                val page = response.data
                if (page == null) {
                    _hasMore.value = false
                } else {
                    _items.value = page.items.map { it.withRedactedText() }
                    nextCursor = page.nextCursor
                    _hasMore.value = page.nextCursor != null
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    // Server predates /activity endpoint; show empty state
                    _hasMore.value = false
                } else {
                    _error.value = "Failed to load activity (${e.code()})"
                }
            } catch (e: Exception) {
                _error.value = "Failed to load activity: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * §3.16 L592 — Subscribe to WebSocket `activity:new` events and prepend new
     * items to the list without disturbing the existing scroll position.
     */
    private fun subscribeToWebSocket() {
        viewModelScope.launch {
            webSocketService.events.collect { event ->
                if (event.type != "activity:new") return@collect
                try {
                    val data = gson.fromJson(event.data, Map::class.java)
                    val itemData = data["data"] as? Map<*, *> ?: return@collect
                    // Reconstruct a minimal ActivityEventDto from the WS payload
                    val newEvent = ActivityEventDto(
                        id = (itemData["id"] as? Double)?.toLong() ?: return@collect,
                        type = itemData["type"]?.toString() ?: "unknown",
                        actor = itemData["actor"]?.toString() ?: "",
                        verb = itemData["verb"]?.toString() ?: "",
                        subject = itemData["subject"]?.toString() ?: "",
                        text = (itemData["text"]?.toString() ?: "").redactPii(),
                        entityType = itemData["entity_type"]?.toString(),
                        entityId = (itemData["entity_id"] as? Double)?.toLong(),
                        timeAgo = itemData["time_ago"]?.toString() ?: "just now",
                        avatarInitials = itemData["avatar_initials"]?.toString(),
                        location = itemData["location"]?.toString(),
                        reactions = emptyMap(),
                    )
                    // Prepend — avoid duplicate if already fetched in first page
                    val current = _items.value
                    if (current.none { it.id == newEvent.id }) {
                        _items.value = listOf(newEvent) + current
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "activity:new parse error: ${e.message}")
                }
            }
        }
    }

    private fun rollBackReaction(eventId: Long, emoji: String) {
        _items.value = _items.value.map { event ->
            if (event.id != eventId) return@map event
            val updated = event.reactions.toMutableMap()
            val current = updated[emoji] ?: 0
            if (current <= 1) updated.remove(emoji) else updated[emoji] = current - 1
            event.copy(reactions = updated)
        }
    }

    private fun ActivityEventDto.withRedactedText(): ActivityEventDto =
        copy(text = text.redactPii())

    companion object {
        private const val TAG = "ActivityFeedVM"
        private const val PAGE_SIZE = 20

        /**
         * §3.16 L598 — Defense-in-depth PII redaction.
         *
         * The server pre-renders event text without raw PII, but as an extra
         * safeguard Android strips any residual email addresses and phone numbers
         * before display. Patterns are conservative to avoid false positives.
         */
        fun String.redactPii(): String {
            var out = this
            // Email addresses
            out = out.replace(Regex("[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}"), "[email]")
            // Phone numbers (US-style 10-digit and E.164): (555) 123-4567 / +15551234567 / 555-123-4567
            out = out.replace(
                Regex("(?:\\+?1[-. ]?)?(?:\\(?[0-9]{3}\\)?[-. ]?)[0-9]{3}[-. ]?[0-9]{4}"),
                "[phone]",
            )
            return out
        }
    }
}
