package com.bizarreelectronics.crm.ui.components

import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.flow.collect

/**
 * CompositionLocal that exposes the current predictive-back swipe progress to any child
 * composable. Value is `0f` when no gesture is in progress and advances toward `1f` as
 * the user completes the swipe. Reads `0f` by default when there is no
 * [PredictiveBackScaffold] ancestor in the tree (safe default — no animation).
 */
val LocalBackProgress = compositionLocalOf { 0f }

/**
 * Drop-in replacement for `BackHandler` that additionally exposes a `progress: 0f..1f`
 * channel during the system back gesture, enabling custom shrink/slide animations to
 * follow the user's swipe in real time.
 *
 * ### How it works
 * `PredictiveBackHandler` (androidx.activity 1.8+) wraps the new
 * `OnBackPressedCallback` predictive-back API introduced in Android 14 (API 34). On
 * older OS versions the handler falls back to the legacy `onBackPressed` path
 * transparently — `progress` stays at `0f` for the whole gesture in that case.
 *
 * The wrapper feeds live progress values into [LocalBackProgress] so child composables
 * can read them via `val progress = LocalBackProgress.current` without any additional
 * plumbing. When the gesture commits, [onBack] is called exactly once.
 *
 * ### Usage
 * ```kotlin
 * PredictiveBackScaffold(
 *     enabled = hasUnsavedChanges,
 *     onBack = { navController.popBackStack() },
 * ) { progress ->
 *     // progress drives any custom exit animation you want here or in children
 *     Box(modifier = Modifier.graphicsLayer { scaleX = 1f - progress * 0.05f })
 * }
 * ```
 *
 * ### Constraints
 * - Do not nest two [PredictiveBackScaffold] wrappers for the same gesture; only the
 *   innermost enabled handler intercepts the event.
 * - [onBack] is responsible for the actual navigation action. The scaffold does **not**
 *   pop the back stack itself.
 *
 * @param enabled  Whether this handler should intercept the back gesture. Mirrors the
 *                 semantics of `BackHandler(enabled)`.
 * @param onBack   Called when the back gesture completes. Perform navigation here.
 * @param content  Composable slot that receives the live swipe [progress] (`0f..1f`).
 *                 Also available to deeper descendants via [LocalBackProgress].
 */
@Composable
fun PredictiveBackScaffold(
    enabled: Boolean = true,
    onBack: () -> Unit,
    content: @Composable (progress: Float) -> Unit,
) {
    var backProgress by remember { mutableFloatStateOf(0f) }

    PredictiveBackHandler(enabled = enabled) { events ->
        try {
            events.collect { backEvent ->
                backProgress = backEvent.progress
            }
            // Flow completed normally — gesture was committed.
            onBack()
        } finally {
            // Reset on cancel (user reversed the swipe) or after commit.
            backProgress = 0f
        }
    }

    CompositionLocalProvider(LocalBackProgress provides backProgress) {
        content(backProgress)
    }
}
