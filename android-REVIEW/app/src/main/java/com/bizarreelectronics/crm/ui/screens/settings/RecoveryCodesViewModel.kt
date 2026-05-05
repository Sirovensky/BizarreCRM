package com.bizarreelectronics.crm.ui.screens.settings

// §2.19 L427-L438 — ViewModel for the Recovery Codes settings screen.
//
// State machine:
//   Idle                → initial; shows description + "Regenerate" button.
//   RequiringPassword   → user tapped Regenerate; shows password field for re-auth.
//   Regenerating        → POST in-flight; shows loading indicator.
//   Generated(codes)    → success; shows BackupCodesDisplay + Print + Email actions.
//   NotSupported        → server returned 404; shows informational card.
//   Error(AppError)     → network/server failure; shows error message.
//
// SECURITY: recovery codes are NEVER logged. The password body field is
//           already redacted by RedactingHttpLogger at the HTTP layer.

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.util.AppError
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

sealed interface RecoveryCodesUiState {
    /** Initial state — server's remaining count is unknown until first load. */
    data object Idle : RecoveryCodesUiState

    /** Waiting for the user to enter their current password before regenerating. */
    data object RequiringPassword : RecoveryCodesUiState

    /** POST is in-flight. */
    data object Regenerating : RecoveryCodesUiState

    /**
     * Server returned fresh codes. The user must save them before dismissing.
     * @param codes The newly-generated one-time recovery codes.
     */
    data class Generated(val codes: List<String>) : RecoveryCodesUiState

    /**
     * Server returned 404 — this server version does not support recovery code
     * management via the API. Show an informational card, no retry.
     */
    data object NotSupported : RecoveryCodesUiState

    /** Network or unexpected server error. */
    data class Error(val error: AppError) : RecoveryCodesUiState
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class RecoveryCodesViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<RecoveryCodesUiState>(RecoveryCodesUiState.Idle)
    val uiState: StateFlow<RecoveryCodesUiState> = _uiState.asStateFlow()

    // ---------------------------------------------------------------------------
    // Actions
    // ---------------------------------------------------------------------------

    /**
     * User tapped "Regenerate codes" from the Idle state.
     * Transitions to RequiringPassword so the UI shows a password field.
     */
    fun requestRegenerate() {
        _uiState.value = RecoveryCodesUiState.RequiringPassword
    }

    /**
     * User confirmed with their password. Calls the regenerate endpoint.
     *
     * On success → Generated(codes).
     * On 404    → NotSupported (server predates this endpoint).
     * On 401    → back to RequiringPassword (wrong password — re-prompt).
     * On other  → Error(AppError).
     *
     * SECURITY: [password] is sent directly in the POST body and is never
     *           stored or logged here. RedactingHttpLogger redacts it at the
     *           HTTP layer.
     */
    fun regenerate(password: String) {
        if (password.isBlank()) return
        _uiState.value = RecoveryCodesUiState.Regenerating
        viewModelScope.launch {
            try {
                val response = authApi.regenerateRecoveryCodes(mapOf("password" to password))
                val codes = response.data?.codes
                if (response.success && !codes.isNullOrEmpty()) {
                    _uiState.value = RecoveryCodesUiState.Generated(codes)
                } else {
                    _uiState.value = RecoveryCodesUiState.Error(
                        AppError.Server(
                            status = 0,
                            serverMessage = response.message ?: "Server returned no codes.",
                            requestId = null,
                        )
                    )
                }
            } catch (e: HttpException) {
                _uiState.value = when (e.code()) {
                    404 -> RecoveryCodesUiState.NotSupported
                    401 -> RecoveryCodesUiState.RequiringPassword // wrong password — re-prompt
                    else -> RecoveryCodesUiState.Error(AppError.from(e))
                }
            } catch (e: IOException) {
                _uiState.value = RecoveryCodesUiState.Error(AppError.from(e))
            } catch (e: Exception) {
                _uiState.value = RecoveryCodesUiState.Error(AppError.from(e))
            }
        }
    }

    /**
     * User dismissed the password prompt or the error state.
     * Returns to Idle without making any network call.
     */
    fun dismiss() {
        _uiState.value = RecoveryCodesUiState.Idle
    }

    /**
     * Called after the user has confirmed they saved the generated codes.
     * Returns to Idle.
     */
    fun confirmSaved() {
        _uiState.value = RecoveryCodesUiState.Idle
    }
}
