package com.bizarreelectronics.crm.ui.screens.appointments

import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.ui.screens.appointments.components.buildApptCountMap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * Unit tests for appointment month-view logic (ActionPlan §10 L1420).
 *
 * All tests are pure-JVM — no Android context required.
 *
 * Cases:
 *  1. Empty list → empty map
 *  2. Single appointment → count 1 for that date
 *  3. Two appointments on same day → count 2
 *  4. Appointments on different days → separate counts
 *  5. Appointment with null startTime → skipped (not in map)
 *  6. Appointment with invalid ISO string → skipped
 *  7. Multiple months present → only the matching date is counted
 *  8. AppointmentViewMode.Agenda is the first mode (default in VM)
 *  9. AppointmentFilter default has all nulls (no filtering)
 * 10. AppointmentListUiState.filtered passes everything when filter is default
 * 11. AppointmentListUiState.filtered filters by employeeId
 * 12. AppointmentListUiState.filtered filters by location (case-insensitive)
 * 13. AppointmentListUiState.filtered filters by type (case-insensitive)
 */
class AppointmentMonthLogicTest {

    // ---------------------------------------------------------------------------
    // buildApptCountMap tests
    // ---------------------------------------------------------------------------

    @Test
    fun `1 empty list returns empty map`() {
        val map = buildApptCountMap(emptyList())
        assertEquals(emptyMap<LocalDate, Int>(), map)
    }

    @Test
    fun `2 single appointment counted once`() {
        val appts = listOf(appt(id = 1, startTime = "2026-04-15T09:00:00"))
        val map = buildApptCountMap(appts)
        assertEquals(1, map[LocalDate.of(2026, 4, 15)])
    }

    @Test
    fun `3 two appointments same day counted as two`() {
        val appts = listOf(
            appt(id = 1, startTime = "2026-04-15T09:00:00"),
            appt(id = 2, startTime = "2026-04-15T14:00:00"),
        )
        val map = buildApptCountMap(appts)
        assertEquals(2, map[LocalDate.of(2026, 4, 15)])
    }

    @Test
    fun `4 appointments on different days have separate counts`() {
        val appts = listOf(
            appt(id = 1, startTime = "2026-04-15T09:00:00"),
            appt(id = 2, startTime = "2026-04-16T14:00:00"),
        )
        val map = buildApptCountMap(appts)
        assertEquals(1, map[LocalDate.of(2026, 4, 15)])
        assertEquals(1, map[LocalDate.of(2026, 4, 16)])
    }

    @Test
    fun `5 null startTime appointment is skipped`() {
        val appts = listOf(appt(id = 1, startTime = null))
        val map = buildApptCountMap(appts)
        assertEquals(emptyMap<LocalDate, Int>(), map)
    }

    @Test
    fun `6 invalid ISO startTime is skipped`() {
        val appts = listOf(appt(id = 1, startTime = "not-a-date"))
        val map = buildApptCountMap(appts)
        assertEquals(emptyMap<LocalDate, Int>(), map)
    }

    @Test
    fun `7 appointments in different months counted separately`() {
        val appts = listOf(
            appt(id = 1, startTime = "2026-03-31T09:00:00"),
            appt(id = 2, startTime = "2026-04-01T09:00:00"),
        )
        val map = buildApptCountMap(appts)
        assertEquals(1, map[LocalDate.of(2026, 3, 31)])
        assertEquals(1, map[LocalDate.of(2026, 4, 1)])
        assertEquals(2, map.size)
    }

    // ---------------------------------------------------------------------------
    // AppointmentViewMode enum tests
    // ---------------------------------------------------------------------------

    @Test
    fun `8 Agenda is first view mode entry`() {
        assertEquals(AppointmentViewMode.Agenda, AppointmentViewMode.entries.first())
    }

    // ---------------------------------------------------------------------------
    // AppointmentFilter default tests
    // ---------------------------------------------------------------------------

    @Test
    fun `9 default filter has all nulls`() {
        val filter = AppointmentFilter()
        assertNull(filter.employeeId)
        assertNull(filter.employeeName)
        assertNull(filter.location)
        assertNull(filter.type)
    }

    // ---------------------------------------------------------------------------
    // AppointmentListUiState.filtered tests
    // ---------------------------------------------------------------------------

    @Test
    fun `10 filtered with default filter passes everything`() {
        val state = AppointmentListUiState(
            appointments = listOf(
                appt(id = 1, startTime = "2026-04-15T09:00:00"),
                appt(id = 2, startTime = "2026-04-16T09:00:00"),
            ),
        )
        assertEquals(2, state.filtered.size)
    }

    @Test
    fun `11 filtered by employeeId keeps matching only`() {
        val state = AppointmentListUiState(
            appointments = listOf(
                appt(id = 1, employeeId = 10L),
                appt(id = 2, employeeId = 20L),
            ),
            filter = AppointmentFilter(employeeId = 10L),
        )
        assertEquals(1, state.filtered.size)
        assertEquals(1L, state.filtered.first().id)
    }

    @Test
    fun `12 filtered by location is case insensitive`() {
        val state = AppointmentListUiState(
            appointments = listOf(
                appt(id = 1, location = "Main Store"),
                appt(id = 2, location = "secondary"),
            ),
            filter = AppointmentFilter(location = "main store"),
        )
        assertEquals(1, state.filtered.size)
        assertEquals(1L, state.filtered.first().id)
    }

    @Test
    fun `13 filtered by type is case insensitive`() {
        val state = AppointmentListUiState(
            appointments = listOf(
                appt(id = 1, type = "Repair"),
                appt(id = 2, type = "Diagnostic"),
            ),
            filter = AppointmentFilter(type = "repair"),
        )
        assertEquals(1, state.filtered.size)
        assertEquals(1L, state.filtered.first().id)
    }

    // ---------------------------------------------------------------------------
    // Factory helpers
    // ---------------------------------------------------------------------------

    private fun appt(
        id: Long,
        startTime: String? = "2026-04-15T09:00:00",
        employeeId: Long? = null,
        location: String? = null,
        type: String? = null,
    ) = AppointmentItem(
        id = id,
        title = "Test Appointment",
        customerName = "Customer $id",
        customerId = id,
        employeeId = employeeId,
        employeeName = null,
        startTime = startTime,
        endTime = null,
        durationMinutes = 60,
        status = "scheduled",
        type = type,
        location = location,
        notes = null,
        reminderOffsetMinutes = null,
        createdAt = null,
        updatedAt = null,
    )
}
