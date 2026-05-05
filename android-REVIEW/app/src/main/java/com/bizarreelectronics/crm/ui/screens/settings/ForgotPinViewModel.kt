package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinConfirm
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinRequest
import com.bizarreelectronics.crm.util.Argon2idHasher
import com.bizarreelectronics.crm.util.DeepLinkBus
import com.bizarreelectronics.crm.util.PinBlocklist
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * §2.15 L387-L388 — Forgot-PIN email reset ViewModel.
 *
 * ## State machine
 *
 * ```
 * Idle ──requestEmailReset()──► RequestingEmail ──(ok)──► EmailSent
 *                                                └─(404)──► FeatureDisabled
 *                                                └─(err)──► Error
 *
 * EmailSent ──[deep-link token arrives in DeepLinkBus]──► SettingPin
 *
 * SettingPin ──onDigit() × pinLength──► submitNewPin()
 *               ├─(blocklist)──► Error          (stays pinnable)
 *               ├─(ok)──► Success               (local hash updated)
 *               ├─(404)──► FeatureDisabled
 *               └─(err)──► Error
 * ```
 *
 * ## Self-hosted tenant note
 *
 * Email server may be absent on self-hosted deployments. 404 from either
 * endpoint maps to [UiState.FeatureDisabled] which surfaces the
 * "Ask admin to reset from Employees" fallback copy.
 *
 * ## Security
 *
 * - [submitNewPin] validates via [PinBlocklist.isBlocked] BEFORE the network
 *   call so the user gets instant feedback without a round-trip.
 * - On success, [PinPreferences.setPinHash] is called immediately so the
 *   offline-verify path has an up-to-date mirror.
 * - [ForgotPinConfirm.newPin] is never logged (see DTO KDoc).
 *
 * ## Testability
 *
 * All side-effects on [PinPreferences] are isolated in [commitPin], which is
 * `internal open` so unit tests can subclass and override it without needing
 * EncryptedSharedPreferences (an Android-only dependency).
 */
@HiltViewModel
class ForgotPinViewModel @Inject constructor(
    private val authApi: AuthApi,
    private val pinPreferences: PinPreferences,
    private val deepLinkBus: DeepLinkBus,
) : ViewModel() {

    // ── UI state ─────────────────────────────────────────────────────────────

    sealed interface UiState {
        /** Initial state — email input form shown. */
        data object Idle : UiState

        /** Waiting for POST /auth/forgot-pin/request response. */
        data object RequestingEmail : UiState

        /** Email dispatched; waiting for user to tap the link from their inbox. */
        data object EmailSent : UiState

        /**
         * Deep-link token received. PIN-setup keypad shown.
         * [entered] accumulates digits as the user types.
         */
        data class SettingPin(val token: String, val entered: String = "") : UiState

        /** PIN confirmed and committed — flow complete. */
        data object Success : UiState

        /**
         * Server returned 404 — email feature disabled on this tenant.
         * UI shows "Ask admin to reset from the Employees screen".
         */
        data object FeatureDisabled : UiState

        /** Network or server error with a user-facing [message]. */
        data class Error(val message: String) : UiState
    }

    private val _state = MutableStateFlow<UiState>(UiState.Idle)
    val state = _state.asStateFlow()

    init {
        // Collect deep-link tokens published by MainActivity when
        // `bizarrecrm://forgot-pin/<token>` is received.
        viewModelScope.launch {
            deepLinkBus.pendingForgotPinToken.collect { token ->
                if (token == null) return@collect
                val current = _state.value
                // Accept token in Idle (app opened via link cold) or EmailSent (normal path).
                if (current is UiState.Idle || current is UiState.EmailSent) {
                    _state.value = UiState.SettingPin(token = token)
                }
                deepLinkBus.consumeForgotPinToken()
            }
        }
    }

    /**
     * Dispatches POST /auth/forgot-pin/request for [email].
     *
     * Transitions:
     *   [UiState.Idle] → [UiState.RequestingEmail] → [UiState.EmailSent]
     *   or [UiState.FeatureDisabled] / [UiState.Error].
     */
    fun requestEmailReset(email: String) {
        if (email.isBlank()) {
            _state.value = UiState.Error("Please enter your email address.")
            return
        }
        viewModelScope.launch {
            _state.value = UiState.RequestingEmail
            runCatching { authApi.requestForgotPin(ForgotPinRequest(email.trim())) }
                .onSuccess { _state.value = UiState.EmailSent }
                .onFailure { t ->
                    _state.value = when {
                        t is HttpException && t.code() == 404 -> UiState.FeatureDisabled
                        else -> UiState.Error(t.message ?: "Request failed. Try again.")
                    }
                }
        }
    }

    /**
     * Called when the user appends a digit to their new PIN.
     *
     * Operates only in [UiState.SettingPin]. Auto-submits when [pinLength]
     * digits have been entered.
     */
    fun onDigit(c: Char, pinLength: Int = DEFAULT_PIN_LENGTH) {
        val current = _state.value as? UiState.SettingPin ?: return
        val next = (current.entered + c).take(pinLength)
        _state.value = current.copy(entered = next)
        if (next.length == pinLength) {
            submitNewPin(current.token, next)
        }
    }

    /** Removes the last entered digit. */
    fun onBackspace() {
        val current = _state.value as? UiState.SettingPin ?: return
        if (current.entered.isNotEmpty()) {
            _state.value = current.copy(entered = current.entered.dropLast(1))
        }
    }

    /**
     * Posts the confirmed PIN to the server.
     *
     * Validates against [PinBlocklist] first (instant feedback, no round-trip).
     * On success, calls [commitPin] to write the local hash mirror.
     *
     * SECURITY: [newPin] is never logged — matches the contract in [ForgotPinConfirm].
     */
    private fun submitNewPin(token: String, newPin: String) {
        if (PinBlocklist.isBlocked(newPin)) {
            _state.value = UiState.Error(
                "This PIN is too common. Choose a less predictable one.",
            )
            return
        }
        viewModelScope.launch {
            runCatching {
                authApi.confirmForgotPin(ForgotPinConfirm(token = token, newPin = newPin))
            }
                .onSuccess {
                    commitPin(newPin)
                    _state.value = UiState.Success
                }
                .onFailure { t ->
                    _state.value = when {
                        t is HttpException && t.code() == 404 -> UiState.FeatureDisabled
                        else -> UiState.Error(t.message ?: "PIN reset failed. Try again.")
                    }
                }
        }
    }

    /**
     * Writes the new PIN's hash mirror and schedules the 90-day rotation reminder.
     *
     * `internal open` so unit tests can subclass [ForgotPinViewModel] and override
     * this method without needing Android's EncryptedSharedPreferences.
     *
     * SECURITY: [newPin] is never logged here or in [Argon2idHasher.hash].
     */
    internal open fun commitPin(newPin: String) {
        val hash = Argon2idHasher.hash(newPin)
        pinPreferences.setPinHash(hash)
        pinPreferences.isPinSet = true
        pinPreferences.scheduleRotation()
    }

    /** Resets to [UiState.Idle] — lets the user re-enter their email. */
    fun reset() {
        _state.value = UiState.Idle
    }

    companion object {
        const val DEFAULT_PIN_LENGTH = 4
    }
}
