#if canImport(UIKit)
import Foundation
import Observation
import Networking
import Core

// MARK: - PosRepairFlowCoordinator
//
// @MainActor @Observable state machine that drives the 4-step repair intake
// flow (frames 1b–1e). Callers inject the current customer ID and an
// `APIClient`; the coordinator creates and updates the server-side draft
// as the user advances through steps.
//
// Server routes consumed:
//   POST  /api/v1/tickets                        — create draft (step 1 commit)
//   POST  /api/v1/tickets/:id/devices            — attach device (step 1 commit)
//   PATCH /api/v1/tickets/:id (via PUT)          — update symptom/notes (step 2 commit)
//   POST  /api/v1/tickets/:id/notes              — diagnostic notes (step 3 commit)
//   POST  /api/v1/tickets/:id/convert-to-invoice — deposit tendered (step 4 commit)

@MainActor
@Observable
public final class PosRepairFlowCoordinator {

    // MARK: - Public state

    /// Currently active step.
    public private(set) var currentStep: RepairStep = .pickDevice

    /// Customer display name shown in the nav bar chip on step 1b ("Sarah M.").
    /// Set by the caller before presenting the repair flow.
    public var customerDisplayName: String?

    /// Server-assigned ticket id once the draft has been persisted.
    public private(set) var savedDraftId: Int64?

    /// Server-assigned ticket-device id (used to attach diagnostic notes).
    public private(set) var savedDeviceId: Int64?

    /// Invoice id set after convert-to-invoice completes.
    public private(set) var invoiceId: Int64?

    /// Draft accumulated as the user progresses.
    public private(set) var draft: TicketDraft

    /// Non-nil while an async network call is in flight.
    public private(set) var isLoading: Bool = false

    /// User-visible error; cleared when the user retries.
    public private(set) var errorMessage: String?

    /// Set to `true` when the flow completes (deposit tendered).
    public private(set) var isComplete: Bool = false

    // MARK: - Private

    private let api: any APIClient

    /// Closure called when the user cancels; gives the parent an opportunity
    /// to dismiss the sheet / pop the navigation stack.
    public var onCancel: (() -> Void)?

    /// Closure called when the deposit is tendered and the invoice is created.
    public var onComplete: ((Int64) -> Void)?

    /// Customer display name for the nav-bar chip on repair step screens
    /// (mockup spec `pos-iphone-mockups.html` 1b–1e + `pos-ipad-mockups.html`
    /// 1b–1e: "New repair · Sarah M."). Set by PosView after coordinator
    /// construction; nil falls back to "Repair" without a customer chip.
    public var customerDisplayName: String?

    // MARK: - Init

    public init(customerId: Int64, api: any APIClient) {
        self.draft = TicketDraft(customerId: customerId)
        self.api = api
    }

    // MARK: - Navigation

    /// Attempt to move to the next step. For steps that require server
    /// persistence (`pickDevice`, `describeIssue`, `diagnosticQuote`) the
    /// coordinator sends the network request before advancing; errors surface
    /// in `errorMessage` and leave the current step unchanged.
    public func advance() {
        Task {
            await _advance()
        }
    }

    private func _advance() async {
        errorMessage = nil

        switch currentStep {
        case .pickDevice:
            guard draft.isDeviceStepValid else {
                errorMessage = "Please select or add a device before continuing."
                return
            }
            await commitDeviceStep()

        case .describeIssue:
            guard draft.isSymptomStepValid else {
                errorMessage = "Please describe the issue before continuing."
                return
            }
            await commitSymptomStep()

        case .diagnosticQuote:
            await commitQuoteStep()

        case .deposit:
            await commitDepositStep()
        }
    }

    /// Navigate back one step. Does NOT undo server-side changes — the draft
    /// stays persisted so that re-advancing merely patches the same record.
    public func goBack() {
        errorMessage = nil
        guard let previous = currentStep.previous else { return }
        currentStep = previous
    }

    /// Jump directly to `step` — used by tests and the iPad inspector
    /// back-navigation affordance. Validated to prevent forward jumps past
    /// unfinished steps.
    public func jump(to step: RepairStep) {
        // Only allow jumping backwards (or to a step already reached).
        guard step.rawValue <= currentStep.rawValue else {
            errorMessage = "Complete the current step before jumping ahead."
            return
        }
        currentStep = step
        errorMessage = nil
    }

    /// Cancel the flow. If a draft has been persisted on the server it is
    /// intentionally left as a draft (not deleted) so the cashier can resume
    /// from the tickets list. Calls `onCancel` after state is reset.
    public func cancel() {
        errorMessage = nil
        isLoading = false
        onCancel?()
    }

    // MARK: - Draft mutations (called by step VMs)

    /// Called by `PosRepairDevicePickerView` when the user selects or confirms a device.
    public func setDevice(_ option: PosDeviceOption) {
        draft = draft.withDevice(option)
    }

    /// Called by `PosRepairSymptomView` when any symptom field changes.
    public func setSymptom(
        text: String,
        condition: DeviceCondition?,
        chips: Set<RepairSymptomChip>,
        internalNotes: String
    ) {
        draft = draft.withSymptom(
            text: text,
            condition: condition,
            chips: chips,
            internalNotes: internalNotes
        )
    }

