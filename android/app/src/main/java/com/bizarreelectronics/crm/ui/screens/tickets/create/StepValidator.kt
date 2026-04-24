package com.bizarreelectronics.crm.ui.screens.tickets.create

import com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateSubStep
import com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateUiState

/**
 * Pure validation logic for each wizard sub-step.
 *
 * [validate] is called before enabling the Next / Create CTA.  All functions
 * are stateless so they can be tested without any Android framework.
 *
 * ### Validation policy per step
 *
 * - **CUSTOMER** — either a customer is selected OR walk-in is explicitly set.
 * - **DEVICE** — at least one device name is non-blank (selected model or custom).
 * - **SERVICES** — at least one cart item or a service + price is pending; we
 *   allow advancing with an empty cart so the user can skip to diagnostic.
 *   (The final REVIEW submit validates a non-empty cart.)
 * - **DIAGNOSTIC** — always valid; all fields optional.
 * - **PRICING** — always valid; pricing is pre-filled from service selection.
 * - **ASSIGNEE** — always valid; assignment is optional.
 * - **REVIEW** — cart must have at least one item AND customer/walk-in resolved.
 */
object StepValidator {

    /**
     * Sealed result returned by [validate].
     *
     * [Valid] — the step is complete and the user may advance.
     * [Invalid] — the step has an error; [reason] is shown in the UI.
     */
    sealed class ValidationResult {
        object Valid : ValidationResult()
        data class Invalid(val reason: String) : ValidationResult()
    }

    /**
     * Validates [step] against the current [state].
     *
     * Returns [ValidationResult.Valid] when the step requirements are met,
     * [ValidationResult.Invalid] with a user-facing reason otherwise.
     */
    fun validate(step: TicketCreateSubStep, state: TicketCreateUiState): ValidationResult =
        when (step) {
            TicketCreateSubStep.CUSTOMER -> validateCustomer(state)
            TicketCreateSubStep.DEVICE -> validateDevice(state)
            TicketCreateSubStep.SERVICES -> ValidationResult.Valid
            TicketCreateSubStep.DIAGNOSTIC -> ValidationResult.Valid
            TicketCreateSubStep.PRICING -> ValidationResult.Valid
            TicketCreateSubStep.ASSIGNEE -> ValidationResult.Valid
            TicketCreateSubStep.REVIEW -> validateReview(state)
        }

    /** Returns [ValidationResult.Valid] only when the step is valid. */
    fun isValid(step: TicketCreateSubStep, state: TicketCreateUiState): Boolean =
        validate(step, state) is ValidationResult.Valid

    // ── Private validators ──────────────────────────────────────────────

    private fun validateCustomer(state: TicketCreateUiState): ValidationResult =
        when {
            state.selectedCustomer != null -> ValidationResult.Valid
            state.isWalkIn -> ValidationResult.Valid
            else -> ValidationResult.Invalid("Select a customer or choose Walk-in to continue.")
        }

    private fun validateDevice(state: TicketCreateUiState): ValidationResult {
        val hasSelectedModel = state.selectedDevice != null
        val hasCustomName = state.customDeviceName.isNotBlank()
        return if (hasSelectedModel || hasCustomName) ValidationResult.Valid
        else ValidationResult.Invalid("Select or enter a device to continue.")
    }

    private fun validateReview(state: TicketCreateUiState): ValidationResult =
        when {
            state.selectedCustomer == null && !state.isWalkIn ->
                ValidationResult.Invalid("No customer selected.")
            state.cartItems.isEmpty() ->
                ValidationResult.Invalid("Add at least one device/service to the cart.")
            else -> ValidationResult.Valid
        }
}
