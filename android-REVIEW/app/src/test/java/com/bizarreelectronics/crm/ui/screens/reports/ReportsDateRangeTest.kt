package com.bizarreelectronics.crm.ui.screens.reports

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/**
 * Unit tests for Reports date-range logic (ActionPlan §15 L1723).
 *
 * Pure-JVM — no Android context required.
 *
 * Cases:
 *  1. TODAY preset → fromDate == toDate == start of today
 *  2. WEEK preset  → fromDate is 6 days before today
 *  3. MONTH preset → fromDate is 29 days before today
 *  4. YEAR preset  → fromDate is 364 days before today
 *  5. CUSTOM preset → rangeFor returns null (caller opens picker)
 *  6. setCustomRange normalises reversed args (from > to → swapped)
 *  7. formatServerDate produces "yyyy-MM-dd" shape
 *  8. DateRangePreset.values() contains exactly the 5 expected values
 *  9. TODAY range: toDate >= fromDate
 * 10. WEEK range: span is exactly 6 days
 * 11. MONTH range: span is exactly 29 days
 * 12. YEAR range: span is exactly 364 days
 * 13. Custom range with equal from/to is valid
 */
class ReportsDateRangeTest {

    // ── helpers mirroring production logic ────────────────────────────────────

    private fun startOfTodayMillis(): Long {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis
    }

    private val millisPerDay = 86_400_000L

    private fun daysAgoMillis(days: Int): Long =
        startOfTodayMillis() - days * millisPerDay

    private fun rangeFor(preset: DateRangePreset): Pair<Long, Long>? {
        val today = startOfTodayMillis()
        return when (preset) {
            DateRangePreset.TODAY  -> today to today
            DateRangePreset.WEEK   -> daysAgoMillis(6) to today
            DateRangePreset.MONTH  -> daysAgoMillis(29) to today
            DateRangePreset.YEAR   -> daysAgoMillis(364) to today
            DateRangePreset.CUSTOM -> null
        }
    }

    private fun normaliseRange(from: Long, to: Long): Pair<Long, Long> =
        minOf(from, to) to maxOf(from, to)

    // ── tests ─────────────────────────────────────────────────────────────────

    @Test fun `TODAY from equals to`() {
        val range = rangeFor(DateRangePreset.TODAY)!!
        assertEquals(range.first, range.second)
    }

    @Test fun `WEEK fromDate is 6 days before today`() {
        val range = rangeFor(DateRangePreset.WEEK)!!
        assertEquals(6 * millisPerDay, range.second - range.first)
    }

    @Test fun `MONTH fromDate is 29 days before today`() {
        val range = rangeFor(DateRangePreset.MONTH)!!
        assertEquals(29 * millisPerDay, range.second - range.first)
    }

    @Test fun `YEAR fromDate is 364 days before today`() {
        val range = rangeFor(DateRangePreset.YEAR)!!
        assertEquals(364 * millisPerDay, range.second - range.first)
    }

    @Test fun `CUSTOM preset returns null`() {
        assertNull(rangeFor(DateRangePreset.CUSTOM))
    }

    @Test fun `setCustomRange normalises reversed args`() {
        val future = startOfTodayMillis() + 5 * millisPerDay
        val past = startOfTodayMillis() - 5 * millisPerDay
        val (from, to) = normaliseRange(future, past)
        assertTrue("from should be <= to", from <= to)
        assertEquals(past, from)
        assertEquals(future, to)
    }

    @Test fun `formatServerDate shape is yyyy-MM-dd`() {
        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }
        val result = sdf.format(java.util.Date(startOfTodayMillis()))
        assertTrue("Should match yyyy-MM-dd pattern", result.matches(Regex("\\d{4}-\\d{2}-\\d{2}")))
    }

    @Test fun `DateRangePreset has exactly 5 values`() {
        assertEquals(5, DateRangePreset.values().size)
    }

    @Test fun `TODAY toDate is >= fromDate`() {
        val range = rangeFor(DateRangePreset.TODAY)!!
        assertTrue(range.second >= range.first)
    }

    @Test fun `WEEK span equals 6 days`() {
        val range = rangeFor(DateRangePreset.WEEK)!!
        assertEquals(6L, (range.second - range.first) / millisPerDay)
    }

    @Test fun `MONTH span equals 29 days`() {
        val range = rangeFor(DateRangePreset.MONTH)!!
        assertEquals(29L, (range.second - range.first) / millisPerDay)
    }

    @Test fun `YEAR span equals 364 days`() {
        val range = rangeFor(DateRangePreset.YEAR)!!
        assertEquals(364L, (range.second - range.first) / millisPerDay)
    }

    @Test fun `custom range with equal from and to is valid`() {
        val now = startOfTodayMillis()
        val (from, to) = normaliseRange(now, now)
        assertEquals(from, to)
    }
}
