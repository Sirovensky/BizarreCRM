package com.bizarreelectronics.crm.util

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.content.getSystemService
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §69 Haptics Catalog — shared controller that maps high-level haptic events to
 * the correct [HapticFeedbackConstants] / [VibrationEffect] call for the running
 * API level.
 *
 * Decision order for every [fire] call:
 *  1. [AppPreferences.hapticEnabled] must be true (in-app toggle).
 *  2. System `Settings.System.HAPTIC_FEEDBACK_ENABLED` must be 1 (respects
 *     Android Settings > Sound > Touch feedback — §69.3).
 *  3. Quiet mode (RINGER_MODE_SILENT) suppresses haptics — §69.3.
 *  4. API 30+ ([Build.VERSION_CODES.R]) uses [android.view.HapticFeedbackConstants]
 *     semantic constants via [android.view.View.performHapticFeedback]; for
 *     composables without a View we fall through to [Vibrator].
 *  5. [Vibrator] access follows §69 guidance:
 *       API 31+ → [VibratorManager.getDefaultVibrator]
 *       API < 31 → deprecated [Context.VIBRATOR_SERVICE]
 *
 * ### Supported events (§69.1 + §69.2)
 *
 * | [HapticEvent]               | Constant / pattern                        | Fallback      |
 * |-----------------------------|-------------------------------------------|---------------|
 * | [HapticEvent.SwipeRelease]  | GESTURE_END (API 30+)                     | short 15ms    |
 * | [HapticEvent.ToggleChange]  | CONTEXT_CLICK (API 23+)                   | 15ms          |
 * | [HapticEvent.PaymentSuccess]| CONFIRM (API 30+) + extended 60ms pulse   | 30ms + 60ms   |
 * | [HapticEvent.PhotoShutter]  | CLOCK_TICK (API 21+)                      | 10ms          |
 * | [HapticEvent.DragHover]     | SEGMENT_FREQUENT_TICK (API 30+)           | 5ms           |
 * | [HapticEvent.Celebration]   | custom waveform 40+60+40+60+40 (§69.2)    | same waveform |
 * | [HapticEvent.ErrorEscalate] | 200ms heavy pulse (§69.2)                 | same          |
 *
 * This controller does NOT replace existing [HapticFeedback] for [HapticKind] events
 * (Tick / DoubleTap / Error). It adds the §69 catalog events that have no existing
 * mapping. Call sites that already use [HapticFeedback] or direct
 * [view.performHapticFeedback] (BarcodeScanScreen, KioskCheckInScreen, signature
 * pads, TicketSwipeRow, PinKeypad, PinLockScreen, LoginScreen) are left untouched.
 *
 * Usage from Compose:
 * ```kotlin
 * val hapticCtrl = LocalAppHapticController.current
 * Button(onClick = {
 *     hapticCtrl?.fire(HapticEvent.ToggleChange)
 *     toggle()
 * }) { ... }
 * ```
 *
 * Usage from a View-backed call site (has a [android.view.View]):
 * ```kotlin
 * view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
 * ```
 * Prefer [view.performHapticFeedback] for View-backed sites — it automatically
 * respects the system haptic-feedback flag without extra checks.
 */

/** §69 catalog events routed through [HapticController]. */
enum class HapticEvent {
    /** Swipe action release — GESTURE_END. §69.1 */
    SwipeRelease,
    /** Toggle on/off state change — CONTEXT_CLICK. §69.1 */
    ToggleChange,
    /** Payment / charge confirmed — CONFIRM + 60ms sustained. §69.1 */
    PaymentSuccess,
    /** Photo shutter / gallery upload initiated — CLOCK_TICK. §69.1 */
    PhotoShutter,
    /** Drag-over-target hover pulse — SEGMENT_FREQUENT_TICK. §69.1 */
    DragHover,
    /** Celebration waveform (first sale of the day, queue clear). §69.2 */
    Celebration,
    /** Error escalation on 3rd consecutive wrong PIN. §69.2 */
    ErrorEscalate,
}

