package com.bizarreelectronics.crm.ui.components.shared

// NOTE: [BrandSkeleton] (shimmer list-row placeholder) lives in SharedComponents.kt
// (same package). This file adds two supplementary skeleton shapes for non-list
// contexts (card-grid and detail-screen header) so Wave 4 agents have composables
// to use without duplicating the shimmer logic.
//
// §66.2: "Skeleton shimmer ≤ 300ms before real data."
// The shimmer animation uses tween(durationMillis = 300) + RepeatMode.Reverse — the
// same spec as BrandSkeleton — so all skeletons share identical timing.
//
// §75.4: [SkeletonTransition] wraps [AnimatedContent] to cross-fade between the
// skeleton placeholder and real content. Screens must replace plain `when { isLoading
// -> BrandSkeleton(...) ... }` blocks with [SkeletonTransition] calls so the
// transition is a smooth dissolve instead of an abrupt state-switch jump.

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp

/**
 * Shimmer placeholder for card-grid layouts (e.g. Reports screen, Dashboard tiles).
 *
 * Renders [columns] × [rows] rounded rectangle cards. Uses the same 300ms shimmer
 * timing as [BrandSkeleton].
 *
 * @param rows    Number of card rows.
 * @param columns Number of cards per row (default 2).
 * @param modifier Applied to the outer [Column].
 */
@Composable
fun CardGridSkeleton(
    rows: Int = 2,
    columns: Int = 2,
    modifier: Modifier = Modifier,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "cardGridSkeleton")
    val shimmerAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 300, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "shimmerAlpha",
    )
    val surface2 = MaterialTheme.colorScheme.surfaceVariant

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        repeat(rows) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                repeat(columns) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(80.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(surface2.copy(alpha = shimmerAlpha)),
                    )
                }
            }
        }
    }
}

/**
 * Shimmer placeholder for detail-screen headers (e.g. Customer detail,
 * Ticket detail — avatar + 2-line name / ID block).
 *
 * Wave 4 targets: CustomerDetailScreen, TicketDetailScreen.
 *
 * @param modifier Applied to the outer [Row].
 */
@Composable
fun DetailHeaderSkeleton(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "detailHeaderSkeleton")
    val shimmerAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 300, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "shimmerAlpha",
    )
    val surface2 = MaterialTheme.colorScheme.surfaceVariant
    val surfaceVar = MaterialTheme.colorScheme.surfaceContainerHigh

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Avatar placeholder
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(28.dp)) // circle
                .background(surface2.copy(alpha = shimmerAlpha)),
        )
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.55f)
                    .height(18.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(surface2.copy(alpha = shimmerAlpha)),
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.35f)
                    .height(13.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(surfaceVar.copy(alpha = shimmerAlpha * 0.6f)),
            )
        }
        // Trailing action placeholder (e.g. call / sms buttons)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(2) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(surfaceVar.copy(alpha = shimmerAlpha * 0.5f)),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// §75.4 SkeletonTransition — cross-fade skeleton → content
//
// Replaces the abrupt `when { isLoading -> BrandSkeleton(...) }` branch with
// an [AnimatedContent] dissolve so screens never "jump" on data arrival.
//
// Usage (replaces plain when-branch on isLoading):
//
//   SkeletonTransition(
//       isLoading = state.isLoading,
//       skeleton  = { BrandSkeleton(rows = 6) },
//   ) {
//       // real content here — only composed when isLoading == false
//       LazyColumn { ... }
//   }
//
// Accessibility:
//   • The skeleton slot carries contentDescription "Loading" (via the Box
//     wrapper in the caller — callers retain full control over semantics).
//   • AnimatedContent label "skeletonTransition" is used for tooling.
//
// Reduce Motion:
//   Pass [reduceMotion] = true (e.g. from rememberReduceMotion()) to collapse
//   the cross-fade to an instant snap so users with vestibular sensitivity do
//   not perceive the dissolve. Defaults to false (animated) for normal builds.
// ---------------------------------------------------------------------------

/**
 * §75.4 — Wraps [AnimatedContent] to cross-fade between a [skeleton] composable
 * (shown while [isLoading] is `true`) and real [content] (shown when `false`).
 *
 * Prior pattern (abrupt jump — do not use):
 * ```kotlin
 * when {
 *     state.isLoading -> BrandSkeleton(rows = 6)
 *     else            -> LazyColumn { ... }
 * }
 * ```
 *
 * New pattern (smooth dissolve):
 * ```kotlin
 * SkeletonTransition(
 *     isLoading = state.isLoading,
 *     skeleton  = { BrandSkeleton(rows = 6) },
 * ) {
 *     LazyColumn { ... }
 * }
 * ```
 *
 * @param isLoading     When `true` the [skeleton] slot is visible; when `false`
 *                      [content] fades in over the dissolving skeleton.
 * @param skeleton      Composable shown while data is loading (typically a
 *                      [BrandSkeleton], [CardGridSkeleton], or [DetailHeaderSkeleton]).
 * @param modifier      Applied to the outer [AnimatedContent] container.
 * @param fadeDurationMs Duration of the cross-fade in milliseconds. Defaults to
 *                      [SKELETON_FADE_DURATION_MS] (200 ms). Ignored when
 *                      [reduceMotion] is `true`.
 * @param reduceMotion  When `true` the fade collapses to 0 ms (instant snap).
 *                      Read from [com.bizarreelectronics.crm.util.rememberReduceMotion].
 * @param content       The real screen content, composed only when [isLoading] is `false`.
 */
