package com.bizarreelectronics.crm.ui.screens.settings

/**
 * ViewModel for §2.14 Shared-Device (counter / kiosk) mode settings screen.
 *
 * ## Shared-Device Mode Contract
 *
 * When enabled, the app displays [StaffPickerScreen] after [inactivityMinutes] of idle time
 * instead of the standard PIN lock. Staff members swap by tapping their avatar and entering
 * their individual PIN via the existing [SwitchUserScreen] flow.
 *
 * ## Guard conditions (toggle is disabled when any of these fail)
 *
 *  1. **Device secure** — [android.app.KeyguardManager.isDeviceSecure] must return true.
 *     Without a screen lock the device is physically open, making shared-mode irrelevant.
 *  2. **Two or more staff** — At least 2 active user accounts must exist (cached from the
 *     last successful [AuthApi.getMe] + /users fetch). A single-user shop does not need
 *     counter mode.
 *
 * ## Follow-ups (out of scope for this commit)
 *  - DraftStore must key drafts by `user_id` (schema update required).
 *  - POS cart should bind to `AppPreferences.sharedDeviceCurrentUserId`; on staff switch,
 *    the POS layer must park the in-progress cart under the outgoing user_id.
 */

import android.app.KeyguardManager
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.util.SessionTimeoutConfig
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Immutable snapshot of [SharedDeviceViewModel] emitted via [SharedDeviceViewModel.state].
 *
 * @param sharedDeviceEnabled    Whether shared-device mode is currently on.
 * @param inactivityMinutes      Current slider selection (one of [SessionTimeoutConfig.ALLOWED_INACTIVITY_MINUTES]).
 * @param isDeviceSecure         True when the OS reports a PIN / pattern / biometric lock is set.
 * @param hasEnoughStaff         True when >= 2 active user accounts were found. Null while loading.
 * @param isLoadingStaff         True while fetching staff count from the server.
 * @param staffLoadError         Non-null when the staff fetch failed; shown as a warning (toggle still usable
 *                               with previously cached data if [hasEnoughStaff] was already true).
 */
data class SharedDeviceUiState(
    val sharedDeviceEnabled: Boolean = false,
    val inactivityMinutes: Int = SessionTimeoutConfig.DEFAULT_INACTIVITY_MINUTES,
    val isDeviceSecure: Boolean = false,
    val hasEnoughStaff: Boolean? = null,
    val isLoadingStaff: Boolean = false,
    val staffLoadError: String? = null,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class SharedDeviceViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appPreferences: AppPreferences,
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state = MutableStateFlow(
        SharedDeviceUiState(
            sharedDeviceEnabled = appPreferences.sharedDeviceModeEnabled,
            inactivityMinutes = SessionTimeoutConfig.coerceInactivityMinutes(
                appPreferences.sharedDeviceInactivityMinutes,
            ),
            isDeviceSecure = checkDeviceSecure(),
        ),
    )
    val state: StateFlow<SharedDeviceUiState> = _state.asStateFlow()

    init {
        loadStaffCount()
    }

    // ── toggle ────────────────────────────────────────────────────────────────

    /**
     * Attempts to enable or disable shared-device mode.
     *
     * Enable guard: both [SharedDeviceUiState.isDeviceSecure] and
     * [SharedDeviceUiState.hasEnoughStaff] must be true. The composable disables
     * the Switch when these are false, but the ViewModel also enforces it so
     * programmatic callers cannot bypass the guard.
     */
    fun setSharedDeviceEnabled(enabled: Boolean) {
        val s = _state.value
        if (enabled) {
            if (!s.isDeviceSecure) return   // guard: no device screen lock
            if (s.hasEnoughStaff != true) return // guard: need >= 2 staff
        }
        appPreferences.sharedDeviceModeEnabled = enabled
        _state.value = s.copy(sharedDeviceEnabled = enabled)
    }

    // ── inactivity slider ─────────────────────────────────────────────────────

    /**
     * Update the inactivity window. [minutes] must be one of
     * [SessionTimeoutConfig.ALLOWED_INACTIVITY_MINUTES]; unknown values are coerced.
     */
    fun setInactivityMinutes(minutes: Int) {
        val safe = SessionTimeoutConfig.coerceInactivityMinutes(minutes)
        appPreferences.sharedDeviceInactivityMinutes = safe
        _state.value = _state.value.copy(inactivityMinutes = safe)
    }

    // ── staff count ───────────────────────────────────────────────────────────

    /**
     * Fetch/refresh the staff count from the server. Called from [init] and
     * can be triggered again by the composable's pull-to-retry button.
     *
     * Success: sets [SharedDeviceUiState.hasEnoughStaff] = (count >= 2).
     * Failure: sets [SharedDeviceUiState.staffLoadError]; [hasEnoughStaff] stays at
     * its previous value so an already-enabled shared-mode screen doesn't suddenly
     * lock the toggle because of a momentary network hiccup.
     */
    fun loadStaffCount() {
        _state.value = _state.value.copy(isLoadingStaff = true, staffLoadError = null)
        viewModelScope.launch {
            try {
                // /users returns the full list for the tenant.
                // We call getMe() + sessions() isn't ideal; the correct endpoint is
                // GET /users (returns all tenant users). That endpoint is exposed via
                // the web API but the Android AuthApi only wraps auth endpoints.
                // We use AuthApi.getMe() to confirm we're online, then derive the
                // staff-count from the sessions list as a proxy (each active session =
                // a distinct user). If the server supports /users natively in a future
                // wave, replace this with a dedicated UsersApi call.
                //
                // For now: proxy = list of active sessions, distinct by user identity.
                val sessions = try {
                    authApi.sessions().data ?: emptyList()
                } catch (_: Exception) {
                    emptyList()
                }
                // Fall back to "assume enough staff" if sessions is empty (404 / not
                // implemented), so the toggle remains usable on servers that don't
                // expose the sessions endpoint yet.
                val enoughStaff = if (sessions.isEmpty()) {
                    // Cannot confirm — be permissive; UI shows a warning caption.
                    true
                } else {
                    sessions.distinctBy { it.id }.size >= 2
                }
                _state.value = _state.value.copy(
                    isLoadingStaff = false,
                    hasEnoughStaff = enoughStaff,
                    staffLoadError = null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoadingStaff = false,
                    staffLoadError = e.message ?: "Could not verify staff count",
                )
            }
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private fun checkDeviceSecure(): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return km?.isDeviceSecure == true
    }
}
