package com.bizarreelectronics.crm.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM unit tests for the signature-pad helpers (ActionPlan §4).
 *
 * Only [isSignatureValid], [SignaturePoint], and [SignatureStroke] are tested
 * here — all three are framework-free and run on the JVM without Robolectric.
 *
 * [renderSignatureBitmap] requires `android.graphics.Bitmap` which is not
 * available in the JVM unit-test environment; it is excluded from this suite
 * and should be covered by an instrumented (on-device) test if needed.
 */
class SignaturePadTest {

    // -----------------------------------------------------------------------
    // isSignatureValid — empty / trivial inputs → false
    // -----------------------------------------------------------------------

    @Test
    fun `isSignatureValid returns false for empty strokes list`() {
        assertFalse(isSignatureValid(emptyList()))
    }

    @Test
    fun `isSignatureValid returns false for single stroke with one point`() {
        val strokes = listOf(SignatureStroke(listOf(SignaturePoint(10f, 20f))))
        assertFalse(isSignatureValid(strokes))
    }

    @Test
    fun `isSignatureValid returns false for single stroke with two points and tiny path`() {
        // Two adjacent points produce a path < DEFAULT min (50px)
        val strokes = listOf(
            SignatureStroke(
                listOf(
                    SignaturePoint(0f, 0f),
                    SignaturePoint(1f, 1f),   // ~1.4px total path length
                ),
            ),
        )
        assertFalse(isSignatureValid(strokes, minTotalPathPx = 50f))
    }

    @Test
    fun `isSignatureValid returns false for list of strokes each with one point`() {
        val strokes = listOf(
            SignatureStroke(listOf(SignaturePoint(0f, 0f))),
            SignatureStroke(listOf(SignaturePoint(5f, 5f))),
        )
        assertFalse(isSignatureValid(strokes))
    }

    // -----------------------------------------------------------------------
    // isSignatureValid — 3+ points in a stroke → true (condition 1)
    // -----------------------------------------------------------------------

    @Test
    fun `isSignatureValid returns true for stroke with exactly 3 points`() {
        val strokes = listOf(
            SignatureStroke(
                listOf(
                    SignaturePoint(0f, 0f),
                    SignaturePoint(10f, 5f),
                    SignaturePoint(20f, 0f),
                ),
            ),
        )
        assertTrue(isSignatureValid(strokes))
    }

    @Test
    fun `isSignatureValid returns true for stroke with 10 points spread across canvas`() {
        val points = (0 until 10).map { i -> SignaturePoint(i * 30f, if (i % 2 == 0) 40f else 80f) }
        val strokes = listOf(SignatureStroke(points))
        assertTrue(isSignatureValid(strokes))
    }

    @Test
    fun `isSignatureValid returns true when second of two strokes has 3 plus points`() {
        val strokes = listOf(
            SignatureStroke(listOf(SignaturePoint(0f, 0f))),   // 1 point — not enough alone
            SignatureStroke(
                listOf(
                    SignaturePoint(50f, 50f),
                    SignaturePoint(60f, 60f),
                    SignaturePoint(70f, 50f),
                ),
            ),
        )
        assertTrue(isSignatureValid(strokes))
    }

    // -----------------------------------------------------------------------
    // isSignatureValid — path-length condition (condition 2)
    // -----------------------------------------------------------------------

    @Test
    fun `isSignatureValid returns true when total path length exceeds minTotalPathPx`() {
        // Two points 100px apart → path length = 100, which exceeds default 50
        val strokes = listOf(
            SignatureStroke(
                listOf(
                    SignaturePoint(0f, 0f),
                    SignaturePoint(100f, 0f),
                ),
            ),
        )
        assertTrue(isSignatureValid(strokes, minTotalPathPx = 50f))
    }

    @Test
    fun `isSignatureValid returns false when total path length is exactly at threshold`() {
        // Two points 50px apart → path length = 50, NOT exceeding minTotalPathPx = 50
        val strokes = listOf(
            SignatureStroke(
                listOf(
                    SignaturePoint(0f, 0f),
                    SignaturePoint(50f, 0f),
                ),
            ),
        )
        // Exactly at threshold is false because isSignatureValid uses strict ">"
        assertFalse(isSignatureValid(strokes, minTotalPathPx = 50f))
    }

