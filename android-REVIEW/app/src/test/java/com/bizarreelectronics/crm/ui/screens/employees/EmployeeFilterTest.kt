package com.bizarreelectronics.crm.ui.screens.employees

import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.ui.screens.employees.components.EmployeeFilter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for EmployeeListUiState.filtered (ActionPlan §14.1 L1610).
 *
 * Pure-JVM — no Android context required.
 *
 * Cases:
 *  1.  Filter.All returns full list
 *  2.  Filter.Admin keeps only admin role
 *  3.  Filter.Technician keeps only technician role
 *  4.  Filter.Active keeps only active (isActive == 1)
 *  5.  Filter.Inactive keeps only inactive (isActive != 1)
 *  6.  Filter.ClockedIn keeps only clocked-in employees
 *  7.  Filter.Admin on empty list returns empty
 *  8.  Filter.ClockedIn with none clocked in returns empty
 *  9.  Filter.Active with mixed data counts correctly
 * 10.  EmployeeFilter.All is first enum entry
 * 11.  EmployeeFilter has exactly 6 entries
 * 12.  EmployeeListUiState default filter is All
 * 13.  presenceMap defaults to empty map
 */
class EmployeeFilterTest {

    // ---------------------------------------------------------------------------
    // filtered list tests
    // ---------------------------------------------------------------------------

    @Test
    fun `1 filter All returns all employees`() {
        val state = stateWith(admin(), technician(), inactiveEmployee())
        assertEquals(3, state.filtered.size)
    }

    @Test
    fun `2 filter Admin keeps only admin role`() {
        val state = stateWith(admin(), technician(), admin(id = 2))
        val result = state.copy(activeFilter = EmployeeFilter.Admin).filtered
        assertEquals(2, result.size)
        assertTrue(result.all { it.role == "admin" })
    }

    @Test
    fun `3 filter Technician keeps only technician role`() {
        val state = stateWith(admin(), technician(), technician(id = 2))
        val result = state.copy(activeFilter = EmployeeFilter.Technician).filtered
        assertEquals(2, result.size)
        assertTrue(result.all { it.role == "technician" })
    }

    @Test
    fun `4 filter Active keeps only isActive == 1`() {
        val state = stateWith(active(), inactiveEmployee())
        val result = state.copy(activeFilter = EmployeeFilter.Active).filtered
        assertEquals(1, result.size)
        assertEquals(1, result.first().isActive)
    }

    @Test
    fun `5 filter Inactive keeps only isActive != 1`() {
        val state = stateWith(active(), inactiveEmployee())
        val result = state.copy(activeFilter = EmployeeFilter.Inactive).filtered
        assertEquals(1, result.size)
        assertEquals(0, result.first().isActive)
    }

    @Test
    fun `6 filter ClockedIn keeps only isClockedIn true`() {
        val state = stateWith(clockedIn(), clockedOut(), clockedIn(id = 2))
        val result = state.copy(activeFilter = EmployeeFilter.ClockedIn).filtered
        assertEquals(2, result.size)
        assertTrue(result.all { it.isClockedIn == true })
    }

    @Test
    fun `7 filter Admin on empty list returns empty`() {
        val state = stateWith()
        val result = state.copy(activeFilter = EmployeeFilter.Admin).filtered
        assertTrue(result.isEmpty())
    }

    @Test
    fun `8 filter ClockedIn with none clocked in returns empty`() {
        val state = stateWith(clockedOut(), clockedOut(id = 2))
        val result = state.copy(activeFilter = EmployeeFilter.ClockedIn).filtered
        assertTrue(result.isEmpty())
    }

    @Test
    fun `9 filter Active with mixed data counts correctly`() {
        val employees = (1L..5L).map { i ->
            employee(id = i, isActive = if (i % 2L == 0L) 1 else 0)
        }
        val state = EmployeeListUiState(employees = employees, activeFilter = EmployeeFilter.Active)
        assertEquals(2, state.filtered.size) // ids 2, 4
    }

    // ---------------------------------------------------------------------------
    // EmployeeFilter enum tests
    // ---------------------------------------------------------------------------

    @Test
    fun `10 EmployeeFilter All is first entry`() {
        assertEquals(EmployeeFilter.All, EmployeeFilter.entries.first())
    }

    @Test
    fun `11 EmployeeFilter has exactly 6 entries`() {
        assertEquals(6, EmployeeFilter.entries.size)
    }

    // ---------------------------------------------------------------------------
    // EmployeeListUiState default tests
    // ---------------------------------------------------------------------------

    @Test
    fun `12 default activeFilter is All`() {
        assertEquals(EmployeeFilter.All, EmployeeListUiState().activeFilter)
    }

    @Test
    fun `13 presenceMap defaults to empty map`() {
        assertTrue(EmployeeListUiState().presenceMap.isEmpty())
    }

    // ---------------------------------------------------------------------------
    // Factory helpers
    // ---------------------------------------------------------------------------

    private fun stateWith(vararg employees: EmployeeListItem) =
        EmployeeListUiState(employees = employees.toList())

    private fun employee(
        id: Long = 1L,
        role: String = "technician",
        isActive: Int = 1,
        isClockedIn: Boolean = false,
    ) = EmployeeListItem(
        id = id,
        username = "user$id",
        email = "user$id@example.com",
        firstName = "First",
        lastName = "Last",
        role = role,
        avatarUrl = null,
        isActive = isActive,
        hasPin = 0,
        permissions = null,
        isClockedIn = isClockedIn,
        createdAt = null,
        updatedAt = null,
    )

    private fun admin(id: Long = 1L) = employee(id = id, role = "admin")
    private fun technician(id: Long = 1L) = employee(id = id, role = "technician")
    private fun active(id: Long = 1L) = employee(id = id, isActive = 1)
    private fun inactiveEmployee(id: Long = 1L) = employee(id = id, isActive = 0)
    private fun clockedIn(id: Long = 1L) = employee(id = id, isClockedIn = true)
    private fun clockedOut(id: Long = 1L) = employee(id = id, isClockedIn = false)
}
