package com.bizarreelectronics.crm.ui.theme

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.TweenSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer

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

// ---------------------------------------------------------------------------
// AnimatedContent helpers — §30.4
//
// Wires Reduce Motion into AnimatedContent.transitionSpec so every step
// wizard and page-level transition respects the user's accessibility choice.
// "Direction" is +1 for forward (increasing step index) and -1 for backward.
// ---------------------------------------------------------------------------

/**
 * Standard horizontal step-wizard [ContentTransform] for [AnimatedContent].
 *
 * When [reduceMotion] is true the transition collapses to an instant
 * cross-fade (near-zero duration) so users with vestibular / motion sensitivity
 * are not disturbed by horizontal sliding animations.
 *
 * @param direction +1 = slide left (forward), -1 = slide right (backward).
 * @param reduceMotion Read from [com.bizarreelectronics.crm.util.rememberReduceMotion].
 *
 * Example in an [AnimatedContent] block:
 * ```kotlin
 * val reduceMotion = rememberReduceMotion(appPrefs)
 * AnimatedContent(
 *     targetState = currentStep,
 *     transitionSpec = {
 *         stepWizardTransition(
 *             direction = if (targetState > initialState) 1 else -1,
 *             reduceMotion = reduceMotion,
 *         )
 *     },
 *     label = "step_transition",
 * ) { step -> ... }
 * ```
 */
fun stepWizardTransition(direction: Int, reduceMotion: Boolean): ContentTransform {
    return if (reduceMotion) {
        // Instant cross-fade — no motion, just a visual state swap.
        fadeIn(animationSpec = tween(durationMillis = 0)) togetherWith
            fadeOut(animationSpec = tween(durationMillis = 0))
    } else {
        val dur = 280
        val enter: EnterTransition =
            slideInHorizontally(animationSpec = tween(dur)) { it * direction } +
                fadeIn(animationSpec = tween(dur, delayMillis = 60))
        val exit: ExitTransition =
            slideOutHorizontally(animationSpec = tween(dur)) { -it * direction } +
                fadeOut(animationSpec = tween(180))
        enter togetherWith exit
    }
}

/**
 * Simple fade-only [ContentTransform] for content swaps where direction is
 * irrelevant (e.g. inline content update, not a step wizard).
 *
 * When [reduceMotion] is true, duration collapses to 0 (instant swap).
 */
fun fadeTransition(reduceMotion: Boolean): ContentTransform {
    val dur = if (reduceMotion) 0 else 200
    return fadeIn(animationSpec = tween(dur)) togetherWith
        fadeOut(animationSpec = tween(dur))
}

// ---------------------------------------------------------------------------
// §70.1 Duration tokens
//
// Named integer millisecond constants for use with tween()/keyframes().
// Always prefer these over raw literals so a global retune only changes one
// place. reduceMotion callers: pass these through reduceMotionDuration() or
// use the tweenOrInstant() shorthand.
// ---------------------------------------------------------------------------

/**
 * §70.1 — Named duration tokens.
 *
 * | Token      | ms  | Use                                |
 * |------------|-----|------------------------------------|
 * | INSTANT    | 0   | Reduce Motion snap                 |
 * | FAST       | 150 | Button press / ripple              |
 * | STANDARD   | 300 | Screen enter                       |
 * | EMPHASIZED | 450 | Shared-element / FAB morph         |
 * | SLOW       | 600 | Onboarding / big reveal            |
 *
 * Reduce-motion: pipe through [reduceMotionDuration] or use [tweenOrInstant].
 */
object MotionDuration {
    const val INSTANT    = 0
    const val FAST       = 150
    const val STANDARD   = 300
    const val EMPHASIZED = 450
    const val SLOW       = 600
}

/**
 * Collapses [durationMs] to 0 when [reduceMotion] is true, otherwise returns
 * [durationMs] unchanged. Use wherever a raw integer duration is needed
 * (keyframes, rememberInfiniteTransition, etc.).
 */
