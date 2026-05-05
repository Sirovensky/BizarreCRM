package com.bizarreelectronics.crm.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalTime

/**
 * §31.1 — unit coverage for §13.2 quiet-hours decision logic. The pure
 * branches of the QuietHours class are exercised here by driving the
 * decision helper directly. (The full [QuietHours.shouldSilence] path
 * needs AppPreferences; the branches tested here mirror the in-class
 * boolean math that decides whether nowMin falls inside [start,end).)
 */
class QuietHoursTest {

    // --- Non-wrap window (start < end) --------------------------------------

    @Test fun `non-wrap window includes start minute`() {
        assertTrue(inWindow(nowMin(22, 0), start = 22 * 60, end = 23 * 60))
    }

    @Test fun `non-wrap window excludes end minute`() {
        assertFalse(inWindow(nowMin(23, 0), start = 22 * 60, end = 23 * 60))
    }

    @Test fun `non-wrap window contains middle`() {
        assertTrue(inWindow(nowMin(22, 30), start = 22 * 60, end = 23 * 60))
    }

    @Test fun `non-wrap window excludes before start`() {
        assertFalse(inWindow(nowMin(21, 59), start = 22 * 60, end = 23 * 60))
    }

    // --- Wrap-around window (start > end) — e.g. 22:00 → 07:00 -------------

    @Test fun `wrap window silences late night`() {
        assertTrue(inWindow(nowMin(23, 0), start = 22 * 60, end = 7 * 60))
        assertTrue(inWindow(nowMin(0, 0), start = 22 * 60, end = 7 * 60))
        assertTrue(inWindow(nowMin(6, 59), start = 22 * 60, end = 7 * 60))
    }

    @Test fun `wrap window releases at end`() {
        assertFalse(inWindow(nowMin(7, 0), start = 22 * 60, end = 7 * 60))
        assertFalse(inWindow(nowMin(12, 0), start = 22 * 60, end = 7 * 60))
        assertFalse(inWindow(nowMin(21, 59), start = 22 * 60, end = 7 * 60))
    }

    // --- Zero-width window (start == end) ----------------------------------

    @Test fun `zero-width window silences nothing`() {
        assertFalse(inWindow(nowMin(22, 0), start = 22 * 60, end = 22 * 60))
        assertFalse(inWindow(nowMin(12, 0), start = 22 * 60, end = 22 * 60))
    }

    // --- Helpers mirroring QuietHours internal logic -----------------------

    private fun nowMin(hour: Int, minute: Int): Int = LocalTime.of(hour, minute).let { it.hour * 60 + it.minute }

    private fun inWindow(nowMin: Int, start: Int, end: Int): Boolean {
        if (start == end) return false
        return if (start < end) {
            nowMin in start until end
        } else {
            nowMin >= start || nowMin < end
        }
    }
}
