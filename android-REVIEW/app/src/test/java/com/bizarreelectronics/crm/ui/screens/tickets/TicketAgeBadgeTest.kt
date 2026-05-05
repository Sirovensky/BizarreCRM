package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.ui.screens.tickets.components.AgeTier
import com.bizarreelectronics.crm.ui.screens.tickets.components.DueTier
import com.bizarreelectronics.crm.ui.screens.tickets.components.ageTierForDays
import com.bizarreelectronics.crm.ui.screens.tickets.components.dueTierFor
import com.bizarreelectronics.crm.ui.screens.tickets.components.parseLocalDate
import com.bizarreelectronics.crm.ui.screens.tickets.components.ticketAgeDays
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * Unit tests for [TicketAgeBadge] threshold logic — [ageTierForDays] and [dueTierFor].
 *
 * All tests are pure JVM — no Android context needed.
 * Boundary values per spec:
 *   Age:     gray <3d / yellow 3-7d / amber 7-14d / red >14d
 *   Due:     red overdue / amber today / yellow ≤2d / gray later
 */
class TicketAgeBadgeTest {

    // -----------------------------------------------------------------------
    // ageTierForDays — age boundary tests
    // -----------------------------------------------------------------------

    @Test
    fun `age tier is gray when days is 0`() {
        assertEquals(AgeTier.Gray, ageTierForDays(0L))
    }

    @Test
    fun `age tier is gray when days is 1`() {
        assertEquals(AgeTier.Gray, ageTierForDays(1L))
    }

    @Test
    fun `age tier is gray when days is 2`() {
        assertEquals(AgeTier.Gray, ageTierForDays(2L))
    }

    @Test
    fun `age tier is yellow when days is exactly 3`() {
        assertEquals(AgeTier.Yellow, ageTierForDays(3L))
    }

    @Test
    fun `age tier is yellow when days is 5`() {
        assertEquals(AgeTier.Yellow, ageTierForDays(5L))
    }

    @Test
    fun `age tier is yellow when days is 6`() {
        assertEquals(AgeTier.Yellow, ageTierForDays(6L))
    }

    @Test
    fun `age tier is amber when days is exactly 7`() {
        assertEquals(AgeTier.Amber, ageTierForDays(7L))
    }

    @Test
    fun `age tier is amber when days is 10`() {
        assertEquals(AgeTier.Amber, ageTierForDays(10L))
    }

    @Test
    fun `age tier is amber when days is exactly 14`() {
        assertEquals(AgeTier.Amber, ageTierForDays(14L))
    }

    @Test
    fun `age tier is red when days is exactly 15`() {
        assertEquals(AgeTier.Red, ageTierForDays(15L))
    }

    @Test
    fun `age tier is red when days is 30`() {
        assertEquals(AgeTier.Red, ageTierForDays(30L))
    }

    @Test
    fun `age tier is red when days is 365`() {
        assertEquals(AgeTier.Red, ageTierForDays(365L))
    }

    // -----------------------------------------------------------------------
    // dueTierFor — due-date boundary tests
    // -----------------------------------------------------------------------

    private val today = LocalDate.of(2026, 4, 23) // fixed reference date

    @Test
    fun `due tier is red when due date is yesterday (overdue)`() {
        val yesterday = today.minusDays(1).toString()
        assertEquals(DueTier.Red, dueTierFor(yesterday, today))
    }

    @Test
    fun `due tier is red when due date is 5 days ago`() {
        val fiveDaysAgo = today.minusDays(5).toString()
        assertEquals(DueTier.Red, dueTierFor(fiveDaysAgo, today))
    }

    @Test
    fun `due tier is amber when due date is today`() {
        val todayStr = today.toString()
        assertEquals(DueTier.Amber, dueTierFor(todayStr, today))
    }

    @Test
    fun `due tier is yellow when due date is tomorrow (1 day)`() {
        val tomorrow = today.plusDays(1).toString()
        assertEquals(DueTier.Yellow, dueTierFor(tomorrow, today))
    }

    @Test
    fun `due tier is yellow when due date is exactly 2 days away`() {
        val twoDays = today.plusDays(2).toString()
        assertEquals(DueTier.Yellow, dueTierFor(twoDays, today))
    }

    @Test
    fun `due tier is gray when due date is 3 days away`() {
        val threeDays = today.plusDays(3).toString()
        assertEquals(DueTier.Gray, dueTierFor(threeDays, today))
    }

    @Test
    fun `due tier is gray when due date is 7 days away`() {
        val sevenDays = today.plusDays(7).toString()
        assertEquals(DueTier.Gray, dueTierFor(sevenDays, today))
    }

    // -----------------------------------------------------------------------
    // ticketAgeDays — parsing boundary checks
    // -----------------------------------------------------------------------

    @Test
    fun `ticketAgeDays returns 0 for today ISO date`() {
        val ageDays = ticketAgeDays(today.toString(), today)
        assertEquals(0L, ageDays)
    }

    @Test
    fun `ticketAgeDays returns 7 for ISO date 7 days ago`() {
        val createdAt = today.minusDays(7).toString()
        assertEquals(7L, ticketAgeDays(createdAt, today))
    }

    @Test
    fun `ticketAgeDays returns 14 for ISO datetime 14 days ago`() {
        val createdAt = "${today.minusDays(14)} 10:30:00"
        assertEquals(14L, ticketAgeDays(createdAt, today))
    }

    @Test
    fun `ticketAgeDays returns null for unparseable string`() {
        assertNull(ticketAgeDays("not-a-date", today))
    }

    @Test
    fun `ticketAgeDays returns 0 minimum when date is in the future`() {
        val futureDate = today.plusDays(5).toString()
        assertEquals(0L, ticketAgeDays(futureDate, today))
    }

    // -----------------------------------------------------------------------
    // parseLocalDate — format coverage
    // -----------------------------------------------------------------------

    @Test
    fun `parseLocalDate handles ISO local date`() {
        val date = parseLocalDate("2026-04-23")
        assertEquals(LocalDate.of(2026, 4, 23), date)
    }

    @Test
    fun `parseLocalDate handles space-separated datetime`() {
        val date = parseLocalDate("2026-04-23 14:30:00")
        assertEquals(LocalDate.of(2026, 4, 23), date)
    }

    @Test
    fun `parseLocalDate handles T-separated datetime`() {
        val date = parseLocalDate("2026-04-23T14:30:00")
        assertEquals(LocalDate.of(2026, 4, 23), date)
    }

    @Test
    fun `parseLocalDate returns null for garbage input`() {
        assertNull(parseLocalDate("bad-value"))
    }
}