fun reduceMotionDuration(durationMs: Int, reduceMotion: Boolean): Int =
    if (reduceMotion) MotionDuration.INSTANT else durationMs

/**
 * Convenience shorthand: returns a [TweenSpec]<[T]> with [durationMs] when
 * [reduceMotion] is false, or an instant (0 ms) tween when true.
 */
fun <T> tweenOrInstant(
    durationMs: Int,
    reduceMotion: Boolean,
    easing: Easing = androidx.compose.animation.core.FastOutSlowInEasing,
    delayMillis: Int = 0,
): TweenSpec<T> = tween(
    durationMillis = reduceMotionDuration(durationMs, reduceMotion),
    easing = easing,
    delayMillis = if (reduceMotion) 0 else delayMillis,
)

// ---------------------------------------------------------------------------
// §70.2 Easing constants + M3 Expressive spring
// ---------------------------------------------------------------------------

/**
 * §70.2 — Standard enter easing. Matches Material Motion "emphasised decelerate"
 * cubic-bezier: fast start, gentle settle. Use for elements entering the screen.
 */
val EnterEasing: CubicBezierEasing = CubicBezierEasing(0.2f, 0f, 0f, 1f)

/**
 * §70.2 — Standard exit easing. Matches Material Motion "emphasised accelerate"
 * cubic-bezier: gentle start, fast exit. Use for elements leaving the screen.
 */
val ExitEasing: CubicBezierEasing = CubicBezierEasing(0.4f, 0f, 1f, 1f)

/**
 * §70.2 — Material Expressive spring preset.
 *
 * stiffness=400 / dampingRatio=0.75 per the M3 Expressive motion spec.
 * Use for FAB morphs, shared-element containers, and personality moments
 * where you want the characteristic M3 Expressive "snappy + slight overshoot".
 *
 * Already integrated with [MotionScheme.expressive()] in Theme.kt; use this
 * when you need a concrete [SpringSpec] for [animateFloatAsState] /
 * [animateDpAsState] outside an AnimatedContent block.
 */
val expressiveSpring: SpringSpec<Float> = spring(
    dampingRatio = 0.75f,
    stiffness    = 400f,
)

// ---------------------------------------------------------------------------
// §70.3 Shared-element helpers
//
// SharedTransitionLayout + Modifier.sharedElement wiring helpers.
// Call sites are tablet list→detail screens that already host a
// SharedTransitionScope (provided by the NavHost's sharedElementTransition
// or an explicit SharedTransitionLayout wrapper).
//
// Usage pattern:
//   SharedTransitionLayout {
//       NavHost(...) {
//           composable("list") {
//               AnimatedVisibilityScope { // provided by NavHost
//                   TicketListItem(
//                       modifier = Modifier.sharedTicketElement(
//                           scope = this@SharedTransitionLayout,
//                           visibilityScope = this@composable,
//                           ticketId = ticket.id,
//                           element = SharedTicketElement.TITLE,
//                       )
//                   )
//               }
//           }
//           composable("detail/{id}") { ... same key ... }
//       }
//   }
// ---------------------------------------------------------------------------

/**
 * §70.3 — Named shared-element roles for list→detail transitions on tablet.
 *
 * Each value maps to a unique sharedElement key so the framework can match
 * the departing and arriving composables across the nav transition.
 */
enum class SharedTicketElement {
    /** The ticket title text. */
    TITLE,
    /** The device photo thumbnail (AsyncImage). */
    PHOTO_THUMB,
    /** The status chip (text + background container). */
    STATUS_CHIP,
}

/**
 * §70.3 — Stable shared-element key for a ticket UI element.
 *
 * Returns a string key unique to [ticketId] + [element] so two tickets in the
 * same list never share a key, and list + detail use identical keys by calling
 * this same function.
 *
 * @param ticketId  Database ID of the ticket.
 * @param element   Which part of the ticket card is animating.
 */
fun sharedTicketKey(ticketId: Long, element: SharedTicketElement): String =
    "ticket:$ticketId:${element.name.lowercase()}"

