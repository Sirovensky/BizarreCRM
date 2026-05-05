package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §53.1 — Training Mode preferences.
 *
 * Training mode is a **client-side only** feature that swaps every data-fetch
 * and data-write behind a [TrainingDataSource] fake so staff can practice
 * workflows without touching production data.  No network requests reach the
 * real server while training mode is active.
 *
 * ## What this class owns
 *  - [trainingModeEnabled] — master on/off toggle (backed by plain prefs).
 *  - [trainingModeEnabledFlow] — reactive StateFlow that drives the top-bar
 *    banner and any conditional UI that must respond to mid-session toggles.
 *  - [checklistCompletedSteps] — persisted set of step IDs the user has
 *    ticked off on the optional onboarding checklist (§53.5).
 *
 * ## What this class does NOT own
 *  - Seeded demo data — that is responsibility of [TrainingDataSource].
 *  - The separate SQLCipher database file — deferred; server-side tenant
 *    `training` flag is required first (§53.1 NOTE-defer).
 */
@Singleton
class TrainingPreferences @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("training_prefs", Context.MODE_PRIVATE)

    // ---------------------------------------------------------------------------
    // §53.1 — Master toggle
    // ---------------------------------------------------------------------------

    private val _trainingModeEnabledFlow = MutableStateFlow(
        prefs.getBoolean(KEY_TRAINING_ENABLED, false),
    )

    /**
     * Observable training-mode flag.  Collect wherever the UI must react to
     * a mid-session enable/disable (e.g. top-bar banner, ViewModel guards).
     */
    val trainingModeEnabledFlow: StateFlow<Boolean> = _trainingModeEnabledFlow.asStateFlow()

    /**
     * Training-mode master switch.
     *
     * Writing this pref causes [trainingModeEnabledFlow] to emit immediately.
     * Any ViewModel that depends on training mode should collect the flow
     * rather than reading this property directly.
     */
    var trainingModeEnabled: Boolean
        get() = prefs.getBoolean(KEY_TRAINING_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(KEY_TRAINING_ENABLED, value).apply()
            _trainingModeEnabledFlow.value = value
        }

    // ---------------------------------------------------------------------------
    // §53.5 — Onboarding checklist step completion
    // ---------------------------------------------------------------------------

    /**
     * §53.5 — Set of onboarding-checklist step IDs the user has ticked off.
     *
     * Step IDs are defined in [TrainingChecklistStep.id].  Returns an empty set
     * on a fresh install or after a training-data reset.
     */
    val checklistCompletedSteps: Set<Int>
        get() {
            val raw = prefs.getString(KEY_CHECKLIST_STEPS, null) ?: return emptySet()
            return runCatching {
                raw.split(",")
                    .mapNotNull { it.trim().toIntOrNull() }
                    .toSet()
            }.getOrDefault(emptySet())
        }

    /**
     * Mark checklist [stepId] as completed.  Idempotent.
     */
    fun markChecklistStepCompleted(stepId: Int) {
        val updated = checklistCompletedSteps + stepId
        prefs.edit()
            .putString(KEY_CHECKLIST_STEPS, updated.joinToString(","))
            .apply()
    }

    // ---------------------------------------------------------------------------
    // §53.3 — Reset training data
    // ---------------------------------------------------------------------------

    /**
     * §53.3 — Clear all training-mode persisted state (checklist completion).
     *
     * Does **not** turn off [trainingModeEnabled] — the user must do that
     * explicitly via the Settings toggle.  This wipes only the side-effects
     * produced while training mode was active so the user can restart the
     * onboarding experience without fully disabling the mode.
     *
     * In-memory data held by [TrainingDataSource] implementations is reset
     * by calling their own `reset()` method; this prefs class is not
     * responsible for that.
     */
    fun resetTrainingData() {
        prefs.edit()
            .remove(KEY_CHECKLIST_STEPS)
            .apply()
    }

    // ---------------------------------------------------------------------------
    private companion object {
        const val KEY_TRAINING_ENABLED  = "training_mode_enabled"
        const val KEY_CHECKLIST_STEPS   = "training_checklist_steps"
    }
}
