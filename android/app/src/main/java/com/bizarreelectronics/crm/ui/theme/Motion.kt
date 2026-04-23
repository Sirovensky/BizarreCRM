package com.bizarreelectronics.crm.ui.theme

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring

/**
 * Bizarre CRM motion tokens — ActionPlan §1.4 line 193.
 *
 * Two spring presets cover the vast majority of UI transitions:
 *
 *   [BizarreMotion.expressive] — bouncy, personality-driven. Use for
 *     high-delight moments: FAB entry, success checkmarks, onboarding steps.
 *     dampingRatio=0.6 (underdamped → slight overshoot) + StiffnessMediumLow
 *     (slower settle) gives a springy feel without being distracting.
 *
 *   [BizarreMotion.standard] — utility-first. Use for routine navigation,
 *     list-item expand/collapse, bottom-sheet presentation.
 *     dampingRatio=0.9 (critically near-damped → minimal overshoot) +
 *     StiffnessMedium (responsive) feels snappy and purposeful.
 *
 * Reduce-motion: call [motionSpec] with the current reduceMotion flag instead
 * of using the presets directly. When [reduceMotion]=true the helper returns
 * a near-zero-duration spring that is perceptually identical to a snap().
 *
 * Integration with [com.bizarreelectronics.crm.util.ReduceMotion]:
 * ```kotlin
 * val reduceMotion = rememberReduceMotion(appPreferences)
 * animateFloatAsState(target, animationSpec = motionSpec(reduceMotion))
 * ```
 */
object BizarreMotion {

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
