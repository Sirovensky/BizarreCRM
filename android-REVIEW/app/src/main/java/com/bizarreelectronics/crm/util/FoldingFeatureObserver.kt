package com.bizarreelectronics.crm.util

import android.app.Activity
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * FoldingFeatureObserver — §22 L2280-L2283 (plan:L2280)
 *
 * Wraps [WindowInfoTracker] to expose the current foldable device posture as a
 * [StateFlow] of [FoldablePosture]. Screens that benefit from split-layout
 * optimisations should collect this flow and adapt their UI accordingly.
 *
 * ## Postures detected
 * | Posture | FoldingFeature state | Orientation |
 * |---------|----------------------|-------------|
 * | [FoldablePosture.Flat]     | FLAT | any   | Normal fully-open tablet |
 * | [FoldablePosture.Tabletop] | HALF_OPENED | HORIZONTAL | Bottom half resting on surface |
 * | [FoldablePosture.Book]     | HALF_OPENED | VERTICAL   | Held like a book |
 * | [FoldablePosture.Unknown]  | No FoldingFeature present | — |
 *
 * ## Where to consume
 * - **SMS thread** (SmsConversationScreen): Tabletop → keyboard + input at bottom,
 *   conversation scroll at top. Book → messages left, compose right.
 * - **POS / Checkout**: Tabletop → customer-facing display top half, cashier controls bottom.
 * - **Ticket detail**: Book → ticket info left pane, photo/signature right pane.
 *
 * ## Usage
 * ```kotlin
 * // In an Activity or Composable that has access to Activity:
 * val observer = FoldingFeatureObserver(activity, lifecycleScope)
 * val posture by observer.posture.collectAsState()
 *
 * when (posture) {
 *     FoldablePosture.Tabletop -> TabletopLayout()
 *     FoldablePosture.Book     -> BookLayout()
 *     else                     -> DefaultLayout()
 * }
 * ```
 *
 * @param activity The host Activity used by [WindowInfoTracker.getOrCreate].
 * @param scope    CoroutineScope for the collection job (tie to lifecycle).
 */
class FoldingFeatureObserver(
    activity: Activity,
    scope: CoroutineScope,
) {
    private val _posture = MutableStateFlow<FoldablePosture>(FoldablePosture.Unknown)

    /** Current foldable posture. Emits on every window layout change. */
    val posture: StateFlow<FoldablePosture> = _posture.asStateFlow()

    init {
        WindowInfoTracker
            .getOrCreate(activity)
            .windowLayoutInfo(activity)
            .onEach { layoutInfo ->
                val fold = layoutInfo.displayFeatures
                    .filterIsInstance<FoldingFeature>()
                    .firstOrNull()

                _posture.value = when {
                    fold == null -> FoldablePosture.Flat

                    fold.state == FoldingFeature.State.HALF_OPENED &&
                        fold.orientation == FoldingFeature.Orientation.HORIZONTAL ->
                        FoldablePosture.Tabletop

                    fold.state == FoldingFeature.State.HALF_OPENED &&
                        fold.orientation == FoldingFeature.Orientation.VERTICAL ->
                        FoldablePosture.Book

                    fold.state == FoldingFeature.State.FLAT ->
                        FoldablePosture.Flat

                    else -> FoldablePosture.Unknown
                }
            }
            .launchIn(scope)
    }
}

/**
 * Device posture for foldable form factors.
 *
 * [Unknown] is the default before the first [WindowInfoTracker] emission —
 * treat it like [Flat] for layout purposes.
 */
sealed interface FoldablePosture {
    /** Device is fully open / non-foldable. Default layout applies. */
    data object Flat : FoldablePosture

    /**
     * Device is half-open with a horizontal fold (hinge at bottom) — the
     * "laptop" or "clamshell" posture. Content at top, controls at bottom.
     */
    data object Tabletop : FoldablePosture

    /**
     * Device is half-open with a vertical fold (hinge on the side) — held
     * like an open book. Content split left / right across the hinge.
     */
    data object Book : FoldablePosture

    /** Posture not yet determined (pre-first-emission). */
    data object Unknown : FoldablePosture
}
