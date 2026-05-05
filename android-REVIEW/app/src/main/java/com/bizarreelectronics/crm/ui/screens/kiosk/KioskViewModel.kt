package com.bizarreelectronics.crm.ui.screens.kiosk

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §57 Kiosk mode ViewModel.
 *
 * Manages the three kiosk sub-flows:
 *  - §57.2  Customer check-in (phone lookup → record/create → sign waiver)
 *  - §57.3  Customer-facing signature (device-flip, no back-out)
 *  - §57.5  Manager-PIN exit gate
 *
 * Inactivity timer (§57.2): resets on [onActivity]; after [INACTIVITY_TIMEOUT_MS]
 * with no activity, [UiState.inactivityExpired] flips to true and the caller
 * navigates back to the start screen.
 */
@HiltViewModel
class KioskViewModel @Inject constructor(
    private val pinPrefs: PinPreferences,
    /** Exposed for §26.4 ReduceMotion check in [KioskExitScreen]. */
    val appPreferences: AppPreferences,
) : ViewModel() {

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    data class UiState(
        /** Phone number typed by the customer (Step 1). */
        val phoneQuery: String = "",
        /** True while network lookup / creation is in flight. */
        val isLoading: Boolean = false,
        /** Customer record resolved in Step 1 (id + display name). */
        val resolvedCustomerId: Long? = null,
        val resolvedCustomerName: String = "",
        /** Inline validation / network error to display. */
        val errorMessage: String? = null,
        /** Signature captured in §57.3 (base64 data-URI or empty). */
        val signatureBase64: String = "",
        /** True after customer signs — advances to done screen. */
        val signatureCaptured: Boolean = false,
        /** §57.2 — inactivity timer expired; caller should reset to start. */
        val inactivityExpired: Boolean = false,
        /** §57.5 — digits entered in the manager-PIN exit gate. */
        val exitPinEntered: String = "",
        /** §57.5 — wrong-PIN animation trigger counter. */
        val exitPinWrongShakes: Int = 0,
        /** §57.5 — error shown when the exit PIN is rejected. */
        val exitPinError: String? = null,
        /** §57.5 — exit authorised; caller should stopLockTask + navigate away. */
        val exitAuthorised: Boolean = false,
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    // -------------------------------------------------------------------------
    // Inactivity timer (§57.2)
    // -------------------------------------------------------------------------

    private var inactivityJob: Job? = null

    /** Reset the 60-second inactivity timer. Call on every user interaction. */
    fun onActivity() {
        _uiState.value = _uiState.value.copy(inactivityExpired = false)
        inactivityJob?.cancel()
        inactivityJob = viewModelScope.launch {
            delay(INACTIVITY_TIMEOUT_MS)
            _uiState.value = _uiState.value.copy(inactivityExpired = true)
        }
    }

    /** Pause the inactivity timer (e.g. while the customer is actively signing). */
    fun pauseInactivity() {
        inactivityJob?.cancel()
    }

    /** Reset all state back to the initial start-screen state. */
    fun resetToStart() {
        inactivityJob?.cancel()
        _uiState.value = UiState()
    }

    // -------------------------------------------------------------------------
    // §57.2 Customer check-in
    // -------------------------------------------------------------------------

    fun onPhoneQueryChange(value: String) {
        _uiState.value = _uiState.value.copy(
            phoneQuery = value,
            errorMessage = null,
        )
        onActivity()
    }

    /**
     * Stub: look up a customer by phone number and resolve [UiState.resolvedCustomerId].
     *
     * Replace with a real repository call once the customer-lookup endpoint is
     * injectable here.  The stub accepts any 10-digit string so the kiosk flow
     * can be exercised end-to-end in development.
     */
    fun lookupCustomer() {
        val phone = _uiState.value.phoneQuery.filter { it.isDigit() }
        if (phone.length < 7) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Enter at least 7 digits",
            )
            return
        }
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            // TODO(§57.2): replace stub with CustomerRepository.findByPhone(phone)
            delay(400L) // simulate network
            // Stub: no matching customer → create walk-in record.
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                resolvedCustomerId = 0L, // 0 = walk-in sentinel
                resolvedCustomerName = "Walk-in customer",
            )
            onActivity()
        }
    }

    // -------------------------------------------------------------------------
    // §57.3 Customer-facing signature
    // -------------------------------------------------------------------------

    fun onSignatureCaptured(base64: String) {
        _uiState.value = _uiState.value.copy(
            signatureBase64 = base64,
            signatureCaptured = base64.isNotEmpty(),
        )
        pauseInactivity() // customer is actively signing — don't time out
    }

    // -------------------------------------------------------------------------
    // §57.5 Manager-PIN exit gate
    // -------------------------------------------------------------------------

    private val PIN_LENGTH = 4

    fun onExitPinDigit(c: Char) {
        val s = _uiState.value
        if (s.exitPinEntered.length >= PIN_LENGTH) return
        val next = s.exitPinEntered + c
        _uiState.value = s.copy(exitPinEntered = next, exitPinError = null)
        if (next.length == PIN_LENGTH) {
            verifyExitPin(next)
        }
    }

    fun onExitPinBackspace() {
        val s = _uiState.value
        if (s.exitPinEntered.isEmpty()) return
        _uiState.value = s.copy(
            exitPinEntered = s.exitPinEntered.dropLast(1),
            exitPinError = null,
        )
    }

    private fun verifyExitPin(pin: String) {
        viewModelScope.launch {
            val ok = pinPrefs.verifyPinLocally(pin)
            if (ok) {
                _uiState.value = _uiState.value.copy(exitAuthorised = true)
            } else {
                _uiState.value = _uiState.value.copy(
                    exitPinEntered = "",
                    exitPinWrongShakes = _uiState.value.exitPinWrongShakes + 1,
                    exitPinError = "Wrong PIN",
                )
            }
        }
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    companion object {
        /** §57.2 — auto-return timeout (60 seconds of inactivity). */
        const val INACTIVITY_TIMEOUT_MS = 60_000L
    }
}
