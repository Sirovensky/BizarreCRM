package com.bizarreelectronics.crm.ui.screens.morning

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.MorningChecklistApi
import com.bizarreelectronics.crm.data.remote.dto.ChecklistStepDto
import com.bizarreelectronics.crm.data.remote.dto.MorningChecklistCompleteBody
import com.bizarreelectronics.crm.data.remote.dto.MorningChecklistSkipBody
import com.bizarreelectronics.crm.util.HardwarePinger
import com.bizarreelectronics.crm.util.PingResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Default steps — used when GET /tenants/me/morning-checklist returns 404
// ---------------------------------------------------------------------------

/**
 * §36 L586 — Built-in morning-open checklist steps.
 *
 * These 7 steps are shown when the server returns 404 for the tenant-
 * customisable endpoint.  Steps 3, 4, and 5 carry a [deepLinkRoute] that
 * renders the "View list →" navigation button in [MorningChecklistScreen].
 */
object MorningChecklistDefaults {
    val steps: List<ChecklistStepDto> = listOf(
        ChecklistStepDto(
            id = 1,
            title = "Open cash drawer & count starting cash",
            subtitle = "Enter the starting float amount",
            requiresInput = true,
        ),
        ChecklistStepDto(
            id = 2,
            title = "Print last night's backup receipt",
            subtitle = "Confirm backup completed successfully",
        ),
        ChecklistStepDto(
            id = 3,
            title = "Review pending tickets for today",
            subtitle = "Check open and in-progress repairs",
            deepLinkRoute = "tickets",
        ),
        ChecklistStepDto(
            id = 4,
            title = "Check appointments list",
            subtitle = "Review today's scheduled appointments",
            deepLinkRoute = "appointments",
        ),
        ChecklistStepDto(
            id = 5,
            title = "Check inventory low-stock alerts",
            subtitle = "Order parts before they run out",
            deepLinkRoute = "inventory",
        ),
        ChecklistStepDto(
            id = 6,
            title = "Power on hardware",
            subtitle = "Verify all peripherals are reachable",
        ),
        ChecklistStepDto(
            id = 7,
            title = "Unlock POS",
            subtitle = "Confirm the POS terminal is ready",
        ),
    )
}

// ---------------------------------------------------------------------------
// UI State
// ---------------------------------------------------------------------------

/**
 * §36 L585–L588 — UI state for [MorningChecklistScreen].
 *
 * @property steps            Ordered list of checklist steps (defaults or tenant-custom).
 * @property completedStepIds Set of step IDs the staff member has checked off.
 * @property pingResults      Map from step id to its [PingResult] (populated for step 6).
 * @property cashAmount       Amount entered for step 1 (cash drawer count), or null.
 * @property isLoading        True while fetching tenant step config.
 * @property isSubmitting     True while posting completion to the server.
 * @property error            Non-null when the submit call fails.
 * @property isAllDone        True when every step is checked off.
 */