@Composable
fun SkeletonTransition(
    isLoading: Boolean,
    skeleton: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    fadeDurationMs: Int = SKELETON_FADE_DURATION_MS,
    reduceMotion: Boolean = false,
    content: @Composable () -> Unit,
) {
    val effectiveDuration = if (reduceMotion) 0 else fadeDurationMs
    AnimatedContent(
        targetState = isLoading,
        transitionSpec = {
            fadeIn(animationSpec = tween(durationMillis = effectiveDuration)) togetherWith
                fadeOut(animationSpec = tween(durationMillis = effectiveDuration))
        },
        label = "skeletonTransition",
        modifier = modifier,
    ) { loading ->
        if (loading) {
            skeleton()
        } else {
            content()
        }
    }
}

/**
 * §75.4 — Variant that also cross-fades between an [errorContent] slot and real
 * [content]. Handles the three-state loading/error/loaded pattern in one composable.
 *
 * The [targetState] is an integer key that encodes the screen phase:
 *   0 = loading, 1 = error, 2 = content ready
 *
 * Use [skeletonErrorTransitionKey] to convert the typical ViewModel boolean flags:
 * ```kotlin
 * SkeletonErrorTransition(
 *     targetState  = skeletonErrorTransitionKey(state.isLoading, state.error != null),
 *     skeleton     = { BrandSkeleton(rows = 6) },
 *     errorContent = { ErrorState(...) },
 * ) {
 *     LazyColumn { ... }
 * }
 * ```
 *
 * @param targetState   0 = loading, 1 = error, 2 = ready. Use [skeletonErrorTransitionKey].
 * @param skeleton      Composable rendered in state 0.
 * @param errorContent  Composable rendered in state 1.
 * @param modifier      Applied to the [AnimatedContent] container.
 * @param fadeDurationMs Cross-fade duration. Collapsed to 0 when [reduceMotion] is `true`.
 * @param reduceMotion  Reads system or in-app Reduce Motion setting.
 * @param content       Composable rendered in state 2 (real data ready).
 */
@Composable
fun SkeletonErrorTransition(
    targetState: Int,
    skeleton: @Composable () -> Unit,
    errorContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    fadeDurationMs: Int = SKELETON_FADE_DURATION_MS,
    reduceMotion: Boolean = false,
    content: @Composable () -> Unit,
) {
    val effectiveDuration = if (reduceMotion) 0 else fadeDurationMs
    AnimatedContent(
        targetState = targetState,
        transitionSpec = {
            fadeIn(animationSpec = tween(durationMillis = effectiveDuration)) togetherWith
                fadeOut(animationSpec = tween(durationMillis = effectiveDuration))
        },
        label = "skeletonErrorTransition",
        modifier = modifier,
    ) { state ->
        when (state) {
            SKELETON_STATE_LOADING -> skeleton()
            SKELETON_STATE_ERROR   -> errorContent()
            else                   -> content()
        }
    }
}

/**
 * §75.4 — Converts the typical ViewModel boolean flags into an integer [targetState]
 * for [SkeletonErrorTransition].
 *
 * Priority: loading > error > content-ready.
 *
 * @param isLoading `true` while the initial fetch is in-flight.
 * @param hasError  `true` when the last fetch ended with a non-null error.
 * @return          0 = loading, 1 = error, 2 = content ready.
 */
fun skeletonErrorTransitionKey(isLoading: Boolean, hasError: Boolean): Int = when {
    isLoading -> SKELETON_STATE_LOADING
    hasError  -> SKELETON_STATE_ERROR
    else      -> SKELETON_STATE_CONTENT
}

/** Default cross-fade duration for skeleton → content transitions (§75.4). */
const val SKELETON_FADE_DURATION_MS: Int = 200

/** [SkeletonErrorTransition] state key: initial data load in progress. */
const val SKELETON_STATE_LOADING: Int = 0

/** [SkeletonErrorTransition] state key: last fetch ended with an error. */
const val SKELETON_STATE_ERROR: Int = 1

/** [SkeletonErrorTransition] state key: data is ready to render. */
const val SKELETON_STATE_CONTENT: Int = 2
