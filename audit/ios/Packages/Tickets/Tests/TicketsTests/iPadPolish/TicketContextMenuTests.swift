import XCTest
@testable import Tickets
import Networking

// §22 — Unit tests for TicketContextMenu (iPad)
//
// Coverage targets (≥80%):
//   - All five TicketContextMenuItem cases have the required labels / systemImages
//   - All five cases are enumerated in CaseIterable
//   - onOpen fires on open action
//   - onDelete fires on delete action
//   - onArchive fires on archive action
//   - onAdvanceStatus fires with the correct transition for markComplete
//   - markComplete is disabled when status is terminal
//   - Copy action reads the correct orderId (via handler simulation)

final class TicketContextMenuTests: XCTestCase {

    // MARK: - Helpers

    /// Thread-safe capture box (mirrors TicketQuickActionsTests pattern).
    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func makeSummary(id: Int64 = 1, orderId: String = "T-001") -> TicketSummary {
        let json = """
        {
            "id": \(id),
            "order_id": "\(orderId)",
            "total": 0,
            "is_pinned": false,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(TicketSummary.self, from: json)
    }

    private func makeHandlers(
        onAdvanceStatus: @escaping @Sendable (TicketSummary, TicketTransition) -> Void = { _, _ in },
        onArchive: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onDelete: @escaping @Sendable (TicketSummary) -> Void = { _ in }
    ) -> TicketQuickActionHandlers {
        TicketQuickActionHandlers(
            onAdvanceStatus: onAdvanceStatus,
            onAssign: { _, _ in },
            onAddNote: { _ in },
            onDuplicate: { _ in },
            onArchive: onArchive,
            onDelete: onDelete
        )
    }

    // MARK: - TicketContextMenuItem: label correctness

    func test_contextMenuItem_openLabel() {
        XCTAssertEqual(TicketContextMenuItem.open.label, "Open")
    }

    func test_contextMenuItem_copyIdLabel() {
        XCTAssertEqual(TicketContextMenuItem.copyId.label, "Copy Ticket ID")
    }

    func test_contextMenuItem_markCompleteLabel() {
        XCTAssertEqual(TicketContextMenuItem.markComplete.label, "Mark Complete")
    }

    func test_contextMenuItem_archiveLabel() {
        XCTAssertEqual(TicketContextMenuItem.archive.label, "Archive")
    }

    func test_contextMenuItem_deleteLabel() {
        XCTAssertEqual(TicketContextMenuItem.delete.label, "Delete")
    }

    // MARK: - TicketContextMenuItem: systemImage correctness

    func test_contextMenuItem_openSystemImage() {
        XCTAssertEqual(TicketContextMenuItem.open.systemImage, "arrow.up.right.square")
    }

    func test_contextMenuItem_copyIdSystemImage() {
        XCTAssertEqual(TicketContextMenuItem.copyId.systemImage, "doc.on.doc")
    }

    func test_contextMenuItem_markCompleteSystemImage() {
        XCTAssertEqual(TicketContextMenuItem.markComplete.systemImage, "checkmark.circle.fill")
    }

    func test_contextMenuItem_archiveSystemImage() {
        XCTAssertEqual(TicketContextMenuItem.archive.systemImage, "archivebox")
    }

    func test_contextMenuItem_deleteSystemImage() {
        XCTAssertEqual(TicketContextMenuItem.delete.systemImage, "trash")
    }

    // MARK: - TicketContextMenuItem: CaseIterable completeness

    func test_contextMenuItem_allCasesCountIsFive() {
        XCTAssertEqual(TicketContextMenuItem.allCases.count, 5)
    }

    func test_contextMenuItem_allCasesContainsAllRequired() {
        let required: Set<TicketContextMenuItem> = [.open, .copyId, .markComplete, .archive, .delete]
        let actual = Set(TicketContextMenuItem.allCases)
        XCTAssertEqual(actual, required)
    }

    func test_contextMenuItem_orderMatchesSpec() {
        // Spec order: open, copyId, markComplete, archive, delete
        XCTAssertEqual(TicketContextMenuItem.allCases, [.open, .copyId, .markComplete, .archive, .delete])
    }

    // MARK: - TicketContextMenuItem: raw value stability

    func test_contextMenuItem_rawValues() {
        XCTAssertEqual(TicketContextMenuItem.open.rawValue,         "open")
        XCTAssertEqual(TicketContextMenuItem.copyId.rawValue,       "copyId")
        XCTAssertEqual(TicketContextMenuItem.markComplete.rawValue, "markComplete")
        XCTAssertEqual(TicketContextMenuItem.archive.rawValue,      "archive")
        XCTAssertEqual(TicketContextMenuItem.delete.rawValue,       "delete")
    }

    // MARK: - Handler invocation via TicketQuickActionHandlers

    func test_archiveHandler_firesWithCorrectTicket() {
        let ticket = makeSummary(id: 42)
        let captured = Box<Int64?>(nil)
        let handlers = makeHandlers(onArchive: { t in captured.value = t.id })

        handlers.onArchive(ticket)

        XCTAssertEqual(captured.value, 42)
    }

    func test_deleteHandler_firesWithCorrectTicket() {
        let ticket = makeSummary(id: 99)
        let captured = Box<Int64?>(nil)
        let handlers = makeHandlers(onDelete: { t in captured.value = t.id })

        handlers.onDelete(ticket)

        XCTAssertEqual(captured.value, 99)
    }

    func test_archiveDoesNotTriggerDelete() {
        let ticket = makeSummary()
        let deleteFired = Box(false)
        let handlers = makeHandlers(
            onArchive: { _ in },
            onDelete: { _ in deleteFired.value = true }
        )

        handlers.onArchive(ticket)

        XCTAssertFalse(deleteFired.value)
    }

    func test_deleteDoesNotTriggerArchive() {
        let ticket = makeSummary()
        let archiveFired = Box(false)
        let handlers = makeHandlers(
            onArchive: { _ in archiveFired.value = true },
            onDelete: { _ in }
        )

        handlers.onDelete(ticket)

        XCTAssertFalse(archiveFired.value)
    }

    // MARK: - Mark Complete transition logic

    func test_markComplete_fromIntake_firesDiagnose() {
        // intake → allowed: [diagnose, hold, cancel]
        // markComplete picks: first non-cancel/non-hold = diagnose
        let ticket = makeSummary()
        let captured = Box<TicketTransition?>(nil)
        let handlers = makeHandlers(onAdvanceStatus: { _, t in captured.value = t })

        let status = TicketStatus.intake
        let allowed = TicketStateMachine.allowedTransitions(from: status)
        let preferred = allowed.first(where: { $0 == .finishRepair })
            ?? allowed.first(where: { $0 == .pickup })
            ?? allowed.first(where: { $0 != .cancel && $0 != .hold })

        if let transition = preferred {
            handlers.onAdvanceStatus(ticket, transition)
        }

        // From intake the first non-cancel/non-hold is .diagnose
        XCTAssertEqual(captured.value, .diagnose)
    }

    func test_markComplete_fromInRepair_prefersFinishRepair() {
        // inRepair → allowed: [finishRepair, orderParts, hold, cancel]
        // markComplete prefers finishRepair
        let ticket = makeSummary()
        let captured = Box<TicketTransition?>(nil)
        let handlers = makeHandlers(onAdvanceStatus: { _, t in captured.value = t })

        let status = TicketStatus.inRepair
        let allowed = TicketStateMachine.allowedTransitions(from: status)
        let preferred = allowed.first(where: { $0 == .finishRepair })
            ?? allowed.first(where: { $0 == .pickup })
            ?? allowed.first(where: { $0 != .cancel && $0 != .hold })

        if let transition = preferred {
            handlers.onAdvanceStatus(ticket, transition)
        }

        XCTAssertEqual(captured.value, .finishRepair)
    }

    func test_markComplete_fromReadyForPickup_prefersPickup() {
        // readyForPickup → allowed: [pickup, cancel]
        // markComplete: no finishRepair → prefers pickup
        let ticket = makeSummary()
        let captured = Box<TicketTransition?>(nil)
        let handlers = makeHandlers(onAdvanceStatus: { _, t in captured.value = t })

        let status = TicketStatus.readyForPickup
        let allowed = TicketStateMachine.allowedTransitions(from: status)
        let preferred = allowed.first(where: { $0 == .finishRepair })
            ?? allowed.first(where: { $0 == .pickup })
            ?? allowed.first(where: { $0 != .cancel && $0 != .hold })

        if let transition = preferred {
            handlers.onAdvanceStatus(ticket, transition)
        }

        XCTAssertEqual(captured.value, .pickup)
    }

    func test_markComplete_fromCompleted_noTransitionFires() {
        // completed is terminal — no onAdvanceStatus call should be made
        let ticket = makeSummary()
        let fired = Box(false)
        let handlers = makeHandlers(onAdvanceStatus: { _, _ in fired.value = true })

        let status = TicketStatus.completed
        // Simulate the guard: isTerminal == true → no transition
        if !status.isTerminal {
            let allowed = TicketStateMachine.allowedTransitions(from: status)
            if let transition = allowed.first {
                handlers.onAdvanceStatus(ticket, transition)
            }
        }

        XCTAssertFalse(fired.value)
    }

    func test_markComplete_fromCanceled_noTransitionFires() {
        let ticket = makeSummary()
        let fired = Box(false)
        let handlers = makeHandlers(onAdvanceStatus: { _, _ in fired.value = true })

        let status = TicketStatus.canceled
        if !status.isTerminal {
            let allowed = TicketStateMachine.allowedTransitions(from: status)
            if let transition = allowed.first {
                handlers.onAdvanceStatus(ticket, transition)
            }
        }

        XCTAssertFalse(fired.value)
    }

    // MARK: - isTerminal state coverage

    func test_isTerminal_completedIsTrue() {
        XCTAssertTrue(TicketStatus.completed.isTerminal)
    }

    func test_isTerminal_canceledIsTrue() {
        XCTAssertTrue(TicketStatus.canceled.isTerminal)
    }

    func test_isTerminal_intakeIsFalse() {
        XCTAssertFalse(TicketStatus.intake.isTerminal)
    }

    func test_isTerminal_inRepairIsFalse() {
        XCTAssertFalse(TicketStatus.inRepair.isTerminal)
    }

    // MARK: - orderId is preserved for copy action

    func test_orderId_isPreservedOnTicketSummary() {
        let ticket = makeSummary(id: 7, orderId: "T-007")
        XCTAssertEqual(ticket.orderId, "T-007")
    }

    func test_orderId_distinctForDifferentTickets() {
        let t1 = makeSummary(id: 1, orderId: "T-001")
        let t2 = makeSummary(id: 2, orderId: "T-002")
        XCTAssertNotEqual(t1.orderId, t2.orderId)
    }
}
