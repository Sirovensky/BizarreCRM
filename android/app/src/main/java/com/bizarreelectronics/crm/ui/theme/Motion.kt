package com.bizarreelectronics.crm.ui.theme

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween

/**
 * Bizarre CRM motion tokens — ActionPlan §30.4 / §1.4 line 193.
 *
 * ## Spring presets
 *
 * [BizarreMotion.expressive] — bouncy, personality-driven. Use for
 *   high-delight moments: FAB entry, success checkmarks, onboarding steps.
 *   dampingRatio=0.6 (underdamped → slight overshoot) + StiffnessMediumLow
 *   gives a springy feel without being distracting.
 *
 * [BizarreMotion.standard] — utility-first. Use for routine navigation,
 *   list-item expand/collapse, bottom-sheet presentation.
 *   dampingRatio=0.9 (near-critically damped) + StiffnessMedium feels snappy.
 *
 * ## Timing tokens (§30.10 / §70)
 *
 * Duration and easing constants for tween-based animations (shared-element
 * enter/exit, page transitions, alpha fades):
 *
 *   [BizarreMotion.DURATION_SHORT]  — 150ms  snappy micro-interactions
 *   [BizarreMotion.DURATION_MEDIUM] — 300ms  standard page/content transitions
 *   [BizarreMotion.DURATION_LONG]   — 500ms  hero / shared-element transitions
 *
 * ## MotionScheme.expressive()
 *
 * Theme.kt wires `MotionScheme.expressive()` into [MaterialExpressiveTheme]
 * when `BuildConfig.USE_EXPRESSIVE_THEME=true`. The BOM-overridden
 * `material3 1.5.0-alpha18` includes this API; it is still alpha-gated via
 * `@ExperimentalMaterial3ExpressiveApi` in Theme.kt.
 *
 * ## Reduce-Motion
 *
 * Call [motionSpec] with the current reduceMotion flag. When true, returns a
 * near-zero-duration spring (perceptually identical to a snap). All spring
 * call sites should route through this helper.
 *
 * Integration with [com.bizarreelectronics.crm.util.ReduceMotion]:
 * ```kotlin
 * val reduceMotion = rememberReduceMotion(appPreferences)
 * animateFloatAsState(target, animationSpec = motionSpec(reduceMotion))
 * ```
 */
object BizarreMotion {

    // ---- Timing constants ------------------------------------------------

    /** 150ms — micro-interactions (chip press, icon swap, badge count change). */
    const val DURATION_SHORT = 150

    /** 300ms — standard screen/content transitions, bottom-sheet enter/exit. */
    const val DURATION_MEDIUM = 300

    /** 500ms — hero animations, shared-element row→detail on tablet. */
    const val DURATION_LONG = 500

    // ---- Spring presets --------------------------------------------------

    /**
     * Expressive spring — slight overshoot, personality-driven delight.
     * dampingRatio=0.6, stiffness=StiffnessMediumLow (~200).
     */
    val expressive: SpringSpec<Float> = spring(
        dampingRatio = 0.6f,
        stiffness    = Spring.StiffnessMediumLow,
    )

    /**
     * Standard spring — utility-first, near-critically damped.
     * dampingRatio=0.9, stiffness=StiffnessMedium (~400).
     */
    val standard: SpringSpec<Float> = spring(
        dampingRatio = 0.9f,
        stiffness    = Spring.StiffnessMedium,
    )

    // ---- Tween convenience specs -----------------------------------------

    /** Tween for fade/alpha transitions. Uses [DURATION_MEDIUM]. */
    fun tweenMedium() = tween<Float>(durationMillis = DURATION_MEDIUM)

    /** Tween for page-level enter/exit. Uses [DURATION_LONG]. */
    fun tweenLong() = tween<Float>(durationMillis = DURATION_LONG)
}

/**
 * Returns the appropriate [SpringSpec]<[Float]> for the given [reduceMotion] flag.
 *
 * When [reduceMotion] is true, returns a very-high-stiffness / fully-damped
 * spring (StiffnessVeryHigh + dampingRatio=1f) that completes in one frame —
 * effectively a snap() without importing the snap spec at call sites.
 *
 * When false, returns [BizarreMotion.standard] as the safe default. Callers
 * that want the expressive preset should use [BizarreMotion.expressive]
 * directly after checking [reduceMotion] themselves.
 *
 * @param reduceMotion read from [com.bizarreelectronics.crm.util.ReduceMotion.isReduceMotion]
 *   or [com.bizarreelectronics.crm.util.rememberReduceMotion].
 */
fun motionSpec(reduceMotion: Boolean): SpringSpec<Float> =
    if (reduceMotion) {
        spring(
            dampingRatio = 1f,
            stiffness    = Spring.StiffnessHigh,
        )
    } else {
        BizarreMotion.standard
    }
