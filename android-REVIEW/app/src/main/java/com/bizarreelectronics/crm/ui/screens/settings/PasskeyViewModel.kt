package com.bizarreelectronics.crm.ui.screens.settings

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.PasskeyCredentialInfo
import com.bizarreelectronics.crm.data.remote.dto.PasskeyRegisterFinishRequest
import com.bizarreelectronics.crm.util.PasskeyManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * §2.22 — ViewModel for [PasskeyScreen].
 *
 * State machine:
 *  - [Idle]         — list loaded (possibly empty).
 *  - [Loading]      — network op in flight.
 *  - [Enrolling]    — CredentialManager create sheet is open.
 *  - [Error]        — transient snackbar error message.
 *  - [Unsupported]  — device API < 28 or CredentialManager unavailable.
 *
 * Passkey operations follow a begin → create/get → finish server handshake:
 *  begin  : POST /auth/passkey/register/begin  (server issues challenge JSON)
 *  create : [PasskeyManager.enrollPasskey]     (system credential sheet)
 *  finish : POST /auth/passkey/register/finish (server validates + stores)
 */
@HiltViewModel
class PasskeyViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    // ── State ──────────────────────────────────────────────────────────────

    data class UiState(
        val passkeys: List<PasskeyCredentialInfo> = emptyList(),
        val isLoading: Boolean = false,
        val isEnrolling: Boolean = false,
        val isUnsupported: Boolean = false,
        val snackbarMessage: String? = null,
        val deleteConfirmId: String? = null,
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    // ── Init ───────────────────────────────────────────────────────────────

    init {
        if (!PasskeyManager.isSupported()) {
            _uiState.value = _uiState.value.copy(isUnsupported = true)
        } else {
            loadPasskeys()
        }
    }

    // ── Load ───────────────────────────────────────────────────────────────

    fun loadPasskeys() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            try {
                val response = authApi.listPasskeys()
                val items = response.data ?: emptyList()
                _uiState.value = _uiState.value.copy(passkeys = items, isLoading = false)
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    // Server predates passkey support — treat as empty list.
                    _uiState.value = _uiState.value.copy(passkeys = emptyList(), isLoading = false)
                } else {
                    Timber.e(e, "listPasskeys HTTP %d", e.code())
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        snackbarMessage = "Could not load passkeys (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "listPasskeys failed")
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    snackbarMessage = "Could not load passkeys: ${e.message}",
                )
            }
        }
    }

    // ── Enroll ─────────────────────────────────────────────────────────────

    /**
     * Starts the passkey enrollment flow for [activity].
     *
     * 1. POST /auth/passkey/register/begin → challenge JSON.
     * 2. [PasskeyManager.enrollPasskey] → system credential sheet.
     * 3. POST /auth/passkey/register/finish → server stores credential.
     * 4. Reload list.
     */
    fun startEnrollment(activity: Activity) {
        if (_uiState.value.isEnrolling) return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isEnrolling = true)
            try {
                // Step 1: get challenge from server.
                val beginResponse = authApi.beginPasskeyRegistration()
                val challengeJson = beginResponse.data?.challengeJson
                    ?: throw Exception("Server returned no challenge JSON")

                // Step 2: show system credential sheet.
                val outcome = PasskeyManager.enrollPasskey(activity, challengeJson)

                when (outcome) {
                    is PasskeyManager.PasskeyOutcome.Success -> {
                        // CreatePublicKeyCredentialResponse.registrationResponseJson is the
                        // full attestation JSON ready to POST to /auth/passkey/register/finish.
                        val responseJson = outcome.data.registrationResponseJson
                        // Step 3: send attestation to server.
                        authApi.finishPasskeyRegistration(
                            PasskeyRegisterFinishRequest(responseJson = responseJson)
                        )
                        _uiState.value = _uiState.value.copy(
                            isEnrolling = false,
                            snackbarMessage = "Passkey added successfully",
                        )
                        loadPasskeys()
                    }
                    is PasskeyManager.PasskeyOutcome.Cancelled -> {
                        _uiState.value = _uiState.value.copy(isEnrolling = false)
                    }
                    is PasskeyManager.PasskeyOutcome.Unsupported -> {
                        _uiState.value = _uiState.value.copy(
                            isEnrolling = false,
                            isUnsupported = true,
                        )
                    }
                    is PasskeyManager.PasskeyOutcome.NoCredentials,
                    is PasskeyManager.PasskeyOutcome.Error -> {
                        val msg = if (outcome is PasskeyManager.PasskeyOutcome.Error) outcome.message
                                  else "No credential option available"
                        _uiState.value = _uiState.value.copy(
                            isEnrolling = false,
                            snackbarMessage = msg,
                        )
                    }
                }
            } catch (e: retrofit2.HttpException) {
                val msg = when (e.code()) {
                    404 -> "Passkeys are not enabled on this server."
                    else -> "Enrollment failed (${e.code()})"
                }
                Timber.e(e, "Passkey enrollment HTTP %d", e.code())
                _uiState.value = _uiState.value.copy(isEnrolling = false, snackbarMessage = msg)
            } catch (e: Exception) {
                Timber.e(e, "Passkey enrollment error")
                _uiState.value = _uiState.value.copy(
                    isEnrolling = false,
                    snackbarMessage = "Enrollment failed: ${e.message}",
                )
            }
        }
    }

    // ── Delete ─────────────────────────────────────────────────────────────

    fun requestDelete(id: String) {
        _uiState.value = _uiState.value.copy(deleteConfirmId = id)
    }

    fun dismissDeleteConfirm() {
        _uiState.value = _uiState.value.copy(deleteConfirmId = null)
    }

    fun confirmDelete() {
        val id = _uiState.value.deleteConfirmId ?: return
        _uiState.value = _uiState.value.copy(deleteConfirmId = null, isLoading = true)
        viewModelScope.launch {
            try {
                authApi.deletePasskey(id)
                _uiState.value = _uiState.value.copy(snackbarMessage = "Passkey removed")
                loadPasskeys()
            } catch (e: retrofit2.HttpException) {
                val msg = when (e.code()) {
                    404 -> "Passkey not found — it may have already been removed."
                    else -> "Remove failed (${e.code()})"
                }
                Timber.e(e, "deletePasskey HTTP %d", e.code())
                _uiState.value = _uiState.value.copy(isLoading = false, snackbarMessage = msg)
            } catch (e: Exception) {
                Timber.e(e, "deletePasskey error")
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    snackbarMessage = "Remove failed: ${e.message}",
                )
            }
        }
    }

    // ── Snackbar ───────────────────────────────────────────────────────────

    fun clearSnackbar() {
        _uiState.value = _uiState.value.copy(snackbarMessage = null)
    }
}
