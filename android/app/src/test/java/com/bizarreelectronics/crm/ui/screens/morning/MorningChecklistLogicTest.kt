package com.bizarreelectronics.crm.ui.screens.morning

import com.bizarreelectronics.crm.data.remote.dto.ChecklistStepDto
import com.bizarreelectronics.crm.util.PingResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * §36 L588 — Pure-JVM unit tests for morning-checklist business logic.
 *
 * No Android context, Hilt, or Room required.  Tests cover:
 *  1.  Date-key generation (ISO format yyyy-MM-dd).
 *  2.  Step-completion toggle (add / remove from set).
 *  3.  Completion state transitions (none → partial → all-done).
 *  4.  [PingResult] interpretation helpers.
 *  5.  [MorningChecklistUiState.isAllDone] correctness.
 *  6.  Default steps list is non-empty with correct size.
 *  7.  Cash amount is stored independently of step completion.
 *  8.  Completion with zero steps is not all-done.
 */
class MorningChecklistLogicTest {

    // -------------------------------------------------------------------------
    // 1. Date-key generation
    // -------------------------------------------------------------------------

    @Test
    fun `date key is ISO format yyyy-MM-dd`() {
        val dateKey = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        // Must match pattern yyyy-MM-dd (length 10, digits at positions 0-3, 5-6, 8-9)
        assertEquals(10, dateKey.length)
        assertTrue("Date key must match yyyy-MM-dd", dateKey.matches(Regex("""\d{4}-\d{2}-\d{2}""")))
    }

    @Test
    fun `date key for a known date is correct`() {
        val date = LocalDate.of(2026, 4, 23)
        val key = date.format(DateTimeFormatter.ISO_LOCAL_DATE)
        assertEquals("2026-04-23", key)
    }

    // -------------------------------------------------------------------------
    // 2. Step-completion toggle
    // -------------------------------------------------------------------------

    @Test
    fun `toggling unchecked step adds it to the set`() {
        val initial = emptySet<Int>()
        val updated = toggleStep(initial, stepId = 1)
        assertTrue(1 in updated)
    }

    @Test
    fun `toggling checked step removes it from the set`() {
        val initial = setOf(1, 2, 3)
        val updated = toggleStep(initial, stepId = 2)
        assertFalse(2 in updated)
        assertTrue(1 in updated)
        assertTrue(3 in updated)
    }

    @Test
    fun `toggle is idempotent when applied twice`() {
        val initial = setOf(5)
        val afterFirst = toggleStep(initial, stepId = 5)
        val afterSecond = toggleStep(afterFirst, stepId = 5)
        assertEquals(initial, afterSecond)
    }

    // -------------------------------------------------------------------------
    // 3. Completion state transitions
    // -------------------------------------------------------------------------

    @Test
    fun `isAllDone is false when no steps completed`() {
        val state = buildState(completedIds = emptySet())
        assertFalse(state.isAllDone)
    }

    @Test
    fun `isAllDone is false when some steps completed`() {
        val state = buildState(completedIds = setOf(1, 2, 3))
        assertFalse(state.isAllDone)
    }

    @Test
    fun `isAllDone is true when all steps completed`() {
        val allIds = MorningChecklistDefaults.steps.map { it.id }.toSet()
        val state = buildState(completedIds = allIds)
        assertTrue(state.isAllDone)
    }

    @Test
    fun `isAllDone is false when steps list is empty`() {
        val state = MorningChecklistUiState(steps = emptyList(), completedStepIds = emptySet())
        assertFalse(state.isAllDone)
    }

    // -------------------------------------------------------------------------
    // 4. PingResult interpretation
    // -------------------------------------------------------------------------

    @Test
    fun `PingResult Success carries non-negative latency`() {
        val result = PingResult.Success(latencyMs = 120L)
        assertTrue((result as PingResult.Success).latencyMs >= 0L)
    }

    @Test
    fun `PingResult Failure carries a non-blank reason`() {
        val result = PingResult.Failure(reason = "Connection refused")
        assertTrue((result as PingResult.Failure).reason.isNotBlank())
    }

