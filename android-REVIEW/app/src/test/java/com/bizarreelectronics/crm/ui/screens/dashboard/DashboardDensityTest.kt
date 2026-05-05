package com.bizarreelectronics.crm.ui.screens.dashboard

import com.bizarreelectronics.crm.ui.theme.DashboardDensity
import com.bizarreelectronics.crm.ui.theme.DashboardDensity.Companion.toKey
import com.bizarreelectronics.crm.util.WindowMode
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §3.19 L613–L616 — Unit tests for [DashboardDensity] column computation,
 * spacing values, type scales, and pref key round-trip.
 *
 * These are pure JVM tests — no Android context required.
 */
class DashboardDensityTest {

    // -----------------------------------------------------------------------
    // columnsForWindowSize
    // -----------------------------------------------------------------------

    @Test
    fun `Comfortable phone yields 1 column`() {
        assertEquals(1, DashboardDensity.Comfortable.columnsForWindowSize(WindowMode.Phone))
    }

    @Test
    fun `Comfortable tablet yields 2 columns`() {
        assertEquals(2, DashboardDensity.Comfortable.columnsForWindowSize(WindowMode.Tablet))
    }

    @Test
    fun `Comfortable desktop yields 2 columns`() {
        assertEquals(2, DashboardDensity.Comfortable.columnsForWindowSize(WindowMode.Desktop))
    }

    @Test
    fun `Cozy phone yields 2 columns`() {
        assertEquals(2, DashboardDensity.Cozy.columnsForWindowSize(WindowMode.Phone))
    }

    @Test
    fun `Cozy tablet yields 3 columns`() {
        assertEquals(3, DashboardDensity.Cozy.columnsForWindowSize(WindowMode.Tablet))
    }

    @Test
    fun `Cozy desktop yields 3 columns`() {
        assertEquals(3, DashboardDensity.Cozy.columnsForWindowSize(WindowMode.Desktop))
    }

    @Test
    fun `Compact phone yields 3 columns`() {
        assertEquals(3, DashboardDensity.Compact.columnsForWindowSize(WindowMode.Phone))
    }

    @Test
    fun `Compact tablet yields 4 columns`() {
        assertEquals(4, DashboardDensity.Compact.columnsForWindowSize(WindowMode.Tablet))
    }

    @Test
    fun `Compact desktop yields 4 columns`() {
        assertEquals(4, DashboardDensity.Compact.columnsForWindowSize(WindowMode.Desktop))
    }

    // -----------------------------------------------------------------------
    // All window modes × all densities matrix (exhaustive)
    // -----------------------------------------------------------------------

    @Test
    fun `column matrix is correct for all density x window combinations`() {
        val expected = mapOf(
            Pair(DashboardDensity.Comfortable, WindowMode.Phone)    to 1,
            Pair(DashboardDensity.Comfortable, WindowMode.Tablet)   to 2,
            Pair(DashboardDensity.Comfortable, WindowMode.Desktop)  to 2,
            Pair(DashboardDensity.Cozy,        WindowMode.Phone)    to 2,
            Pair(DashboardDensity.Cozy,        WindowMode.Tablet)   to 3,
            Pair(DashboardDensity.Cozy,        WindowMode.Desktop)  to 3,
            Pair(DashboardDensity.Compact,     WindowMode.Phone)    to 3,
            Pair(DashboardDensity.Compact,     WindowMode.Tablet)   to 4,
            Pair(DashboardDensity.Compact,     WindowMode.Desktop)  to 4,
        )
        expected.forEach { (key, expectedColumns) ->
            val (density, window) = key
            assertEquals(
                "columnsForWindowSize($window) on $density",
                expectedColumns,
                density.columnsForWindowSize(window),
            )
        }
    }

    // -----------------------------------------------------------------------
    // baseSpacing
    // -----------------------------------------------------------------------

    @Test
    fun `Comfortable baseSpacing is 16dp`() {
        assertEquals(16f, DashboardDensity.Comfortable.baseSpacing.value, 0f)
    }

    @Test
    fun `Cozy baseSpacing is 12dp`() {
        assertEquals(12f, DashboardDensity.Cozy.baseSpacing.value, 0f)
    }

    @Test
    fun `Compact baseSpacing is 8dp`() {
        assertEquals(8f, DashboardDensity.Compact.baseSpacing.value, 0f)
    }

    // -----------------------------------------------------------------------
    // typeScale
    // -----------------------------------------------------------------------

    @Test
    fun `Comfortable typeScale is 1_00`() {
        assertEquals(1.00f, DashboardDensity.Comfortable.typeScale, 0.001f)
    }

    @Test
    fun `Cozy typeScale is 0_95`() {
        assertEquals(0.95f, DashboardDensity.Cozy.typeScale, 0.001f)
    }

    @Test
    fun `Compact typeScale is 0_90`() {
        assertEquals(0.90f, DashboardDensity.Compact.typeScale, 0.001f)
    }

    // -----------------------------------------------------------------------
    // fromKey / toKey round-trip
    // -----------------------------------------------------------------------

    @Test
    fun `fromKey comfortable round-trips`() {
        val density = DashboardDensity.fromKey("comfortable")
        assertEquals(DashboardDensity.Comfortable, density)
        assertEquals("comfortable", density.toKey())
    }

    @Test
    fun `fromKey cozy round-trips`() {
        val density = DashboardDensity.fromKey("cozy")
        assertEquals(DashboardDensity.Cozy, density)
        assertEquals("cozy", density.toKey())
    }

    @Test
    fun `fromKey compact round-trips`() {
        val density = DashboardDensity.fromKey("compact")
        assertEquals(DashboardDensity.Compact, density)
        assertEquals("compact", density.toKey())
    }

    @Test
    fun `fromKey unknown value falls back to Comfortable`() {
        assertEquals(DashboardDensity.Comfortable, DashboardDensity.fromKey("unknown"))
    }

    @Test
    fun `fromKey empty string falls back to Comfortable`() {
        assertEquals(DashboardDensity.Comfortable, DashboardDensity.fromKey(""))
    }

    // -----------------------------------------------------------------------
    // Ordering sanity: Comfortable > Cozy > Compact (spacing shrinks)
    // -----------------------------------------------------------------------

    @Test
    fun `spacing decreases from Comfortable to Compact`() {
        assert(DashboardDensity.Comfortable.baseSpacing > DashboardDensity.Cozy.baseSpacing)
        assert(DashboardDensity.Cozy.baseSpacing > DashboardDensity.Compact.baseSpacing)
    }

    @Test
    fun `typeScale decreases from Comfortable to Compact`() {
        assert(DashboardDensity.Comfortable.typeScale > DashboardDensity.Cozy.typeScale)
        assert(DashboardDensity.Cozy.typeScale > DashboardDensity.Compact.typeScale)
    }

    @Test
    fun `column count is non-decreasing from Comfortable to Compact`() {
        WindowMode.entries.forEach { window ->
            val comfortable = DashboardDensity.Comfortable.columnsForWindowSize(window)
            val cozy = DashboardDensity.Cozy.columnsForWindowSize(window)
            val compact = DashboardDensity.Compact.columnsForWindowSize(window)
            assert(cozy >= comfortable) { "Cozy ($cozy) should have >= columns than Comfortable ($comfortable) on $window" }
            assert(compact >= cozy) { "Compact ($compact) should have >= columns than Cozy ($cozy) on $window" }
        }
    }
}
