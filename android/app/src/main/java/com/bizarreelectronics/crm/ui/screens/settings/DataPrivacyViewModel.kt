package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ConsentStatusResponse
import com.bizarreelectronics.crm.data.remote.api.PrivacyApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * L2526 — ViewModel backing [DataPrivacyScreen].
 *
 * Orchestrates GDPR data-export, account-deletion, and consent-status calls
 * against [PrivacyApi].  All network operations are tolerant of 404 responses
 * (feature not deployed on the connected server).
 *
 * ## State machine
 * [state] is the single source of truth.  The screen renders reactively from it.
 *
 * ## Account deletion flow
 * 1. User taps "Delete my account".
 * 2. Screen shows a confirmation dialog.
 * 3. On confirm, [deleteAccount] is called.
 * 4. On success: local state is wiped ([AppPreferences] + [AuthPreferences])
 *    and the VM emits [DataPrivacyState.DeletedAndLoggedOut].
 * 5. Navigation to the login screen is triggered from the composable on that state.
 */
@HiltViewModel
class DataPrivacyViewModel @Inject constructor(
    private val privacyApi: PrivacyApi,
    private val authPreferences: AuthPreferences,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow<DataPrivacyState>(DataPrivacyState.Idle)
    val state: StateFlow<DataPrivacyState> = _state.asStateFlow()

    private val _consentStatus = MutableStateFlow<ConsentStatusResponse?>(null)
    val consentStatus: StateFlow<ConsentStatusResponse?> = _consentStatus.asStateFlow()

    init {
        loadConsentStatus()
    }

    // ─── Public actions ───────────────────────────────────────────────────────

    /**
     * Requests an async data export for the current user.
     *
     * On success, emits [DataPrivacyState.ExportRequested] with the server's
     * [request_id].  On 404, emits [DataPrivacyState.FeatureNotAvailable].
     * On other errors, emits [DataPrivacyState.Error].
     */
    fun requestExport() {
        viewModelScope.launch {
            _state.value = DataPrivacyState.Loading
            try {
                val response = privacyApi.exportMyData()
                if (response.success) {
                    _state.value = DataPrivacyState.ExportRequested(
                        requestId = response.data?.requestId,
                    )
                } else {
                    _state.value = DataPrivacyState.Error(
                        message = response.message ?: "Export request failed",
                    )
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _state.value = DataPrivacyState.FeatureNotAvailable
                } else {
                    Timber.e(e, "exportMyData failed")
                    _state.value = DataPrivacyState.Error("Network error: ${e.code()}")
                }
            } catch (e: Exception) {
                Timber.e(e, "exportMyData failed")
                _state.value = DataPrivacyState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Soft-deletes the current user account and wipes local state.
     *
     * Should only be called after the user has confirmed the destructive action
     * via the confirmation dialog in [DataPrivacyScreen].
     */
    fun deleteAccount() {
        viewModelScope.launch {
            _state.value = DataPrivacyState.Loading
            try {
                val response = privacyApi.deleteMyAccount()
                if (response.success) {
                    wipeLocalState()
                    _state.value = DataPrivacyState.DeletedAndLoggedOut
                } else {
                    _state.value = DataPrivacyState.Error(
                        message = response.message ?: "Account deletion failed",
                    )
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _state.value = DataPrivacyState.FeatureNotAvailable
                } else {
                    Timber.e(e, "deleteMyAccount failed")
                    _state.value = DataPrivacyState.Error("Network error: ${e.code()}")
                }
            } catch (e: Exception) {
                Timber.e(e, "deleteMyAccount failed")
                _state.value = DataPrivacyState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /** Resets the state back to [DataPrivacyState.Idle] (e.g. after showing a snackbar). */
    fun resetState() {
        _state.value = DataPrivacyState.Idle
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private fun loadConsentStatus() {
        viewModelScope.launch {
            try {
                val response = privacyApi.consentStatus()
                if (response.success) {
                    _consentStatus.value = response.data
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() != 404) {
                    Timber.w(e, "consentStatus returned %d", e.code())
                }
                // 404 → feature not available; leave consentStatus null
            } catch (e: Exception) {
                Timber.w(e, "consentStatus failed")
            }
        }
    }

    /**
     * Clears auth tokens and resets cached non-auth preferences (open tickets,
     * revenue, FCM token, etc.) so deleted-account data does not persist locally.
     * The shared preferences file itself is left intact for install-level keys
     * (serverUrl, installationId) — [AuthPreferences.clear] handles that policy.
     */
    private fun wipeLocalState() {
        authPreferences.clear(AuthPreferences.ClearReason.UserLogout)
        // Reset non-auth cached values
        appPreferences.cachedOpenTickets = 0
        appPreferences.cachedRevenueToday = 0.0
        appPreferences.cachedLowStock = 0
        appPreferences.cachedMissingParts = 0
        appPreferences.cachedStaleTickets = 0
        appPreferences.cachedOverdueInvoices = 0
        appPreferences.fcmToken = null
        appPreferences.fcmTokenRegistered = false
    }
}

// ─── State sealed class ───────────────────────────────────────────────────────

/**
 * UI state for [DataPrivacyScreen].
 */
sealed class DataPrivacyState {
    /** Default state — no operation in progress. */
    data object Idle : DataPrivacyState()

    /** A network call is in flight. */
    data object Loading : DataPrivacyState()

    /**
     * Data export request was submitted successfully.
     * @property requestId Server-assigned job ID, or null if not returned.
     */
    data class ExportRequested(val requestId: String?) : DataPrivacyState()

    /** Account was deleted and local auth state has been wiped. */
    data object DeletedAndLoggedOut : DataPrivacyState()

    /**
     * The requested feature is not available on the connected server (404).
     * The screen should surface a "Not available on this server" message.
     */
    data object FeatureNotAvailable : DataPrivacyState()

    /**
     * A network or server error occurred.
     * @property message Human-readable description.
     */
    data class Error(val message: String) : DataPrivacyState()
}
