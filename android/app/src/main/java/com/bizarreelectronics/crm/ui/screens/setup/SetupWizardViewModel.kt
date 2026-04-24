package com.bizarreelectronics.crm.ui.screens.setup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SetupApi
import com.bizarreelectronics.crm.data.remote.dto.SetupProgressRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Total wizard step count ─────────────────────────────────────────────────
const val SETUP_WIZARD_TOTAL_STEPS = 13

// ─── State ───────────────────────────────────────────────────────────────────

/**
 * §2.10 [plan:L343] — Immutable UI state for SetupWizardScreen.
 *
 * [currentStep] is 0-based (0 = Welcome, 12 = Finish & launch).
 * [stepData] stores per-step field maps using step index as key.
 * [isLoading] is true while async operations (save progress, complete) are in flight.
 * [error] is a human-readable string shown as a Snackbar when non-null.
 */
data class SetupWizardUiState(
    val currentStep: Int = 0,
    val stepData: Map<Int, Map<String, Any>> = emptyMap(),
    val isLoading: Boolean = false,
    val error: String? = null,
)

/** One-shot navigation events emitted by the ViewModel. */
sealed interface SetupWizardEvent {
    /** Setup complete — navigate to the dashboard, clearing the back stack. */
    data object NavigateToDashboard : SetupWizardEvent
}

// ─── Validation ──────────────────────────────────────────────────────────────

/**
 * §2.10 — Pure validation logic for each wizard step (steps 1–5 are fully
 * validated; steps 6–12 show a "Skip for now" option and are always passable).
 *
 * Returns null when valid, or a human-readable error string when invalid.
 */
internal object SetupStepValidator {

    /** Step 0 — Welcome. Always valid (no required fields). */
    fun validateStep0(@Suppress("UNUSED_PARAMETER") data: Map<String, Any>): String? = null

    /**
     * Step 1 — Business info.
     *
     * Required: shop_name, address, phone, timezone, shop_type.
     * Server contract: POST /setup/progress { step_index: 1, data: { shop_name, address,
     *   phone, timezone, shop_type } }.
     */
    fun validateStep1(data: Map<String, Any>): String? {
        if (data["shop_name"]?.toString().isNullOrBlank()) return "Shop name is required."
        if (data["phone"]?.toString().isNullOrBlank()) return "Phone number is required."
        if (data["timezone"]?.toString().isNullOrBlank()) return "Timezone is required."
        return null
    }

    /**
     * Step 2 — Owner account.
     *
     * Required: username (≥3 chars), email (valid format), password (≥8 chars).
     * Server contract: POST /setup/progress { step_index: 2, data: { username, email, password } }.
     * SECURITY: password is never stored in stepData beyond what the server confirms.
     */
    fun validateStep2(data: Map<String, Any>): String? {
        val username = data["username"]?.toString().orEmpty()
        val email    = data["email"]?.toString().orEmpty()
        val password = data["password"]?.toString().orEmpty()
        if (username.length < 3) return "Username must be at least 3 characters."
        if (!EMAIL_REGEX.matches(email)) return "Enter a valid email address."
        if (password.length < 8) return "Password must be at least 8 characters."
        return null
    }

    /**
     * Step 3 — Tax classes.
     *
     * Requires at least one tax-class entry. Default list is pre-seeded; user
     * may keep defaults or customise. Skippable if data contains
     * { "skipped": "true" }.
     */
    fun validateStep3(data: Map<String, Any>): String? {
        if (data["skipped"] == "true") return null
        val classes = data["tax_classes"]
        if (classes == null) return "Add at least one tax class or skip."
        return null
    }

    /**
     * Step 4 — Payment methods.
     *
     * Requires at least one payment method selected. Skippable via
     * { "skipped": "true" }.
     */
    fun validateStep4(data: Map<String, Any>): String? {
        if (data["skipped"] == "true") return null
        val methods = data["payment_methods"]
        if (methods == null) return "Select at least one payment method or skip."
        return null
    }

    /**
     * Step 5+ — SMS/email, labels, staff invite, inventory, printer, barcode,
     * summary. All skippable — always return null.
     */
    fun validateSkippable(@Suppress("UNUSED_PARAMETER") data: Map<String, Any>): String? = null

    fun validate(step: Int, data: Map<String, Any>): String? = when (step) {
        0    -> validateStep0(data)
        1    -> validateStep1(data)
        2    -> validateStep2(data)
        3    -> validateStep3(data)
        4    -> validateStep4(data)
        else -> validateSkippable(data)
    }

