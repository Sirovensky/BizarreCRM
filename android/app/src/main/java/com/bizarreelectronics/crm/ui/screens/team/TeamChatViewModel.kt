package com.bizarreelectronics.crm.ui.screens.team

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TeamChatApi
import com.bizarreelectronics.crm.data.remote.api.TeamChatMessage
import com.bizarreelectronics.crm.data.remote.api.TeamChatReactionRequest
import com.bizarreelectronics.crm.data.remote.api.TeamChatRoom
import com.bizarreelectronics.crm.data.remote.api.TeamChatSendRequest
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.util.MentionUtil
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── List state ──────────────────────────────────────────────────────────────

data class TeamChatListUiState(
    val rooms: List<TeamChatRoom> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    /** null = not configured (show empty state). true = server returned 404. */
    val notConfigured: Boolean = false,
    val searchQuery: String = "",
)

// ─── Thread state ─────────────────────────────────────────────────────────────

data class TeamChatThreadUiState(
    val messages: List<TeamChatMessage> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val notConfigured: Boolean = false,
    val isSending: Boolean = false,
    val actionMessage: String? = null,
    /** Employees for @mention autocomplete. */
    val employees: List<EmployeeListItem> = emptyList(),
    /** Visible when the current compose text has a live @-trigger. */
    val mentionSuggestions: List<EmployeeListItem> = emptyList(),
    val roomName: String = "",
)

// ─── List ViewModel ──────────────────────────────────────────────────────────

@HiltViewModel
class TeamChatListViewModel @Inject constructor(
    private val teamChatApi: TeamChatApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(TeamChatListUiState())
    val state = _state.asStateFlow()

    private var rawRooms: List<TeamChatRoom> = emptyList()
    private var searchJob: Job? = null

    init { loadRooms() }

    fun loadRooms() {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = _state.value.rooms.isEmpty(),
                error = null,
                notConfigured = false,
            )
            if (!serverMonitor.isEffectivelyOnline.value) {
                _state.value = _state.value.copy(isLoading = false)
                return@launch
            }
            try {
                val response = teamChatApi.getRooms()
                rawRooms = response.data?.rooms ?: emptyList()
                _state.value = _state.value.copy(
                    rooms = applySearch(rawRooms, _state.value.searchQuery),
                    isLoading = false,
                    isRefreshing = false,
                )
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        notConfigured = true,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Could not load team chat",
                    )
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = "Could not load team chat",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadRooms()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300L)
            _state.value = _state.value.copy(
                rooms = applySearch(rawRooms, query),
            )
        }
    }

    private fun applySearch(rooms: List<TeamChatRoom>, query: String): List<TeamChatRoom> {
        val q = query.trim().lowercase()
        val sorted = rooms.sortedWith(
            compareByDescending<TeamChatRoom> { it.isPinned }
                .thenByDescending { it.lastMessageAt }
        )
        return if (q.isEmpty()) sorted
        else sorted.filter { it.name.lowercase().contains(q) || it.description?.lowercase()?.contains(q) == true }
    }
}

// ─── Thread ViewModel ────────────────────────────────────────────────────────

@HiltViewModel
class TeamChatThreadViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val teamChatApi: TeamChatApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    val roomId: String = checkNotNull(savedStateHandle["roomId"])
    val roomName: String = savedStateHandle["roomName"] ?: ""

    private val _state = MutableStateFlow(TeamChatThreadUiState(roomName = roomName))
    val state = _state.asStateFlow()

    /** Current compose TextFieldValue.text tracked for mention detection. */
    private var _composeText: String = ""

    init { loadMessages() }

    fun loadMessages(cursor: String? = null) {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = _state.value.messages.isEmpty(),
                error = null,
                notConfigured = false,
            )
            if (!serverMonitor.isEffectivelyOnline.value) {
                _state.value = _state.value.copy(isLoading = false)
                return@launch
            }
            try {
                val response = teamChatApi.getMessages(roomId, after = cursor)
                val incoming = response.data?.messages ?: emptyList()
                val merged = if (cursor == null) incoming
                else _state.value.messages + incoming
                _state.value = _state.value.copy(
                    messages = merged,
                    isLoading = false,
                    isRefreshing = false,
                )
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        notConfigured = true,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Could not load messages",
                    )
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = "Could not load messages",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadMessages()
    }

    fun sendMessage(body: String, mentionIds: List<Long> = emptyList()) {
        if (body.isBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSending = true)
            try {
                val response = teamChatApi.sendMessage(
                    roomId,
                    TeamChatSendRequest(body = body, mentions = mentionIds),
                )
                val sent = response.data
                if (sent != null) {
                    _state.value = _state.value.copy(
                        messages = listOf(sent) + _state.value.messages,
                        isSending = false,
                        actionMessage = null,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSending = false,
                        actionMessage = "Message sent",
                    )
                    loadMessages()
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    isSending = false,
                    actionMessage = "Failed to send message",
                )
            }
        }
    }

    /** Toggle a reaction; 404-tolerant. */
    fun toggleReaction(messageId: String, emoji: String) {
        viewModelScope.launch {
            try {
                teamChatApi.toggleReaction(roomId, messageId, TeamChatReactionRequest(emoji))
                loadMessages()
            } catch (_: Exception) { /* 404-tolerant */ }
        }
    }

    /** Called when compose text changes — triggers mention suggestion filtering. */
    fun onComposeTextChanged(text: String, employees: List<EmployeeListItem>) {
        _composeText = text
        val query = MentionUtil.mentionQueryAtCursor(
            androidx.compose.ui.text.input.TextFieldValue(text)
        )
        val suggestions = if (query != null && query.length >= 1) {
            val q = query.lowercase()
            employees.filter { emp ->
                val fullName = listOfNotNull(emp.firstName, emp.lastName)
                    .joinToString(" ").lowercase()
                fullName.contains(q) || emp.username?.lowercase()?.contains(q) == true
            }.take(5)
        } else {
            emptyList()
        }
        _state.value = _state.value.copy(mentionSuggestions = suggestions)
    }

    /** Called when a WebSocket `team-chat:message:<roomId>` event arrives. */
    fun onWebSocketMessage(message: TeamChatMessage) {
        val existing = _state.value.messages.any { it.id == message.id }
        if (!existing) {
            _state.value = _state.value.copy(
                messages = listOf(message) + _state.value.messages,
            )
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}