    @Test
    fun `isSignatureValid aggregates path length across multiple strokes`() {
        // Each stroke has 2 points 30px apart → combined = 60 > default 50
        val strokes = listOf(
            SignatureStroke(
                listOf(SignaturePoint(0f, 0f), SignaturePoint(30f, 0f)),
            ),
            SignatureStroke(
                listOf(SignaturePoint(0f, 50f), SignaturePoint(30f, 50f)),
            ),
        )
        assertTrue(isSignatureValid(strokes, minTotalPathPx = 50f))
    }

    @Test
    fun `isSignatureValid with custom minTotalPathPx zero accepts any non-empty stroke`() {
        val strokes = listOf(
            SignatureStroke(
                listOf(
                    SignaturePoint(0f, 0f),
                    SignaturePoint(0.1f, 0.1f),
                ),
            ),
        )
        // minTotalPathPx = 0 → even a tiny path exceeds 0
        assertTrue(isSignatureValid(strokes, minTotalPathPx = 0f))
    }

    // -----------------------------------------------------------------------
    // SignaturePoint — data class equality and copy
    // -----------------------------------------------------------------------

    @Test
    fun `SignaturePoint equality uses value semantics`() {
        val p1 = SignaturePoint(1.5f, 2.5f)
        val p2 = SignaturePoint(1.5f, 2.5f)
        assertEquals(p1, p2)
    }

    @Test
    fun `SignaturePoint inequality for different coordinates`() {
        val p1 = SignaturePoint(0f, 0f)
        val p2 = SignaturePoint(0f, 1f)
        assertTrue(p1 != p2)
    }

    @Test
    fun `SignaturePoint copy produces a new instance with changed field`() {
        val original = SignaturePoint(3f, 7f)
        val copied = original.copy(y = 99f)
        assertNotSame(original, copied)
        assertEquals(3f, copied.x)
        assertEquals(99f, copied.y)
        // original is unchanged
        assertEquals(7f, original.y)
    }

    // -----------------------------------------------------------------------
    // SignatureStroke — data class equality and copy
    // -----------------------------------------------------------------------

    @Test
    fun `SignatureStroke equality uses structural comparison of points`() {
        val pts = listOf(SignaturePoint(1f, 2f), SignaturePoint(3f, 4f))
        val s1 = SignatureStroke(pts)
        val s2 = SignatureStroke(listOf(SignaturePoint(1f, 2f), SignaturePoint(3f, 4f)))
        assertEquals(s1, s2)
    }

    @Test
    fun `SignatureStroke copy with replaced points does not mutate original`() {
        val original = SignatureStroke(listOf(SignaturePoint(0f, 0f)))
        val newPoints = listOf(SignaturePoint(10f, 10f), SignaturePoint(20f, 20f))
        val copied = original.copy(points = newPoints)
        assertNotSame(original, copied)
        // Original still has one point
        assertEquals(1, original.points.size)
        assertEquals(2, copied.points.size)
    }

    @Test
    fun `SignatureStroke hashCode consistent with equals`() {
        val s1 = SignatureStroke(listOf(SignaturePoint(5f, 5f)))
        val s2 = SignatureStroke(listOf(SignaturePoint(5f, 5f)))
        assertEquals(s1, s2)
        assertEquals(s1.hashCode(), s2.hashCode())
    }

    // -----------------------------------------------------------------------
    // isSignatureValid — toString not null (smoke)
    // -----------------------------------------------------------------------

    @Test
    fun `SignaturePoint toString is not null or empty`() {
        val p = SignaturePoint(1f, 2f)
        assertNotNull(p.toString())
        assertTrue(p.toString().isNotEmpty())
    }

    @Test
    fun `SignatureStroke toString is not null or empty`() {
        val s = SignatureStroke(listOf(SignaturePoint(1f, 2f)))
        assertNotNull(s.toString())
        assertTrue(s.toString().isNotEmpty())
    }
}
