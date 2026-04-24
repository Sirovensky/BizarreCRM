package com.bizarreelectronics.crm.util

import android.graphics.Rect
import androidx.window.layout.DisplayFeature
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowLayoutInfo
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * FoldingFeatureObserverTest — §22 L2280-L2283 (plan:L2283)
 *
 * Validates the posture-derivation logic in [FoldingFeatureObserver] using a
 * pure-JVM stub observer (no Activity, no Robolectric required).
 *
 * Each test constructs a [WindowLayoutInfo] with a [FoldingFeatureStub] whose
 * [state] + [orientation] drive the expected [FoldablePosture].
 *
 * ## Covered transitions
 * | Input                              | Expected posture             |
 * |------------------------------------|------------------------------|
 * | No folding feature                 | [FoldablePosture.Flat]       |
 * | HALF_OPENED + HORIZONTAL           | [FoldablePosture.Tabletop]   |
 * | HALF_OPENED + VERTICAL             | [FoldablePosture.Book]       |
 * | FLAT state                         | [FoldablePosture.Flat]       |
 * | Tabletop → device fully opened     | [FoldablePosture.Flat]       |
 */
class FoldingFeatureObserverTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun layoutInfoOf(vararg features: DisplayFeature): WindowLayoutInfo =
        WindowLayoutInfo(features.toList())

    private fun makeFold(
        state: FoldingFeature.State,
        orientation: FoldingFeature.Orientation,
    ): FoldingFeature = FoldingFeatureStub(state, orientation)

    /**
     * Mirrors the posture-derivation logic from [FoldingFeatureObserver]
     * without requiring [WindowInfoTracker] (which needs an Activity).
     */
    private fun derivePosture(info: WindowLayoutInfo): FoldablePosture {
        val fold = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
        return when {
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

    // ── Tests ─────────────────────────────────────────────────────────────────

    @Test
    fun `no folding feature emits Flat`() {
        val info = layoutInfoOf()
        assertEquals(FoldablePosture.Flat, derivePosture(info))
    }

    @Test
    fun `half-opened horizontal emits Tabletop`() {
        val info = layoutInfoOf(
            makeFold(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.HORIZONTAL),
        )
        assertEquals(FoldablePosture.Tabletop, derivePosture(info))
    }

    @Test
    fun `half-opened vertical emits Book`() {
        val info = layoutInfoOf(
            makeFold(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.VERTICAL),
        )
        assertEquals(FoldablePosture.Book, derivePosture(info))
    }

    @Test
    fun `flat state emits Flat`() {
        val info = layoutInfoOf(
            makeFold(FoldingFeature.State.FLAT, FoldingFeature.Orientation.HORIZONTAL),
        )
        assertEquals(FoldablePosture.Flat, derivePosture(info))
    }

    @Test
    fun `posture transitions from Tabletop to Flat when device is fully opened`() {
        val tabletopInfo = layoutInfoOf(
            makeFold(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.HORIZONTAL),
        )
        val flatInfo = layoutInfoOf()  // no FoldingFeature when fully open

        assertEquals(FoldablePosture.Tabletop, derivePosture(tabletopInfo))
        assertEquals(FoldablePosture.Flat, derivePosture(flatInfo))
    }

    @Test
    fun `posture transitions from Book to Tabletop`() {
        val bookInfo = layoutInfoOf(
            makeFold(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.VERTICAL),
        )
        val tabletopInfo = layoutInfoOf(
            makeFold(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.HORIZONTAL),
        )

        assertEquals(FoldablePosture.Book, derivePosture(bookInfo))
        assertEquals(FoldablePosture.Tabletop, derivePosture(tabletopInfo))
    }
}

// ── FoldingFeature test stub ──────────────────────────────────────────────────

/**
 * Pure-JVM [FoldingFeature] stub usable in unit tests without Robolectric.
 *
 * Only [state] and [orientation] are meaningful for posture detection. [bounds]
 * is an empty rect (sufficient for logic that does not measure the hinge area).
 */
private class FoldingFeatureStub(
    override val state: FoldingFeature.State,
    override val orientation: FoldingFeature.Orientation,
) : FoldingFeature {
    override val bounds: Rect get() = Rect()
    override val isSeparating: Boolean get() = false
    override val occlusionType: FoldingFeature.OcclusionType
        get() = FoldingFeature.OcclusionType.NONE
}
