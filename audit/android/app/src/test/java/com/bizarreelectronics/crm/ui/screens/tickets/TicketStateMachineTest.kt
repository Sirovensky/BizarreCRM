package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * plan:L789-L793 — Unit tests for [TicketStateMachine].
 *
 * Covers:
 *  - Default transition graph connectivity
 *  - Blocked transitions (out-of-order moves)
 *  - Branch states reachable from non-terminal main states
 *  - Terminal states have no forward transitions
 *  - Requirement guards (note_added, photos_taken, device_checked)
 *  - Rollback validation rules
 *  - Rollback candidates list
 *  - Custom/unknown state handling (graceful pass-through)
 */
class TicketStateMachineTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private fun makeStatus(
        name: String,
        requirements: List<String> = emptyList(),
    ) = TicketStatusItem(
        id = name.hashCode().toLong(),
        name = name,
        color = null,
        sortOrder = 0,
        isClosed = 0,
        isCancelled = 0,
        notifyCustomer = 0,
        transitionRequirements = requirements,
    )

    private fun allowed(
        from: String,
        to: String,
        targetStatus: TicketStatusItem? = null,
        hasNotes: Boolean = true,
        hasPhotos: Boolean = true,
        hasDevices: Boolean = true,
    ) = TicketStateMachine.validateTransition(from, to, targetStatus, hasNotes, hasPhotos, hasDevices)

    // ─── 1. Default graph — forward transitions ───────────────────────────────

    @Test
    fun `Intake can advance to Diagnostic`() {
        val result = allowed("Intake", "Diagnostic")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `Diagnostic can advance to Awaiting Approval`() {
        val result = allowed("Diagnostic", "Awaiting Approval")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `Awaiting Approval can advance to Awaiting Parts`() {
        val result = allowed("Awaiting Approval", "Awaiting Parts")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `Awaiting Parts can advance to In Repair`() {
        val result = allowed("Awaiting Parts", "In Repair")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `In Repair can advance to QA`() {
        val result = allowed("In Repair", "QA")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `QA can advance to Ready for Pickup`() {
        val result = allowed("QA", "Ready for Pickup")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `Ready for Pickup can advance to Completed`() {
        val result = allowed("Ready for Pickup", "Completed")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `Completed can advance to Archived`() {
        val result = allowed("Completed", "Archived")
        assertTrue(result is TransitionResult.Allowed)
    }

    // ─── 2. Blocked transitions ───────────────────────────────────────────────

    @Test
    fun `Intake cannot jump directly to Ready for Pickup`() {
        val result = allowed("Intake", "Ready for Pickup")
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `Diagnostic cannot jump directly to Completed`() {
        val result = allowed("Diagnostic", "Completed")
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `Archived has no forward transitions`() {
        val result = allowed("Archived", "Completed")
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `Cancelled has no forward transitions`() {
        val result = allowed("Cancelled", "In Repair")
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `Un-repairable has no forward transitions`() {
        val result = allowed("Un-repairable", "Intake")
        assertTrue(result is TransitionResult.Blocked)
    }

    // ─── 3. Branch states reachable from non-terminal main states ─────────────

    @Test
    fun `Intake can transition to Cancelled`() {
        val result = allowed("Intake", "Cancelled")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `In Repair can transition to Un-repairable`() {
        val result = allowed("In Repair", "Un-repairable")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `QA can transition to Warranty Return`() {
        val result = allowed("QA", "Warranty Return")
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `Ready for Pickup can transition to Cancelled`() {
        val result = allowed("Ready for Pickup", "Cancelled")
        assertTrue(result is TransitionResult.Allowed)
    }

    // ─── 4. Requirement guards ────────────────────────────────────────────────

    @Test
    fun `note_added requirement blocks when no notes`() {
        val target = makeStatus("QA", requirements = listOf("note_added"))
        val result = TicketStateMachine.validateTransition(
            fromStateName = "In Repair",
            toStateName = "QA",
            targetStatusItem = target,
            hasNotes = false,
            hasPhotos = true,
            hasDevices = true,
        )
        assertTrue(result is TransitionResult.Blocked)
        val blocked = result as TransitionResult.Blocked
        assertTrue(blocked.message.contains("note"))
    }

    @Test
    fun `photos_taken requirement blocks when no photos`() {
        val target = makeStatus("Ready for Pickup", requirements = listOf("photos_taken"))
        val result = TicketStateMachine.validateTransition(
            fromStateName = "QA",
            toStateName = "Ready for Pickup",
            targetStatusItem = target,
            hasNotes = true,
            hasPhotos = false,
            hasDevices = true,
        )
        assertTrue(result is TransitionResult.Blocked)
        val blocked = result as TransitionResult.Blocked
        assertTrue(blocked.message.contains("photo"))
    }

    @Test
    fun `photos_taken requirement surfaces inline error Can't mark X no photo`() {
        val target = makeStatus("Ready for Pickup", requirements = listOf("photos_taken"))
        val result = TicketStateMachine.validateTransition(
            fromStateName = "QA",
            toStateName = "Ready for Pickup",
            targetStatusItem = target,
            hasPhotos = false,
        )
        val blocked = result as? TransitionResult.Blocked
        assertFalse(blocked?.message.isNullOrBlank())
    }

    @Test
    fun `device_checked requirement blocks when no devices`() {
        val target = makeStatus("Diagnostic", requirements = listOf("device_checked"))
        val result = TicketStateMachine.validateTransition(
            fromStateName = "Intake",
            toStateName = "Diagnostic",
            targetStatusItem = target,
            hasNotes = true,
            hasPhotos = true,
            hasDevices = false,
        )
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `all requirements satisfied returns Allowed`() {
        val target = makeStatus(
            "QA",
            requirements = listOf("note_added", "photos_taken", "device_checked"),
        )
        val result = TicketStateMachine.validateTransition(
            fromStateName = "In Repair",
            toStateName = "QA",
            targetStatusItem = target,
            hasNotes = true,
            hasPhotos = true,
            hasDevices = true,
        )
        assertTrue(result is TransitionResult.Allowed)
    }

    // ─── 5. Custom/unknown state handling ─────────────────────────────────────

    @Test
    fun `unknown from-state does not block when to-state is also unknown`() {
        // Both names unrecognised → graph check skipped; depends only on requirements
        val result = TicketStateMachine.validateTransition(
            fromStateName = "Custom State A",
            toStateName = "Custom State B",
            targetStatusItem = null,
        )
        assertTrue(result is TransitionResult.Allowed)
    }

    @Test
    fun `unknown from-state with known to-state skips graph block`() {
        // fromState unrecognised → no graph entry → graph guard skipped
        val result = TicketStateMachine.validateTransition(
            fromStateName = "CustomTenantState",
            toStateName = "Completed",
            targetStatusItem = null,
        )
        assertTrue(result is TransitionResult.Allowed)
    }

    // ─── 6. Rollback validation ───────────────────────────────────────────────

    @Test
    fun `rollback requires a target status`() {
        val result = TicketStateMachine.validateRollback("In Repair", null)
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `rollback requires a non-blank target`() {
        val result = TicketStateMachine.validateRollback("In Repair", "  ")
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `rollback to same state is blocked`() {
        val result = TicketStateMachine.validateRollback("In Repair", "In Repair")
        assertTrue(result is TransitionResult.Blocked)
    }

    @Test
    fun `rollback to different state is allowed`() {
        val result = TicketStateMachine.validateRollback("In Repair", "Diagnostic")
        assertTrue(result is TransitionResult.Allowed)
    }

    // ─── 7. Rollback candidates ───────────────────────────────────────────────

    @Test
    fun `rollback candidates for Intake are empty`() {
        val candidates = TicketStateMachine.rollbackCandidates("Intake")
        assertTrue(candidates.isEmpty())
    }

    @Test
    fun `rollback candidates for Diagnostic contains Intake only`() {
        val candidates = TicketStateMachine.rollbackCandidates("Diagnostic")
        assertEquals(1, candidates.size)
        assertEquals(TicketState.Intake, candidates[0])
    }

    @Test
    fun `rollback candidates for In Repair includes Intake through Awaiting Parts`() {
        val candidates = TicketStateMachine.rollbackCandidates("In Repair")
        assertEquals(4, candidates.size)
        assertTrue(TicketState.Intake in candidates)
        assertTrue(TicketState.Diagnostic in candidates)
        assertTrue(TicketState.AwaitingApproval in candidates)
        assertTrue(TicketState.AwaitingParts in candidates)
    }

    @Test
    fun `rollback candidates for unknown state returns all non-terminal main states`() {
        val candidates = TicketStateMachine.rollbackCandidates("TenantCustomState")
        assertTrue(candidates.isNotEmpty())
        // Should include standard non-terminal states
        assertTrue(TicketState.Intake in candidates)
        assertTrue(TicketState.Completed in candidates)
    }
}
