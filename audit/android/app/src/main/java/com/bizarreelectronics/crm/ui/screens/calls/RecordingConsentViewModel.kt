package com.bizarreelectronics.crm.ui.screens.calls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.RecordingConfigData
import com.bizarreelectronics.crm.data.remote.api.RecordingConsentRequest
import com.bizarreelectronics.crm.data.remote.api.VoiceApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ── UI state ──────────────────────────────────────────────────────────────────

data class RecordingConsentUiState(
    val isLoading: Boolean = true,
    val config: RecordingConfigData? = null,
    val consentGiven: Boolean? = null,
    val isSaving: Boolean = false,
    val error: String? = null,
    val actionMessage: String? = null,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

/**
 * §42.3 — Backing VM for CallRecordingConsentScreen.
 *
 * Loads the tenant recording config (GET /voice/recording-config) and
 * posts per-session consent decisions (POST /voice/recording-consent).
 *
 * 404 from recording-config → recording not configured on this server;
 * the screen renders in a "not configured" state and all consent actions
 * are hidden.
 */
@HiltViewModel
class RecordingConsentViewModel @Inject constructor(
    private val voiceApi: VoiceApi,
) : ViewModel() {

    private val _state = MutableStateFlow(RecordingConsentUiState())
    val state = _state.asStateFlow()

    fun loadRecordingConfig(callId: Long) {
        viewModelScope.launch {
            _state.value = RecordingConsentUiState(isLoading = true)
            runCatching { voiceApi.getRecordingConfig() }
                .onSuccess { resp ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        config = resp.data,
                    )
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _state.value = _state.value.copy(
                        isLoading = false,
                        config = if (is404) RecordingConfigData(
                            enabled = false,
                            two_party_required = false,
                            announcement_url = null,
                        ) else null,
                        error = if (is404) null else (e.message ?: "Failed to load recording config"),
                    )
                }
        }
    }

    fun saveConsent(callId: Long, consented: Boolean) {
        _state.value = _state.value.copy(isSaving = true)
        viewModelScope.launch {
            runCatching {
                voiceApi.postRecordingConsent(RecordingConsentRequest(call_id = callId, consented = consented))
            }.onSuccess {
                _state.value = _state.value.copy(
                    isSaving = false,
                    consentGiven = consented,
                    actionMessage = if (consented) "Recording consent given" else "Recording consent withdrawn",
                )
            }.onFailure { e ->
                _state.value = _state.value.copy(
                    isSaving = false,
                    actionMessage = "Failed to save consent: ${e.message ?: "Unknown error"}",
                )
            }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}