data class MorningChecklistUiState(
    val steps: List<ChecklistStepDto> = MorningChecklistDefaults.steps,
    val completedStepIds: Set<Int> = emptySet(),
    val pingResults: Map<Int, PingResult> = emptyMap(),
    val cashAmount: String? = null,
    val isLoading: Boolean = true,
    val isSubmitting: Boolean = false,
    val error: String? = null,
) {
    val isAllDone: Boolean
        get() = steps.isNotEmpty() && steps.all { it.id in completedStepIds }
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * §36 L585–L588 — ViewModel for [MorningChecklistScreen].
 *
 * Responsibilities:
 *  - Load tenant-customised steps from `GET /tenants/me/morning-checklist`
 *    (404 → fall back to [MorningChecklistDefaults.steps]).
 *  - Track which steps have been checked off.
 *  - Drive hardware ping probes for step 6 via [HardwarePinger].
 *  - On completion, persist state via [AppPreferences.setMorningChecklistCompleted]
 *    and optionally POST to `POST /morning-checklist/complete` (404 tolerated).
 */
@HiltViewModel
class MorningChecklistViewModel @Inject constructor(
    private val morningChecklistApi: MorningChecklistApi,
    private val appPreferences: AppPreferences,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _uiState = MutableStateFlow(MorningChecklistUiState())
    val uiState: StateFlow<MorningChecklistUiState> = _uiState.asStateFlow()

    /** ISO date key (yyyy-MM-dd) for today — stable across the lifecycle. */
    val todayKey: String = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)

    init {
        loadSteps()
        restoreCompletedSteps()
    }

    // -------------------------------------------------------------------------
    // Step loading
    // -------------------------------------------------------------------------

    private fun loadSteps() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val steps = try {
                val response = morningChecklistApi.getChecklistConfig()
                val remote = response.data?.steps
                if (!remote.isNullOrEmpty()) remote else MorningChecklistDefaults.steps
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    Log.d(TAG, "GET /tenants/me/morning-checklist 404 — using defaults")
                } else {
                    Log.w(TAG, "GET /tenants/me/morning-checklist HTTP ${e.code()}")
                }
                MorningChecklistDefaults.steps
            } catch (e: Exception) {
                Log.w(TAG, "GET /tenants/me/morning-checklist failed: ${e.message}")
                MorningChecklistDefaults.steps
            }
            _uiState.value = _uiState.value.copy(isLoading = false, steps = steps)
        }
    }

    private fun restoreCompletedSteps() {
        val saved = appPreferences.morningChecklistCompletedSteps(todayKey)
        _uiState.value = _uiState.value.copy(completedStepIds = saved)
    }

    // -------------------------------------------------------------------------
    // Step interactions
    // -------------------------------------------------------------------------

    /**
     * Toggle the checked state for [stepId].  For step 6 (hardware), a ping
     * probe is also triggered when the step is checked.
     */
    fun toggleStep(stepId: Int) {
        val current = _uiState.value.completedStepIds
        val updated = if (stepId in current) current - stepId else current + stepId
        _uiState.value = _uiState.value.copy(completedStepIds = updated)
        persistSteps(updated)
    }

    /** Store the cash-drawer float amount entered in step 1's dialog. */
    fun setCashAmount(amount: String) {
        _uiState.value = _uiState.value.copy(cashAmount = amount)
    }

    // -------------------------------------------------------------------------
    // Hardware ping (step 6)
    // -------------------------------------------------------------------------

    /**
     * Run a ping probe for [stepId] using the given [host]/[port] or [macAddress].
     *
     * Updates [MorningChecklistUiState.pingResults] for [stepId]:
     *  - [PingResult.Pending] immediately while the probe is in flight.
     *  - Final [PingResult.Success], [PingResult.Failure], or [PingResult.Timeout]
     *    once the probe resolves.
     */
    fun pingDevice(stepId: Int, host: String, port: Int) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                pingResults = _uiState.value.pingResults + (stepId to PingResult.Pending),
            )
            val result = HardwarePinger.pingIpv4(host, port)
            _uiState.value = _uiState.value.copy(
                pingResults = _uiState.value.pingResults + (stepId to result),
            )
        }
    }

    /** Bluetooth variant of [pingDevice]. */
    fun pingDeviceBluetooth(stepId: Int, macAddress: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                pingResults = _uiState.value.pingResults + (stepId to PingResult.Pending),
            )
            val result = HardwarePinger.pingBluetooth(macAddress)
            _uiState.value = _uiState.value.copy(
                pingResults = _uiState.value.pingResults + (stepId to result),
            )
        }
    }

    // -------------------------------------------------------------------------
    // Completion
    // -------------------------------------------------------------------------

    /**
     * §36 L588 — Finalize the checklist.
     *
     * 1. Marks every step as complete locally.
     * 2. Persists state to [AppPreferences].
     * 3. Attempts to POST to the server (404 tolerated).
     */
    fun completeChecklist() {
        val allStepIds = _uiState.value.steps.map { it.id }.toSet()
        val staffId = authPreferences.userId
        _uiState.value = _uiState.value.copy(
            completedStepIds = allStepIds,
            isSubmitting = true,
            error = null,
        )
        appPreferences.setMorningChecklistCompleted(todayKey, staffId, allStepIds)

        viewModelScope.launch {
            try {
                morningChecklistApi.postCompletion(
                    MorningChecklistCompleteBody(
                        dateKey = todayKey,
                        staffId = staffId,
                        completedSteps = allStepIds.toList(),
                        completedAtMs = System.currentTimeMillis(),
                    ),
                )
                Log.d(TAG, "Morning checklist completion posted for $todayKey")
            } catch (e: HttpException) {
                // 404 = endpoint not live yet; silently tolerated.
                if (e.code() != 404) {
                    Log.w(TAG, "POST /morning-checklist/complete HTTP ${e.code()}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "POST /morning-checklist/complete failed: ${e.message}")
            } finally {
                _uiState.value = _uiState.value.copy(isSubmitting = false)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Skip
    // -------------------------------------------------------------------------

    /**
     * §3.15 L589 — Record that the user explicitly skipped today's checklist.
     *
     * Steps:
     *  1. Persist the skip locally via [AppPreferences.setMorningChecklistSkipped].
     *  2. Attempt to POST to the server so the audit log captures the event.
     *     HTTP 404 (endpoint not yet live) is silently tolerated.
     *
     * The caller (MorningChecklistScreen) should navigate back after calling this
     * (same as pressing the "back" button — but now with an audit trail).
     */
    fun skipChecklist() {
        appPreferences.setMorningChecklistSkipped(todayKey)
        val staffId = authPreferences.userId
        viewModelScope.launch {
            try {
                morningChecklistApi.postSkip(
                    MorningChecklistSkipBody(
                        dateKey = todayKey,
                        staffId = staffId,
                        skippedAtMs = System.currentTimeMillis(),
                    ),
                )
                Log.d(TAG, "Morning checklist skip posted for $todayKey")
            } catch (e: HttpException) {
                // 404 = endpoint not live yet; silently tolerated.
                if (e.code() != 404) {
                    Log.w(TAG, "POST /morning-checklist/skip HTTP ${e.code()}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "POST /morning-checklist/skip failed: ${e.message}")
            }
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun persistSteps(completed: Set<Int>) {
        val staffId = authPreferences.userId
        appPreferences.setMorningChecklistCompleted(todayKey, staffId, completed)
    }

    companion object {
        private const val TAG = "MorningChecklistVM"
    }
}
