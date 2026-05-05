package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — unit coverage for DateFormatter's JDK-only string parsers.
 *
 * The Long-based (`formatAbsolute(timestampMs)`) and
 * relative (`formatRelative(timestampMs)`) overloads depend on
 * `android.text.format.DateUtils`, which pulls Android framework — those
 * paths stay out of this JVM unit test and will be exercised under
 * Robolectric in §31.2. The ISO-string overloads are pure `java.time`
 * so they run here without any framework stubs.
 */
class DateFormatterTest {

    // --- formatDate(iso) ----------------------------------------------------

    @Test fun `formatDate renders ISO date-time`() {
        assertEquals("Apr 16, 2026", DateFormatter.formatDate("2026-04-16 21:17:57"))
    }

    @Test fun `formatDate handles T-separated ISO`() {
        assertEquals("Apr 4, 2026", DateFormatter.formatDate("2026-04-04T17:30:00"))
    }

    @Test fun `formatDate falls back to date-only string`() {
        assertEquals("Apr 16, 2026", DateFormatter.formatDate("2026-04-16"))
    }

    @Test fun `formatDate returns empty for null or blank`() {
        assertEquals("", DateFormatter.formatDate(null))
        assertEquals("", DateFormatter.formatDate(""))
        assertEquals("", DateFormatter.formatDate("   "))
    }

    @Test fun `formatDate returns input unchanged on unparseable string`() {
        assertEquals("not-a-date", DateFormatter.formatDate("not-a-date"))
    }

    // --- formatAbsolute(iso) ------------------------------------------------

    @Test fun `formatAbsolute renders canonical April 16, 2026 shape`() {
        assertEquals("April 16, 2026", DateFormatter.formatAbsolute("2026-04-16 21:17:57"))
    }

    @Test fun `formatAbsolute handles T-separated ISO`() {
        assertEquals("April 4, 2026", DateFormatter.formatAbsolute("2026-04-04T17:30:00"))
    }

    @Test fun `formatAbsolute returns empty for null or blank`() {
        assertEquals("", DateFormatter.formatAbsolute(null as String?))
        assertEquals("", DateFormatter.formatAbsolute(""))
    }

    // --- formatDateTime(iso) ------------------------------------------------

    @Test fun `formatDateTime renders month + day + time`() {
        val out = DateFormatter.formatDateTime("2026-04-16 21:17:57")
        // Locale default puts AM/PM around; lock on the month + day prefix.
        assertTrue("expected 'Apr 16, ' prefix, got '$out'", out.startsWith("Apr 16, "))
    }

    @Test fun `formatDateTime returns empty for null or blank`() {
        assertEquals("", DateFormatter.formatDateTime(null))
        assertEquals("", DateFormatter.formatDateTime(""))
    }
}