    /// Called by `PosRepairQuoteView` when quote lines or diagnostic notes change.
    public func setQuote(diagnosticNotes: String, lines: [RepairQuoteLine]) {
        draft = draft.withQuote(diagnosticNotes: diagnosticNotes, lines: lines)
    }

    /// Called by the deposit view when the cashier edits the deposit amount.
    public func setDepositCents(_ cents: Int) {
        draft = draft.withDeposit(cents: cents)
    }

    // MARK: - Step commits

    /// Creates the server-side draft ticket and attaches the chosen device.
    private func commitDeviceStep() async {
        guard let deviceOption = draft.selectedDeviceOption else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let deviceName: String
            switch deviceOption {
            case .asset(_, let label, _):
                deviceName = label
            case .addNew:
                // TODO: launch device-creation sheet; for now use a placeholder
                deviceName = "New device"
            case .noSpecificDevice:
                deviceName = "Unspecified device"
            }

            if savedDraftId == nil {
                // First time — create the ticket draft on the server.
                let createReq = CreateTicketRequest(
                    customerId: draft.customerId,
                    devices: [.init(deviceName: deviceName)]
                )
                let created = try await api.createTicket(createReq)
                savedDraftId = created.id
                AppLog.pos.info("RepairFlow: created draft ticket id=\(created.id, privacy: .public)")
            }

            guard let ticketId = savedDraftId else {
                errorMessage = "Failed to save ticket draft. Please try again."
                return
            }

            // Attach / re-attach device row.
            let deviceReq = AddTicketDeviceRequest(deviceName: deviceName)
            let deviceCreated = try await api.addTicketDevice(ticketId: ticketId, deviceReq)
            savedDeviceId = deviceCreated.id
            AppLog.pos.info("RepairFlow: attached device id=\(deviceCreated.id, privacy: .public)")

            currentStep = .describeIssue

        } catch {
            AppLog.pos.error("RepairFlow commitDeviceStep: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not save device. \(error.localizedDescription)"
        }
    }

    /// Patches the ticket with symptom / condition data as a note.
    private func commitSymptomStep() async {
        guard let ticketId = savedDraftId else {
            // Ticket not yet created (e.g. walk-in path that skipped device
            // selection). Fall through to the next step — symptom will be
            // included in the diagnostic note instead.
            currentStep = .diagnosticQuote
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Encode condition + chips into the internal note.
            var noteParts: [String] = []
            if let condition = draft.condition {
                noteParts.append("Condition: \(condition.displayName)")
            }
            if !draft.quickChips.isEmpty {
                let chipLabels = draft.quickChips.map { $0.displayLabel }.sorted().joined(separator: ", ")
                noteParts.append("Symptoms: \(chipLabels)")
            }
            if !draft.symptomText.isEmpty {
                noteParts.append(draft.symptomText)
            }
            if !draft.internalNotes.isEmpty {
                noteParts.append("Internal: \(draft.internalNotes)")
            }
            let noteContent = noteParts.joined(separator: "\n")

            if !noteContent.isEmpty {
                let noteReq = AddTicketNoteRequest(type: "diagnostic", content: noteContent)
                _ = try await api.addTicketNote(ticketId: ticketId, noteReq)
                AppLog.pos.info("RepairFlow: saved symptom note for ticket \(ticketId, privacy: .public)")
            }

            currentStep = .diagnosticQuote

        } catch {
            AppLog.pos.error("RepairFlow commitSymptomStep: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not save symptom. \(error.localizedDescription)"
        }
    }

    /// Saves diagnostic notes as a note on the ticket.
    private func commitQuoteStep() async {
        guard let ticketId = savedDraftId else {
            currentStep = .deposit
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if !draft.diagnosticNotes.isEmpty {
                let noteReq = AddTicketNoteRequest(type: "diagnostic", content: draft.diagnosticNotes)
                _ = try await api.addTicketNote(ticketId: ticketId, noteReq)
                AppLog.pos.info("RepairFlow: saved diagnostic note for ticket \(ticketId, privacy: .public)")
            }

            // Apply default deposit suggestion before advancing.
            if draft.depositCents == 0 && draft.estimateCents > 0 {
                draft = draft.withDeposit(cents: draft.suggestedDepositCents)
            }

            currentStep = .deposit

        } catch {
            AppLog.pos.error("RepairFlow commitQuoteStep: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not save diagnostic quote. \(error.localizedDescription)"
        }
    }

    /// Converts the draft to an invoice once the deposit is tendered.
    private func commitDepositStep() async {
        guard let ticketId = savedDraftId else {
            errorMessage = "No draft ticket found. Please restart the flow."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.convertTicketToInvoice(ticketId: ticketId)
            let resolvedId = response.resolvedInvoiceId ?? ticketId
            invoiceId = resolvedId
            isComplete = true
            AppLog.pos.info("RepairFlow: converted ticket \(ticketId, privacy: .public) → invoice \(resolvedId, privacy: .public)")
            onComplete?(resolvedId)

        } catch {
            AppLog.pos.error("RepairFlow commitDepositStep: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not finalize repair ticket. \(error.localizedDescription)"
        }
    }
}
#endif
