package com.bizarreelectronics.crm.ui.screens.dashboard

import com.bizarreelectronics.crm.ui.screens.dashboard.components.DashboardDatePreset
import com.bizarreelectronics.crm.ui.screens.dashboard.components.toDateRange
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/**
 * §3 L488–L497 — pure-logic unit tests for [DashboardDatePreset.toDateRange].
 *
 * All tests inject a fixed [today] (2026-04-23) so results are deterministic
 * regardless of when the CI runs.  No Robolectric / Android framework needed.
 */
class DateRangeSelectorLogicTest {

    private val today: LocalDate = LocalDate.of(2026, 4, 23)

    // ---------------------------------------------------------------------------
    // TODAY
    // ---------------------------------------------------------------------------

    @Test fun `today preset maps from and to to today`() {
        val range = DashboardDatePreset.TODAY.toDateRange(today)
        assertEquals(today, range.from)
        assertEquals(today, range.to)
    }

    @Test fun `today preset label is Today`() {
        assertEquals("Today", DashboardDatePreset.TODAY.toDateRange(today).label)
    }

    // ---------------------------------------------------------------------------
    // YESTERDAY
    // ---------------------------------------------------------------------------

    @Test fun `yesterday preset maps both bounds to yesterday`() {
        val range = DashboardDatePreset.YESTERDAY.toDateRange(today)
        val expected = today.minusDays(1)
        assertEquals(expected, range.from)
        assertEquals(expected, range.to)
    }

    @Test fun `yesterday label is Yesterday`() {
        assertEquals("Yesterday", DashboardDatePreset.YESTERDAY.toDateRange(today).label)
    }

    // ---------------------------------------------------------------------------
    // DAYS_7
    // ---------------------------------------------------------------------------

    @Test fun `7-day preset spans exactly 7 days inclusive`() {
        val range = DashboardDatePreset.DAYS_7.toDateRange(today)
        assertEquals(today.minusDays(6), range.from)
        assertEquals(today, range.to)
    }

    @Test fun `7-day preset contains exactly 7 days`() {
        val range = DashboardDatePreset.DAYS_7.toDateRange(today)
        val dayCount = java.time.temporal.ChronoUnit.DAYS.between(range.from, range.to) + 1
        assertEquals(7L, dayCount)
    }

    // ---------------------------------------------------------------------------
    // DAYS_30
    // ---------------------------------------------------------------------------

    @Test fun `30-day preset spans exactly 30 days inclusive`() {
        val range = DashboardDatePreset.DAYS_30.toDateRange(today)
        assertEquals(today.minusDays(29), range.from)
        assertEquals(today, range.to)
    }

    @Test fun `30-day preset contains exactly 30 days`() {
        val range = DashboardDatePreset.DAYS_30.toDateRange(today)
        val dayCount = java.time.temporal.ChronoUnit.DAYS.between(range.from, range.to) + 1
        assertEquals(30L, dayCount)
    }

    // ---------------------------------------------------------------------------
    // MONTH_TO_DATE
    // ---------------------------------------------------------------------------

    @Test fun `month-to-date from is first day of current month`() {
        val range = DashboardDatePreset.MONTH_TO_DATE.toDateRange(today)
        val firstOfMonth = YearMonth.from(today).atDay(1)
        assertEquals(firstOfMonth, range.from)
    }

    @Test fun `month-to-date to is today`() {
        val range = DashboardDatePreset.MONTH_TO_DATE.toDateRange(today)
        assertEquals(today, range.to)
    }

    @Test fun `month-to-date first-of-month edge case when today is 1st`() {
        val firstOfMonth = LocalDate.of(2026, 4, 1)
        val range = DashboardDatePreset.MONTH_TO_DATE.toDateRange(firstOfMonth)
        assertEquals(firstOfMonth, range.from)
        assertEquals(firstOfMonth, range.to)
    }

    @Test fun `month-to-date spans into correct month for January`() {
        val jan15 = LocalDate.of(2026, 1, 15)
        val range = DashboardDatePreset.MONTH_TO_DATE.toDateRange(jan15)
        assertEquals(LocalDate.of(2026, 1, 1), range.from)
        assertEquals(jan15, range.to)
    }

    // ---------------------------------------------------------------------------
    // CUSTOM (fallback — picker result handled in UI layer)
    // ---------------------------------------------------------------------------

    @Test fun `custom preset fallback is today to today`() {
        val range = DashboardDatePreset.CUSTOM.toDateRange(today)
        assertEquals(today, range.from)
        assertEquals(today, range.to)
    }

    // ---------------------------------------------------------------------------
    // Ordering invariant — from never exceeds to for any preset
    // ---------------------------------------------------------------------------

    @Test fun `all presets produce from not after to`() {
        DashboardDatePreset.entries.forEach { preset ->
            val range = preset.toDateRange(today)
            assert(!range.from.isAfter(range.to)) {
                "Preset $preset: from=${range.from} is after to=${range.to}"
            }
        }
    }
}
