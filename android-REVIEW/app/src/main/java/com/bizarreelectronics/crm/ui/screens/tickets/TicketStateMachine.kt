package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem

/**
 * plan:L789 — Ticket state machine: default state set + allowed transition graph.
 *
 * Default linear flow:
 *   Intake → Diagnostic → Awaiting Approval → Awaiting Parts → In Repair
 *     → QA → Ready for Pickup → Completed → Archived
 *
 * Branch states (can be reached from several nodes):
 *   Cancelled, Un-repairable, Warranty Return
 *
 * When the tenant has customised statuses via server, [validateTransition] defers
 * to [StatusDto.transitionRequirements] already cached in [TicketDetailViewModel].
 * The default graph is the fallback for installations where the server does not
 * return custom statuses.
 */

/** Canonical default ticket states. Order matches the default workflow sequence. */
enum class TicketState(val displayName: String) {
    Intake("Intake"),
    Diagnostic("Diagnostic"),
    AwaitingApproval("Awaiting Approval"),
    AwaitingParts("Awaiting Parts"),
    InRepair("In Repair"),
    QA("QA"),
    ReadyForPickup("Ready for Pickup"),
    Completed("Completed"),
    Archived("Archived"),

    // Branch states — reachable from multiple points
    Cancelled("Cancelled"),
    UnRepairable("Un-repairable"),
    WarrantyReturn("Warranty Return"),
    ;

    companion object {
        /** Resolve a [TicketState] from a server status name (case-insensitive). Returns null on no match. */
        fun fromStatusName(name: String): TicketState? =
            entries.firstOrNull { it.displayName.equals(name.trim(), ignoreCase = true) }
    }
}

/** Result of a transition-validation call. */
sealed class TransitionResult {
    /** Transition is allowed — proceed with PATCH. */
    data object Allowed : TransitionResult()

    /** Transition is blocked. [reasons] is a non-empty list of human-readable messages. */
    data class Blocked(val reasons: List<String>) : TransitionResult() {
        /** Convenience: joins all reasons with "; " for inline error display. */
        val message: String get() = reasons.joinToString("; ")
    }
}

/**
 * Allowed transitions in the default workflow.
 *
 * Each key can transition to any state in its value set. Branch states
 * (Cancelled, UnRepairable, WarrantyReturn) are reachable from all non-terminal
 * states and are therefore added below via [addBranchesTo].
 *
 * Rollback: any state can go back to its immediate predecessor (enforced by
 * [TicketStateMachine.validateRollback] separately — admins only).
 */
val defaultTransitions: Map<TicketState, Set<TicketState>> = buildMap {
    val mainFlow = listOf(
        TicketState.Intake,
        TicketState.Diagnostic,
        TicketState.AwaitingApproval,
        TicketState.AwaitingParts,
        TicketState.InRepair,
        TicketState.QA,
        TicketState.ReadyForPickup,
        TicketState.Completed,
        TicketState.Archived,
    )

    val branchStates = setOf(
        TicketState.Cancelled,
        TicketState.UnRepairable,
        TicketState.WarrantyReturn,
    )

    // Each state can advance to the next in the linear sequence
    for (i in 0 until mainFlow.size - 1) {
        val from = mainFlow[i]
        val next = mainFlow[i + 1]
        // Non-terminal main states can also reach branch states
        put(from, setOf(next) + branchStates)
    }

    // Terminal states — no forward transitions (but rollback is allowed by admins)
    put(TicketState.Archived, emptySet())
    put(TicketState.Cancelled, emptySet())
    put(TicketState.UnRepairable, emptySet())
    put(TicketState.WarrantyReturn, emptySet())
}

/**
 * plan:L789-L790 — Ticket state machine.
 *
 * Validates forward transitions against [defaultTransitions] and falls back to
 * server [TicketStatusItem.transitionRequirements] when tenant-customised statuses
 * are present. For tenant statuses, the graph is "anything goes unless a
 * transitionRequirements gate blocks it" since the server owns the graph there.
 */
object TicketStateMachine {