// ---------------------------------------------------------------------------
// §70.4 Predictive back helper
// ---------------------------------------------------------------------------

/**
 * §70.4 — Returns a [Modifier] that applies a predictive-back scale + translate
 * preview to a composable driven by a back-gesture progress value [0f..1f].
 *
 * At [progress]=0 the modifier is a no-op (identity transform). As progress
 * approaches 1 the content scales down to 0.9× and translates toward the
 * leading edge, matching the Android 14 predictive-back aesthetic.
 *
 * When [reduceMotion] is true the modifier is always a no-op — users with
 * vestibular sensitivity should not see the parallax effect.
 *
 * Typical usage with [androidx.activity.compose.PredictiveBackHandler]:
 * ```kotlin
 * var backProgress by remember { mutableFloatStateOf(0f) }
 * PredictiveBackHandler { progress ->
 *     progress.collect { backProgress = it.progress }
 *     // navigation pop happens here when coroutine completes
 * }
 * Box(modifier = Modifier.predictiveBackPreview(backProgress, reduceMotion))
 * ```
 */
fun Modifier.predictiveBackPreview(
    progress: Float,
    reduceMotion: Boolean,
): Modifier {
    if (reduceMotion || progress == 0f) return this
    val scale = 1f - (progress * 0.1f)          // 1.0 → 0.9
    val translateX = -(progress * 32f)           // 0 → -32px (slide toward leading edge)
    return this.graphicsLayer {
        scaleX = scale
        scaleY = scale
        translationX = translateX
    }
}

// ---------------------------------------------------------------------------
// §70.5 Reduce-Motion — static replacement for animated effects
// ---------------------------------------------------------------------------

/**
 * §70.5 — Returns a tint [Color] to replace animated decorative effects
 * (confetti, shake-on-error shimmer, celebration overlay) when Reduce Motion
 * is active.
 *
 * Instead of playing a particle / wiggle animation, callers flash this color
 * once as a background tint on the container for one frame — no movement,
 * just a perceptible visual acknowledgment.
 *
 * Mapping:
 *   [ReduceMotionAccentType.SUCCESS] → SuccessGreen (from Theme.kt semantic tokens)
 *   [ReduceMotionAccentType.ERROR]   → ErrorRed
 *   [ReduceMotionAccentType.WARNING] → WarningAmber
 *   [ReduceMotionAccentType.NEUTRAL] → brand cream (BrandAccent)
 *
 * Pass [active]=false to get [Color.Transparent] (no highlight) — useful when
 * the animation hasn't triggered yet or reduce-motion is off.
 */
enum class ReduceMotionAccentType { SUCCESS, ERROR, WARNING, NEUTRAL }

/**
 * §70.5 — Static accent color to replace animated decorations under Reduce Motion.
 *
 * @param type    Which semantic role this accent represents.
 * @param active  True once the event has fired (e.g., form submitted, error detected).
 *                False = transparent (no effect yet).
 */
fun reduceMotionStaticAccent(type: ReduceMotionAccentType, active: Boolean): Color {
    if (!active) return Color.Transparent
    return when (type) {
        ReduceMotionAccentType.SUCCESS -> SuccessGreen
        ReduceMotionAccentType.ERROR   -> ErrorRed
        ReduceMotionAccentType.WARNING -> WarningAmber
        ReduceMotionAccentType.NEUTRAL -> BrandAccent
    }
}

/**
 * §70.5 — Collapses a [SpringSpec]<[Float]> to a zero-duration [TweenSpec]<[Float]>
 * when [reduceMotion] is true, allowing spring-driven animations (e.g. FAB entry,
 * checkmark draw) to be replaced with snaps rather than animated curves.
 *
 * Returns the original [springSpec] unchanged when [reduceMotion] is false so
 * call sites need no conditional logic of their own.
 */
fun springOrInstant(
    springSpec: SpringSpec<Float>,
    reduceMotion: Boolean,
): AnimationSpec<Float> =
    if (reduceMotion) tween(durationMillis = 0) else springSpec