@Singleton
class HapticController @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appPreferences: AppPreferences,
) {

    // --- Vibrator access (§69 API guidance) ------------------------------------

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService<VibratorManager>()?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService<Vibrator>()
        }
    }

    // ---------------------------------------------------------------------------

    /**
     * Fire a §69 catalog haptic event.
     *
     * No-ops if:
     * - The in-app [AppPreferences.hapticEnabled] toggle is off, OR
     * - `Settings.System.HAPTIC_FEEDBACK_ENABLED` is 0 (user disabled in Android Settings), OR
     * - Ringer mode is silent (quiet mode suppresses haptics per §69.3).
     */
    fun fire(event: HapticEvent) {
        if (!appPreferences.hapticEnabled) return
        if (!isSystemHapticEnabled()) return
        if (!isAccessibilityVibrationEnabled()) return   // §69.3 OEM accessibility setting
        if (isQuietMode()) return                         // §69.3 quiet mode

        val v = vibrator ?: return
        if (!v.hasVibrator()) return

        val effect: VibrationEffect = when (event) {
            HapticEvent.SwipeRelease -> {
                // §69.1 — swipe action release: GESTURE_END feel.
                // HapticFeedbackConstants.GESTURE_END (API 30+) is a View-level semantic
                // constant. VibrationEffect has no matching predefined ID for GESTURE_END
                // across all OEMs, so we use a medium 15ms click — the same weight the
                // Compose SwipeToDismissBox uses internally for its threshold feedback.
                // Call sites that have a View reference (e.g. TicketSwipeRow) fire
                // view.performHapticFeedback(GESTURE_END) directly — this path covers
                // Compose-only sites that use the HapticController.
                return shortTick(15L, v)
            }

            HapticEvent.ToggleChange -> {
                // §69.1 — toggle on/off: CONTEXT_CLICK.
                // CONTEXT_CLICK is API 23+ as a HapticFeedbackConstants constant but
                // VibrationEffect.createPredefined only accepts predefined IDs (not
                // HapticFeedbackConstants values). We call Vibrator directly with a
                // short tick matching the expected weight of a toggle flick.
                return shortTick(15L, v)
            }

            HapticEvent.PaymentSuccess -> {
                // §69.1 — payment success: CONFIRM (API 30+) + extended 60ms sustained.
                // Pattern: 0ms delay, 20ms confirm-strength, 30ms gap, 60ms sustained.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    VibrationEffect.createWaveform(
                        longArrayOf(0L, 20L, 30L, 60L),
                        intArrayOf(0, VibrationEffect.DEFAULT_AMPLITUDE, 0, VibrationEffect.DEFAULT_AMPLITUDE),
                        -1,
                    )
                } else {
                    // Fallback: double bump — 30ms + 60ms
                    VibrationEffect.createWaveform(
                        longArrayOf(0L, 30L, 30L, 60L),
                        -1,
                    )
                }
            }

            HapticEvent.PhotoShutter -> {
                // §69.1 — photo shutter / gallery upload: CLOCK_TICK feel — very short 10ms.
                VibrationEffect.createOneShot(10L, VibrationEffect.DEFAULT_AMPLITUDE)
            }

            HapticEvent.DragHover -> {
                // §69.1 — drag-over-target hover: ultra-short 5ms pulse.
                // SEGMENT_FREQUENT_TICK maps to a 5ms-class tick on supported hardware.
                VibrationEffect.createOneShot(5L, VibrationEffect.DEFAULT_AMPLITUDE)
            }

            HapticEvent.Celebration -> {
                // §69.2 — celebration waveform: first sale, queue clear.
                // createWaveform(timings, -1) plays once.
                VibrationEffect.createWaveform(
                    longArrayOf(0L, 40L, 60L, 40L, 60L, 40L),
                    -1,
                )
            }

            HapticEvent.ErrorEscalate -> {
                // §69.2 — 3rd consecutive wrong PIN / escalated error: heavy 200ms pulse.
                VibrationEffect.createOneShot(200L, VibrationEffect.DEFAULT_AMPLITUDE)
            }
        }

        v.vibrate(effect)
    }

    // ---------------------------------------------------------------------------
    // §69.3 — Respect system settings
    // ---------------------------------------------------------------------------

    /**
     * Returns false when the user has disabled Touch feedback in Android Settings
     * (Settings > Sound > Touch feedback = off). This is the `HAPTIC_FEEDBACK_ENABLED`
     * system setting — distinct from `ACCESSIBILITY_VIBRATION_ENABLED`.
     *
     * Note: [android.view.View.performHapticFeedback] automatically checks this flag
     * internally; we only need to check it explicitly when going through [Vibrator]
     * directly (which is what this controller does for most events).
     */
    private fun isSystemHapticEnabled(): Boolean =
        Settings.System.getInt(
            context.contentResolver,
            Settings.System.HAPTIC_FEEDBACK_ENABLED,
            1, // default ON if key absent
        ) != 0

    /**
     * §69.3 — Honor `ACCESSIBILITY_VIBRATION_ENABLED` system setting.
     *
     * This is not a public Android SDK constant and is only reliably available on
     * Samsung and some other OEM distributions. We do a best-effort check via the
     * raw key string; if the key is absent (most stock Android devices), we default
     * to enabled (1) so users on AOSP/Pixel builds are unaffected.
     *
     * Returns false only when the key explicitly equals 0 on an OEM that exposes it.
     */
    private fun isAccessibilityVibrationEnabled(): Boolean =
        Settings.System.getInt(
            context.contentResolver,
            "accessibility_vibration_enabled",
            1, // default ON — absent on stock Android = not disabled
        ) != 0

    /**
     * Returns true when the device is in silent/ringer-off mode.
     *
     * §69.3 — Quiet mode (RINGER_MODE_SILENT) disables haptics. VIBRATE mode
     * retains them. Android does not expose a dedicated "quiet mode → no haptics"
     * flag; the conventional mapping is RINGER_MODE_SILENT = suppress all feedback.
     */
    private fun isQuietMode(): Boolean {
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                ?: return false
        return audioManager.ringerMode == android.media.AudioManager.RINGER_MODE_SILENT
    }

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    /** Fire a one-shot vibration and return immediately (helper for fallback paths). */
    private fun shortTick(durationMs: Long, v: Vibrator) {
        v.vibrate(
            VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE),
        )
    }

}