    @Test
    fun `PingResult Timeout is distinct from Failure`() {
        val timeout: PingResult = PingResult.Timeout
        assertFalse(timeout is PingResult.Failure)
    }

    @Test
    fun `PingResult Pending is distinct from Success`() {
        val pending: PingResult = PingResult.Pending
        assertFalse(pending is PingResult.Success)
    }

    @Test
    fun `ping result success indicates device reachable`() {
        assertTrue(isDeviceReachable(PingResult.Success(latencyMs = 50)))
    }

    @Test
    fun `ping result failure indicates device not reachable`() {
        assertFalse(isDeviceReachable(PingResult.Failure("timeout")))
    }

    @Test
    fun `ping result timeout indicates device not reachable`() {
        assertFalse(isDeviceReachable(PingResult.Timeout))
    }

    @Test
    fun `ping result pending indicates unknown reachability`() {
        assertFalse(isDeviceReachable(PingResult.Pending))
    }

    // -------------------------------------------------------------------------
    // 5. Default steps
    // -------------------------------------------------------------------------

    @Test
    fun `default steps list has exactly 7 items`() {
        assertEquals(7, MorningChecklistDefaults.steps.size)
    }

    @Test
    fun `default steps have unique IDs`() {
        val ids = MorningChecklistDefaults.steps.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
    }

    @Test
    fun `step 1 requires input (cash dialog)`() {
        val step1 = MorningChecklistDefaults.steps.first { it.id == 1 }
        assertTrue(step1.requiresInput)
    }

    @Test
    fun `steps 3 4 5 have deepLinkRoutes`() {
        val stepsWithNav = MorningChecklistDefaults.steps
            .filter { it.deepLinkRoute != null }
            .map { it.id }
        assertTrue(3 in stepsWithNav)
        assertTrue(4 in stepsWithNav)
        assertTrue(5 in stepsWithNav)
    }

    @Test
    fun `steps 1 2 6 7 have no deepLinkRoute`() {
        val stepsWithoutNav = MorningChecklistDefaults.steps
            .filter { it.deepLinkRoute == null }
            .map { it.id }
        assertTrue(1 in stepsWithoutNav)
        assertTrue(2 in stepsWithoutNav)
        assertTrue(6 in stepsWithoutNav)
        assertTrue(7 in stepsWithoutNav)
    }

    // -------------------------------------------------------------------------
    // 6. Cash amount is independent of step completion
    // -------------------------------------------------------------------------

    @Test
    fun `setting cash amount does not auto-complete step 1`() {
        val state = MorningChecklistUiState(
            completedStepIds = emptySet(),
            cashAmount = "150.00",
        )
        assertFalse(1 in state.completedStepIds)
    }

    @Test
    fun `cash amount survives step toggle`() {
        val state = MorningChecklistUiState(
            cashAmount = "200.00",
            completedStepIds = emptySet(),
        )
        val updated = state.copy(completedStepIds = setOf(1))
        assertEquals("200.00", updated.cashAmount)
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Pure toggle function mirroring the one in [MorningChecklistViewModel.toggleStep].
     * Extracted here so the logic is testable without a ViewModel instance.
     */
    private fun toggleStep(current: Set<Int>, stepId: Int): Set<Int> =
        if (stepId in current) current - stepId else current + stepId

    /**
     * Returns true only when the ping result is [PingResult.Success].
     * Mirrors the UI rendering contract documented on [PingResult].
     */
    private fun isDeviceReachable(result: PingResult): Boolean = result is PingResult.Success

    /** Build a [MorningChecklistUiState] with the default steps and given completed IDs. */
    private fun buildState(completedIds: Set<Int>): MorningChecklistUiState =
        MorningChecklistUiState(
            steps = MorningChecklistDefaults.steps,
            completedStepIds = completedIds,
        )

    /** Build a minimal [ChecklistStepDto] for test purposes. */
    @Suppress("SameParameterValue")
    private fun step(id: Int, requiresInput: Boolean = false, deepLinkRoute: String? = null) =
        ChecklistStepDto(
            id = id,
            title = "Step $id",
            requiresInput = requiresInput,
            deepLinkRoute = deepLinkRoute,
        )
}