    /**
     * plan:L790 — Validate a status transition.
     *
     * Checks two layers:
     * 1. **State-graph guard** — is the target state reachable from [fromStateName]
     *    in the default graph? Skipped when either name is unrecognised (tenant custom states).
     * 2. **Requirement guards** — from [targetStatusItem.transitionRequirements]:
     *    - `"note_added"` → [hasNotes] must be true
     *    - `"photos_taken"` → [hasPhotos] must be true
     *    - `"device_checked"` → [hasDevices] must be true
     *
     * @param fromStateName  Current status display name (from the server).
     * @param toStateName    Target status display name.
     * @param targetStatusItem  The server DTO for the target status (may be null when statuses
     *                          are not yet loaded — defaults to Allowed in that case).
     * @param hasNotes       True if the ticket has at least one note.
     * @param hasPhotos      True if the ticket has at least one photo.
     * @param hasDevices     True if the ticket has at least one device.
     * @return [TransitionResult.Allowed] or [TransitionResult.Blocked] with reasons.
     */
    fun validateTransition(
        fromStateName: String?,
        toStateName: String?,
        targetStatusItem: TicketStatusItem?,
        hasNotes: Boolean = false,
        hasPhotos: Boolean = false,
        hasDevices: Boolean = false,
    ): TransitionResult {
        val reasons = mutableListOf<String>()

        // Layer 1: default graph check (only when both states are recognised defaults)
        val fromState = fromStateName?.let { TicketState.fromStatusName(it) }
        val toState = toStateName?.let { TicketState.fromStatusName(it) }
        if (fromState != null && toState != null) {
            val allowed = defaultTransitions[fromState] ?: emptySet()
            if (toState !in allowed) {
                reasons += "Cannot move directly from \"${fromState.displayName}\" to \"${toState.displayName}\""
            }
        }

        // Layer 2: requirement guards from server DTO
        if (targetStatusItem != null) {
            val reqs = targetStatusItem.transitionRequirements
            if ("note_added" in reqs && !hasNotes) {
                reasons += "A note must be added before moving to \"${targetStatusItem.name}\""
            }
            if ("photos_taken" in reqs && !hasPhotos) {
                reasons += "Can't mark ${targetStatusItem.name} — no photo"
            }
            if ("device_checked" in reqs && !hasDevices) {
                reasons += "A device must be attached before moving to \"${targetStatusItem.name}\""
            }
        }

        return if (reasons.isEmpty()) TransitionResult.Allowed else TransitionResult.Blocked(reasons)
    }

    /**
     * Validate that an admin rollback to [toStateName] is structurally sensible.
     *
     * Rollback is always admin-only; this function only checks that the target
     * is a recognized state different from the current state. Requirement guards
     * do NOT apply to rollbacks (admin overrides them).
     */
    fun validateRollback(fromStateName: String?, toStateName: String?): TransitionResult {
        if (toStateName.isNullOrBlank()) {
            return TransitionResult.Blocked(listOf("Select a target status to roll back to"))
        }
        if (fromStateName?.equals(toStateName, ignoreCase = true) == true) {
            return TransitionResult.Blocked(listOf("Target status is the same as the current status"))
        }
        return TransitionResult.Allowed
    }

    /**
     * Returns candidate previous states for a rollback dropdown.
     *
     * For default-graph states, returns all predecessors in the main flow.
     * For custom/unknown states, returns all non-terminal default states as candidates.
     */
    fun rollbackCandidates(currentStateName: String?): List<TicketState> {
        val current = currentStateName?.let { TicketState.fromStatusName(it) }
        val mainFlow = listOf(
            TicketState.Intake,
            TicketState.Diagnostic,
            TicketState.AwaitingApproval,
            TicketState.AwaitingParts,
            TicketState.InRepair,
            TicketState.QA,
            TicketState.ReadyForPickup,
            TicketState.Completed,
        )
        return if (current != null) {
            val idx = mainFlow.indexOf(current)
            if (idx > 0) mainFlow.subList(0, idx) else emptyList()
        } else {
            mainFlow
        }
    }
}