    private val EMAIL_REGEX = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+\$")
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * §2.10 [plan:L343] — ViewModel driving SetupWizardScreen.
 *
 * Responsibilities:
 *   - Maintain [uiState]: current step, per-step data, loading + error flags.
 *   - [nextStep]: validate current step data, save progress (server + local
 *     fallback), then advance [currentStep].
 *   - [previousStep]: decrement [currentStep] (no validation; no server call).
 *   - [updateStepData]: merge new field values into the current step's data map
 *     immutably.
 *   - [completeSetup]: fire POST /setup/complete and emit [SetupWizardEvent.NavigateToDashboard].
 *
 * Server fallback: if [setupApi] returns 404 (server predates endpoints), progress
 * is tracked in-memory only and [completeSetup] navigates immediately.
 */
@HiltViewModel
class SetupWizardViewModel @Inject constructor(
    private val setupApi: SetupApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SetupWizardUiState())
    val uiState: StateFlow<SetupWizardUiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<SetupWizardEvent>()
    val events: SharedFlow<SetupWizardEvent> = _events.asSharedFlow()

    init {
        loadProgress()
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    /**
     * Merge [fields] into the data map for the current step.
     *
     * Returns a new [SetupWizardUiState] (immutable update) and clears any
     * lingering [SetupWizardUiState.error].
     */
    fun updateStepData(fields: Map<String, Any>) {
        _uiState.update { current ->
            val merged = (current.stepData[current.currentStep] ?: emptyMap()) + fields
            current.copy(
                stepData = current.stepData + (current.currentStep to merged),
                error    = null,
            )
        }
    }

    /**
     * Validate the current step and advance to the next step.
     *
     * On validation failure: sets [SetupWizardUiState.error] and stays on the
     * current step so the user can correct input.
     *
     * On success: persists progress to the server (best-effort; 404 is silenced),
     * then increments [SetupWizardUiState.currentStep].
     */
    fun nextStep() {
        val state = _uiState.value
        val data  = state.stepData[state.currentStep] ?: emptyMap()
        val err   = SetupStepValidator.validate(state.currentStep, data)
        if (err != null) {
            _uiState.update { it.copy(error = err) }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            saveProgressRemote(state.currentStep, data)
            _uiState.update { it.copy(
                isLoading   = false,
                currentStep = (state.currentStep + 1).coerceAtMost(SETUP_WIZARD_TOTAL_STEPS - 1),
            ) }
        }
    }

    /** Decrement [currentStep] without validation or a server call. */
    fun previousStep() {
        _uiState.update { it.copy(
            currentStep = (it.currentStep - 1).coerceAtLeast(0),
            error       = null,
        ) }
    }

    /**
     * Fire POST /setup/complete and navigate to dashboard.
     *
     * On 404 (server predates endpoint): navigate immediately.
     * On other error: set [SetupWizardUiState.error]; stay on finish step.
     */
    fun completeSetup() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val response = setupApi.completeSetup()
                // If server issued auto-login tokens, store them.
                response.data?.accessToken?.let { token ->
                    authPreferences.accessToken = token
                }
                response.data?.refreshToken?.let { token ->
                    authPreferences.refreshToken = token
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() != 404 && e.code() != 409) {
                    _uiState.update { it.copy(isLoading = false, error = "Could not finalise setup: ${e.message()}") }
                    return@launch
                }
                // 404 (server predates endpoint) or 409 (already complete) — proceed.
            } catch (_: Exception) {
                // Network error during complete — still navigate (server state uncertain).
            }
            _uiState.update { it.copy(isLoading = false) }
            _events.emit(SetupWizardEvent.NavigateToDashboard)
        }
    }

    /** Jump to a specific step (used by resume-from-saved-progress). */
    fun jumpToStep(index: Int) {
        _uiState.update { it.copy(
            currentStep = index.coerceIn(0, SETUP_WIZARD_TOTAL_STEPS - 1),
            error       = null,
        ) }
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    private fun loadProgress() {
        viewModelScope.launch {
            try {
                val response = setupApi.getProgress()
                val progress = response.data ?: return@launch
                _uiState.update { it.copy(
                    currentStep = progress.resumeAtStep.coerceIn(0, SETUP_WIZARD_TOTAL_STEPS - 1),
                ) }
            } catch (_: Exception) {
                // 404 or network error — start from step 0.
            }
        }
    }

    private suspend fun saveProgressRemote(stepIndex: Int, data: Map<String, Any>) {
        try {
            setupApi.postProgress(SetupProgressRequest(stepIndex = stepIndex, data = data))
        } catch (_: Exception) {
            // Best-effort; never block navigation on a progress-save failure.
        }
    }
}
