package com.bizarreelectronics.crm.util

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.content.getSystemService
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Centralised haptic feedback. Wraps the platform Vibrator API so the rest
 * of the app just calls [HapticFeedback.fire] with a [HapticKind] and doesn't
 * have to think about SDK version gates or whether the user has haptics
 * disabled in settings.
 *
 * Enabled state is driven by [AppPreferences.hapticEnabled] which defaults
 * to ON. A toggle in the settings screen flips the underlying preference —
 * this helper reads it on every call so changes take effect immediately.
 */
enum class HapticKind {
    /** Short click: record saved, add to cart, etc. */
    Tick,
    /** Double pulse: payment complete, barcode scanned. */
    DoubleTap,
    /** Long buzz: error, form validation failure. */
    Error,
}

@Singleton
class HapticFeedback @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appPreferences: AppPreferences,
) {

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService<VibratorManager>()?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService<Vibrator>()
        }
    }

    fun fire(kind: HapticKind) {
        if (!appPreferences.hapticEnabled) return
        val v = vibrator ?: return
        if (!v.hasVibrator()) return

        val effect = when (kind) {
            HapticKind.Tick -> VibrationEffect.createOneShot(20L, VibrationEffect.DEFAULT_AMPLITUDE)
            HapticKind.DoubleTap -> VibrationEffect.createWaveform(
                longArrayOf(0, 25, 50, 25),
                intArrayOf(0, 200, 0, 200),
                -1,
            )
            HapticKind.Error -> VibrationEffect.createOneShot(150L, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        v.vibrate(effect)
    }
}
