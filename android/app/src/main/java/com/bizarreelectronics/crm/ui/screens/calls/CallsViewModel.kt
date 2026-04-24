package com.bizarreelectronics.crm.ui.screens.calls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.CallLogEntry
import com.bizarreelectronics.crm.data.remote.api.VoiceApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ── UI states ─────────────────────────────────────────────────────────────────

data class CallsUiState(
    val calls: List<CallLogEntry> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val directionFilter: String = "All",     // All | Inbound | Outbound | Missed
    val error: String? = null,
    val notConfigured: Boolean = false,
    /** Staff+ can initiate VoIP calls; viewer role cannot. */
    val canInitiateCalls: Boolean = false,
    val actionMessage: String? = null,
)

data class CallDetailUiState(
    val entry: CallLogEntry? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val transcription: String? = null,
    val transcriptionLoading: Boolean = false,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class CallsViewModel @Inject constructor(
    private val voiceApi: VoiceApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(CallsUiState())
    val state = _state.asStateFlow()

    private val _detailState = MutableStateFlow(CallDetailUiState())
    val detailState = _detailState.asStateFlow()

    init {
        // §42.2 — role-gate call initiation to staff+
        val role = authPreferences.userRole ?: "viewer"
        val canInitiate = role in listOf("admin", "manager", "staff")
        _state.value = _state.value.copy(canInitiateCalls = canInitiate)
        loadCalls()
    }

    // ── List ─────────────────────────────────────────────────────────────────

    fun loadCalls() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val filters = buildMap<String, String> {
                val dir = _state.value.directionFilter
                if (dir != "All") put("direction", dir.lowercase())
                put("limit", "50")
            }
            runCatching { voiceApi.listCalls(filters) }
                .onSuccess { resp ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        calls = resp.data?.items ?: emptyList(),
                    )
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        notConfigured = is404,
                        error = if (is404) null else (e.message ?: "Failed to load calls"),
                    )
                }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadCalls()
    }

    fun onDirectionFilterChanged(dir: String) {
        _state.value = _state.value.copy(directionFilter = dir)
        loadCalls()
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    // ── Detail ───────────────────────────────────────────────────────────────

    fun loadCallDetail(id: Long) {
        viewModelScope.launch {
            _detailState.value = CallDetailUiState(isLoading = true)
            runCatching { voiceApi.getCall(id) }
                .onSuccess { resp ->
                    _detailState.value = CallDetailUiState(entry = resp.data)
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _detailState.value = CallDetailUiState(
                        isLoading = false,
                        error = if (is404) "VoIP not configured on this server" else (e.message ?: "Failed to load call"),
                    )
                }
        }
    }

    fun loadTranscription(callId: Long) {
        viewModelScope.launch {
            _detailState.value = _detailState.value.copy(transcriptionLoading = true)
            runCatching { voiceApi.getTranscription(callId) }
                .onSuccess { resp ->
                    _detailState.value = _detailState.value.copy(
                        transcriptionLoading = false,
                        transcription = resp.data?.text ?: "Transcription not available",
                    )
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _detailState.value = _detailState.value.copy(
                        transcriptionLoading = false,
                        transcription = if (is404) "Transcription not available on this server" else "Failed to load transcription",
                    )
                }
        }
    }
}
