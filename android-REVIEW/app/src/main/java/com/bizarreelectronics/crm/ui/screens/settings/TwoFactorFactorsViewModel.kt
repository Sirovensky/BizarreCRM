package com.bizarreelectronics.crm.ui.screens.settings

// §2.18 L417-L426 — ViewModel for Manage 2FA Factors settings screen.
//
// State machine:
//   Idle          → initial; never rendered (transitions to Loading immediately).
//   Loading       → GET /auth/2fa/factors in-flight.
//   Content(list) → factor list received; screen shows enrolled + available sections.
//   NotSupported  → server returned 404; screen shows "not available" message.
//   Error(err)    → network/server failure; inline error card with Retry.
//
// Enroll actions:
//   enrollFactor("totp")         → navigates caller to existing 2FA enroll QR path
//                                   (reuses commit cd36e98 path via [ToastEvent.NavigateToTotpEnroll]).
//   enrollFactor("sms")          → emits [ToastEvent.PromptSmsPhone]; caller collects + shows dialog.
//   enrollFactor("hardware_key") → emits [ToastEvent.ComingSoon] (Credential Manager deferred).
//   enrollFactor("passkey")      → emits [ToastEvent.ComingSoon] (Credential Manager deferred).
//
// USER DIRECTIVE 2026-04-23: "Disable 2FA" UI is PROHIBITED. No "delete factor"
// action must be added anywhere in this screen or its ViewModel.
// KDoc: per product decision logged in ActionPlan §2.18 line 304 [blocked] —
//       factor disable is off-limits in the Android UI. Enroll/upgrade only.

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorFactorDto
import com.bizarreelectronics.crm.util.AppError
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

sealed interface TwoFactorFactorsUiState {
    /** Never rendered; transitions to Loading on init. */
    data object Idle : TwoFactorFactorsUiState

    /** GET /auth/2fa/factors in-flight. */
    data object Loading : TwoFactorFactorsUiState

    /**
     * Factor list received.
     * @param factors All factors currently enrolled for this user.
     */
    data class Content(val factors: List<TwoFactorFactorDto>) : TwoFactorFactorsUiState

    /**
     * Server returned 404 — factor management endpoint not present on this build.
     * Screen shows informational "not available on this server version" card.
     */
    data object NotSupported : TwoFactorFactorsUiState

    /** Network or unexpected server failure. */
    data class Error(val error: AppError) : TwoFactorFactorsUiState
}

// ---------------------------------------------------------------------------
// One-shot events (toast / navigation)
// ---------------------------------------------------------------------------

/**
 * One-shot events emitted via [Channel] so they are consumed exactly once
 * even across recompositions.
 */
sealed interface TwoFactorFactorsEvent {
    /**
     * Navigate caller to the existing TOTP enroll QR path (commit cd36e98).
     * The screen itself does not navigate — it emits this event and the host
     * nav graph handles it.
     */
    data object NavigateToTotpEnroll : TwoFactorFactorsEvent

    /**
     * Prompt the user to enter a phone number before the SMS factor enroll
     * POST is dispatched. Caller shows a dialog and calls [enrollSmsWithPhone].
     */
    data object PromptSmsPhone : TwoFactorFactorsEvent

    /**
     * Passkey / hardware key enroll requested. Credential Manager integration
     * is deferred — show bottom sheet stub with "coming soon" message.
     * @param type "passkey" or "hardware_key"
     */
    data class ComingSoon(val type: String) : TwoFactorFactorsEvent

    /** Generic transient message (snackbar). */
    data class Toast(val message: String) : TwoFactorFactorsEvent
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class TwoFactorFactorsViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<TwoFactorFactorsUiState>(TwoFactorFactorsUiState.Idle)
    val uiState: StateFlow<TwoFactorFactorsUiState> = _uiState.asStateFlow()

    private val _events = Channel<TwoFactorFactorsEvent>(Channel.BUFFERED)

    /** Collect this in the composable with [receiveAsFlow] to process one-shot events. */
    val events = _events.receiveAsFlow()

    init {
        refresh()
    }

    // ---------------------------------------------------------------------------
    // Data loading
    // ---------------------------------------------------------------------------

