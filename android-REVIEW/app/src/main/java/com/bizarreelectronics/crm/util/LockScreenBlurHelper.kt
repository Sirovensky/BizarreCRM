package com.bizarreelectronics.crm.util

import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.view.View
import androidx.annotation.RequiresApi
import timber.log.Timber

/**
 * L2491 — Lock-Screen blur helper.
 *
 * Applies a Gaussian blur to a [View] when the app moves to the background
 * (ProcessLifecycleOwner ON_STOP) if customer PII may be visible on screen.
 * Clears the effect when the app returns to the foreground (ON_START).
 *
 * ## API level gating
 * [RenderEffect] is only available on API 31 (Android 12, S) and above.
 * On older devices this helper is a no-op; FLAG_SECURE already prevents
 * screenshots on those devices.
 *
 * ## Usage
 * Mount this in [com.bizarreelectronics.crm.MainActivity.onPause] guarded by
 * the existing FLAG_SECURE state, or attach the [ProcessLifecycleOwner]
 * observer from [com.bizarreelectronics.crm.BizarreCrmApp.onCreate].
 *
 * ```kotlin
 * // In BizarreCrmApp lifecycle observer:
 * override fun onStop(owner: LifecycleOwner) {
 *     rootView?.let { LockScreenBlurHelper.applyBlur(it) }
 * }
 * override fun onStart(owner: LifecycleOwner) {
 *     rootView?.let { LockScreenBlurHelper.clearBlur(it) }
 * }
 * ```
 *
 * ## Thread safety
 * All methods must be called on the main thread (they touch [View]).
 */
object LockScreenBlurHelper {

    private const val TAG = "LockScreenBlurHelper"

    /** Blur radius in pixels applied on both axes. 25 f is strong enough to obscure PII. */
    private const val BLUR_RADIUS = 25f

    /**
     * Applies a Gaussian blur [RenderEffect] to [view] on API 31+.
     *
     * On API < 31 this is a no-op — FLAG_SECURE handles screenshot prevention
     * on those devices and the compositor does not support RenderEffect.
     *
     * @param view The root view to blur (e.g. the activity's decorView or
     *   a ComposeView wrapping the entire scaffold).
     */
    fun applyBlur(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyBlurApi31(view)
        } else {
            Timber.tag(TAG).d("applyBlur: RenderEffect not available on API %d — skipping", Build.VERSION.SDK_INT)
        }
    }

    /**
     * Clears any blur [RenderEffect] previously applied to [view] on API 31+.
     *
     * On API < 31 this is a no-op.
     *
     * @param view The same root view passed to [applyBlur].
     */
    fun clearBlur(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            clearBlurApi31(view)
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun applyBlurApi31(view: View) {
        val effect = RenderEffect.createBlurEffect(
            BLUR_RADIUS,
            BLUR_RADIUS,
            Shader.TileMode.CLAMP,
        )
        view.setRenderEffect(effect)
        Timber.tag(TAG).d("applyBlur: Gaussian blur applied (radius=%.0f)", BLUR_RADIUS)
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun clearBlurApi31(view: View) {
        view.setRenderEffect(null)
        Timber.tag(TAG).d("clearBlur: RenderEffect cleared")
    }

    /**
     * Returns true if the current device supports [RenderEffect]-based blur.
     * Callers can use this to decide whether additional PII-hiding measures are
     * needed on older API levels.
     */
    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
}
