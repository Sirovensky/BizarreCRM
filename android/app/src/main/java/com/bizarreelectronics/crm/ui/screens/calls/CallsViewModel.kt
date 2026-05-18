package com.bizarreelectronics.crm.ui.screens.calls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.CallLogEntry
import com.bizarreelectronics.crm.data.remote.api.InitiateCallRequest
import com.bizarreelectronics.crm.data.remote.api.VoiceApi
import com.bizarreelectronics.crm.data.remote.api.VoicemailEntry
import com.bizarreelectronics.crm.util.CallerIdLookupHelper
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    /** §42.1 — resolved caller-ID names keyed by from_number */
    val callerIdNames: Map<String, String> = emptyMap(),
    /** §42.5 — dial-prompt visibility + pre-filled number */
    val showDialPrompt: Boolean = false,
    val dialPromptNumber: String = "",
    val dialPromptCustomerName: String? = null,
    val dialPromptCustomerId: Long? = null,
    /** §42.5 — recent numbers shown in the dial prompt (last 5 outbound) */
    val recentOutboundNumbers: List<String> = emptyList(),
    /** true while a POST /voice/call is in-flight */
    val isInitiatingCall: Boolean = false,
)

data class VoicemailUiState(
    val voicemails: List<VoicemailEntry> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val notConfigured: Boolean = false,
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
    private val callerIdLookupHelper: CallerIdLookupHelper,
) : ViewModel() {

    private val _state = MutableStateFlow(CallsUiState())
    val state = _state.asStateFlow()

    private val _detailState = MutableStateFlow(CallDetailUiState())
    val detailState = _detailState.asStateFlow()

    private val _voicemailState = MutableStateFlow(VoicemailUiState())
    val voicemailState = _voicemailState.asStateFlow()

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
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException
            // and paints a fake "Failed to load calls" banner on filter swap.
            // Switch to try/catch with explicit re-throw to preserve coroutine
            // cancellation; CancellationException returns early instead of
            // hitting onFailure.
            try {
                val resp = voiceApi.listCalls(filters)
                val items = resp.data?.items ?: emptyList()
                // §42.1 — resolve caller-ID names off the main thread
                val resolvedNames = withContext(Dispatchers.IO) {
                    items.mapNotNull { entry ->
                        // Only look up numbers that don't already have a server-provided name
                        if (entry.customer_name == null) {
                            val name = callerIdLookupHelper.lookupName(entry.from_number)
                            if (name != null) entry.from_number to name else null
                        } else null
                    }.toMap()
                }
                // Recent outbound numbers for §42.5 dial prompt
                val recentOutbound = items
                    .filter { it.direction == "outbound" }
                    .distinctBy { it.to_number }
                    .take(5)
                    .map { it.to_number }
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    calls = items,
                    callerIdNames = resolvedNames,
                    recentOutboundNumbers = recentOutbound,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
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

    // ── §42.5 Dial prompt (click-to-call from anywhere) ──────────────────────

    fun openDialPrompt(
        number: String = "",
        customerName: String? = null,
        customerId: Long? = null,
    ) {
        _state.value = _state.value.copy(
            showDialPrompt = true,
            dialPromptNumber = number,
            dialPromptCustomerName = customerName,
            dialPromptCustomerId = customerId,
        )
    }

    fun dismissDialPrompt() {
        _state.value = _state.value.copy(
            showDialPrompt = false,
            dialPromptNumber = "",
            dialPromptCustomerName = null,
            dialPromptCustomerId = null,
        )
    }

    fun updateDialPromptNumber(number: String) {
        _state.value = _state.value.copy(dialPromptNumber = number)
    }

    /**
     * §42.5 — Initiate a VoIP call via POST /voice/call.
     *
     * On success, launches [CallInProgressActivity] via [onLaunchCallActivity].
     * On 404 the tenant has no VoIP configured; falls back to ACTION_DIAL.
     */
    fun initiateVoipCall(
        number: String,
        customerId: Long? = null,
        onLaunchCallActivity: (callId: Long, callerName: String, number: String) -> Unit,
        onFallbackDial: (String) -> Unit,
    ) {
        if (!_state.value.canInitiateCalls) return
        // BUGHUNT-2026-05-17: re-entry guard. A fast double-tap on the Call
        // button could reach this VM method before Compose has had time to
        // recompose with `isInitiating = true` on the dial sheet's button
        // (the `enabled = !isInitiating` flag only blocks the *third* tap
        // after the first POST kicks off). Without this guard, two POST
        // /voice/call requests fire in parallel and the tenant is billed
        // for two outbound legs.
        if (_state.value.isInitiatingCall) return
        _state.value = _state.value.copy(isInitiatingCall = true)
        viewModelScope.launch {
            try {
                val resp = voiceApi.initiateCall(
                    InitiateCallRequest(to_number = number, customer_id = customerId),
                )
                _state.value = _state.value.copy(isInitiatingCall = false, showDialPrompt = false)
                val session = resp.data
                if (session != null) {
                    onLaunchCallActivity(
                        session.call_id,
                        session.caller_id_name ?: number,
                        number,
                    )
                } else {
                    onFallbackDial(number)
                }
            } catch (e: CancellationException) {
                // BUGHUNT-2026-05-17: re-throw cancellation. The POST may
                // have already reached the SIP/VoIP provider and a call leg
                // is dialing out (billed). A "Call failed" toast would
                // tempt the user to re-tap, dialing a SECOND outbound leg.
                // Clear the in-flight flag so the VM is consistent after
                // scope cancellation, then propagate so structured
                // concurrency stays intact.
                _state.value = _state.value.copy(isInitiatingCall = false)
                throw e
            } catch (e: Exception) {
                _state.value = _state.value.copy(isInitiatingCall = false, showDialPrompt = false)
                val is404 = (e as? HttpException)?.code() == 404
                if (is404) {
                    // VoIP not configured — fall back to system dialer
                    onFallbackDial(number)
                } else {
                    _state.value = _state.value.copy(
                        actionMessage = "Call failed: ${e.message ?: "Unknown error"}",
                    )
                }
            }
        }
    }

    // ── §42.4 Voicemail ───────────────────────────────────────────────────────

    fun loadVoicemails(showAll: Boolean = false) {
        viewModelScope.launch {
            _voicemailState.value = _voicemailState.value.copy(isLoading = true, error = null)
            val filters = buildMap<String, String> {
                put("status", if (showAll) "all" else "new")
                put("limit", "25")
            }
            // BUGHUNT-2026-05-17: switch from runCatching to try/catch+rethrow.
            try {
                val resp = voiceApi.listVoicemails(filters)
                _voicemailState.value = _voicemailState.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    voicemails = resp.data?.items ?: emptyList(),
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val is404 = (e as? HttpException)?.code() == 404
                _voicemailState.value = _voicemailState.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    notConfigured = is404,
                    error = if (is404) null else (e.message ?: "Failed to load voicemails"),
                )
            }
        }
    }

    fun refreshVoicemails() {
        _voicemailState.value = _voicemailState.value.copy(isRefreshing = true)
        loadVoicemails()
    }

    fun markVoicemailHeard(id: Long) {
        viewModelScope.launch {
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException,
            // breaking structured concurrency. Switch to try/catch with
            // explicit re-throw so VM cancellation doesn't leak.
            try {
                voiceApi.markVoicemailHeard(id)
                _voicemailState.value = _voicemailState.value.copy(
                    voicemails = _voicemailState.value.voicemails.map { vm ->
                        if (vm.id == id) vm.copy(status = "heard") else vm
                    },
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Best-effort; keep silent
            }
        }
    }

    fun deleteVoicemail(id: Long) {
        viewModelScope.launch {
            // BUGHUNT-2026-05-17: same antipattern. Optimistic local
            // removal also moved INTO try so cancellation between server
            // ack and local update doesn't desync; on commit-then-cancel
            // the server already removed it, so we keep the local remove
            // consistent.
            try {
                voiceApi.deleteVoicemail(id)
                _voicemailState.value = _voicemailState.value.copy(
                    voicemails = _voicemailState.value.voicemails.filterNot { it.id == id },
                    actionMessage = "Voicemail deleted",
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Best-effort; keep silent
            }
        }
    }

    fun clearVoicemailActionMessage() {
        _voicemailState.value = _voicemailState.value.copy(actionMessage = null)
    }

    // ── Detail ───────────────────────────────────────────────────────────────

    fun loadCallDetail(id: Long) {
        viewModelScope.launch {
            _detailState.value = CallDetailUiState(isLoading = true)
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException.
            try {
                val resp = voiceApi.getCall(id)
                _detailState.value = CallDetailUiState(entry = resp.data)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
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
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException.
            try {
                val resp = voiceApi.getTranscription(callId)
                _detailState.value = _detailState.value.copy(
                    transcriptionLoading = false,
                    transcription = resp.data?.text ?: "Transcription not available",
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val is404 = (e as? HttpException)?.code() == 404
                _detailState.value = _detailState.value.copy(
                    transcriptionLoading = false,
                    transcription = if (is404) "Transcription not available on this server" else "Failed to load transcription",
                )
            }
        }
    }
}