    /**
     * Loads the factor list from GET /auth/2fa/factors.
     *
     * On success → [TwoFactorFactorsUiState.Content].
     * On 404    → [TwoFactorFactorsUiState.NotSupported].
     * On error  → [TwoFactorFactorsUiState.Error].
     */
    fun refresh() {
        _uiState.value = TwoFactorFactorsUiState.Loading
        viewModelScope.launch {
            try {
                val response = authApi.listFactors()
                val factors = response.data
                if (response.success && factors != null) {
                    _uiState.value = TwoFactorFactorsUiState.Content(factors)
                } else {
                    _uiState.value = TwoFactorFactorsUiState.Error(
                        AppError.Server(
                            status = 0,
                            serverMessage = response.message ?: "Server returned no factor data.",
                            requestId = null,
                        )
                    )
                }
            } catch (e: HttpException) {
                _uiState.value = when (e.code()) {
                    404 -> TwoFactorFactorsUiState.NotSupported
                    else -> TwoFactorFactorsUiState.Error(AppError.from(e))
                }
            } catch (e: IOException) {
                _uiState.value = TwoFactorFactorsUiState.Error(AppError.from(e))
            } catch (e: Exception) {
                _uiState.value = TwoFactorFactorsUiState.Error(AppError.from(e))
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Enroll actions
    // ---------------------------------------------------------------------------

    /**
     * Dispatches the enroll intent for the given [type].
     *
     * - "totp"         → emits [TwoFactorFactorsEvent.NavigateToTotpEnroll].
     *                    Caller navigates to the existing QR enroll step (cd36e98).
     * - "sms"          → emits [TwoFactorFactorsEvent.PromptSmsPhone].
     *                    Caller shows a phone-number dialog, then calls [enrollSmsWithPhone].
     * - "passkey"
     * - "hardware_key" → emits [TwoFactorFactorsEvent.ComingSoon].
     *                    Credential Manager API integration is deferred.
     * - other          → emits a Toast indicating an unsupported type. [~] path.
     *
     * NOTE: No "delete" / "disable" action is present here by policy.
     * See USER DIRECTIVE 2026-04-23 at the top of this file.
     */
    fun enrollFactor(type: String) {
        viewModelScope.launch {
            when (type) {
                "totp" -> _events.send(TwoFactorFactorsEvent.NavigateToTotpEnroll)
                "sms" -> _events.send(TwoFactorFactorsEvent.PromptSmsPhone)
                "passkey", "hardware_key" -> _events.send(TwoFactorFactorsEvent.ComingSoon(type))
                else -> _events.send(
                    TwoFactorFactorsEvent.Toast("Factor type \"$type\" is not supported.")
                )
            }
        }
    }

    /**
     * Called after the user confirms a phone number for SMS factor enrollment.
     *
     * Posts { type: "sms", phone: [phoneE164] } to /auth/2fa/factors/enroll.
     * On success → emits Toast("Check your phone — enter the OTP to complete SMS enroll.").
     *              Caller should surface a follow-up OTP entry dialog.
     * On 404    → emits Toast indicating the endpoint is not available.
     * On error  → emits Toast with error message.
     */
    fun enrollSmsWithPhone(phoneE164: String) {
        if (phoneE164.isBlank()) return
        viewModelScope.launch {
            try {
                val body = mapOf("type" to "sms", "phone" to phoneE164)
                val response = authApi.enrollFactor(body)
                if (response.success) {
                    _events.send(
                        TwoFactorFactorsEvent.Toast(
                            "Check your phone — enter the OTP to complete SMS enroll."
                        )
                    )
                    refresh()
                } else {
                    _events.send(
                        TwoFactorFactorsEvent.Toast(
                            response.message ?: "SMS factor enroll failed."
                        )
                    )
                }
            } catch (e: HttpException) {
                val msg = when (e.code()) {
                    404 -> "SMS factor enroll is not available on this server version."
                    else -> "SMS enroll failed (HTTP ${e.code()})."
                }
                _events.send(TwoFactorFactorsEvent.Toast(msg))
            } catch (e: IOException) {
                _events.send(TwoFactorFactorsEvent.Toast("Network error. Please try again."))
            } catch (e: Exception) {
                _events.send(TwoFactorFactorsEvent.Toast(e.localizedMessage ?: "Unknown error."))
            }
        }
    }
}
