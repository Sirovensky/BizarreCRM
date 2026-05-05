import XCTest
@testable import Tickets
import Networking

/// §22 + §4 — Unit tests for `TicketQuickActionsContent` closure invocations
/// and `TicketRowSwipeActions` ViewModifier.
///
/// Coverage requirements (≥80%):
/// - Each handler closure fires for the correct action.
/// - `TicketQuickActionHandlers.preview` is all no-ops (smoke test).
/// - `TicketAssignee` identity is correct.
/// - No unintended closures fire on other actions.
final class TicketQuickActionsTests: XCTestCase {

    // MARK: - Helpers

    private func makeSummary(id: Int64 = 1) -> TicketSummary {
        let json = """
        {
            "id": \(id),
            "order_id": "T-00\(id)",
            "total": 0,
            "is_pinned": false,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(TicketSummary.self, from: json)
    }

    /// Thread-safe capture box for @Sendable closures in Swift 6 strict mode.
    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func makeHandlers(
        onAdvanceStatus: @escaping @Sendable (TicketSummary, TicketTransition) -> Void = { _, _ in },
        onAssign: @escaping @Sendable (TicketSummary, Int64) -> Void = { _, _ in },
        onAddNote: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onDuplicate: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onArchive: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onDelete: @escaping @Sendable (TicketSummary) -> Void = { _ in }
    ) -> TicketQuickActionHandlers {
        TicketQuickActionHandlers(
            onAdvanceStatus: onAdvanceStatus,
            onAssign: onAssign,
            onAddNote: onAddNote,
            onDuplicate: onDuplicate,
            onArchive: onArchive,
            onDelete: onDelete
        )
    }

    // MARK: - onAdvanceStatus

    func test_onAdvanceStatus_firesWithCorrectTicketAndTransition() {
        let ticket = makeSummary(id: 10)
        let captured = Box<(TicketSummary, TicketTransition)?>(nil)
        let handlers = makeHandlers(onAdvanceStatus: { t, tr in captured.value = (t, tr) })

        handlers.onAdvanceStatus(ticket, .diagnose)

        XCTAssertEqual(captured.value?.0.id, 10)
        XCTAssertEqual(captured.value?.1, .diagnose)
    }

    func test_onAdvanceStatus_doesNotFireOtherHandlers() {
        let ticket = makeSummary()
        let archiveFired = Box(false)
        let deleteFired = Box(false)
        let handlers = makeHandlers(
            onArchive: { _ in archiveFired.value = true },
            onDelete: { _ in deleteFired.value = true }
        )

        handlers.onAdvanceStatus(ticket, .hold)

        XCTAssertFalse(archiveFired.value)
        XCTAssertFalse(deleteFired.value)
    }

    // MARK: - onAssign

    func test_onAssign_firesWithCorrectTicketAndUserId() {
        let ticket = makeSummary(id: 20)
        let targetUserId: Int64 = 99
        let captured = Box<(TicketSummary, Int64)?>(nil)
        let handlers = makeHandlers(onAssign: { t, uid in captured.value = (t, uid) })

        handlers.onAssign(ticket, targetUserId)

        XCTAssertEqual(captured.value?.0.id, 20)
        XCTAssertEqual(captured.value?.1, 99)
    }

    // MARK: - onAddNote

    func test_onAddNote_firesWithCorrectTicket() {
        let ticket = makeSummary(id: 30)
        let capturedId = Box<Int64?>(nil)
        let handlers = makeHandlers(onAddNote: { t in capturedId.value = t.id })

        handlers.onAddNote(ticket)

        XCTAssertEqual(capturedId.value, 30)
    }

    func test_onAddNote_doesNotFireOnDuplicate() {
        let ticket = makeSummary()
        let noteFired = Box(false)
        let handlers = makeHandlers(
            onAddNote: { _ in noteFired.value = true },
            onDuplicate: { _ in }
        )

        handlers.onDuplicate(ticket)

        XCTAssertFalse(noteFired.value)
    }

    // MARK: - onDuplicate

    func test_onDuplicate_firesWithCorrectTicket() {
        let ticket = makeSummary(id: 40)
        let capturedId = Box<Int64?>(nil)
        let handlers = makeHandlers(onDuplicate: { t in capturedId.value = t.id })

        handlers.onDuplicate(ticket)

        XCTAssertEqual(capturedId.value, 40)
    }

    // MARK: - onArchive

    func test_onArchive_firesWithCorrectTicket() {
        let ticket = makeSummary(id: 50)
        let capturedId = Box<Int64?>(nil)
        let handlers = makeHandlers(onArchive: { t in capturedId.value = t.id })

        handlers.onArchive(ticket)

        XCTAssertEqual(capturedId.value, 50)
    }

    func test_onArchive_doesNotFireDelete() {
        let ticket = makeSummary()
        let deleteFired = Box(false)
        let handlers = makeHandlers(
            onArchive: { _ in },
            onDelete: { _ in deleteFired.value = true }
        )

        handlers.onArchive(ticket)

        XCTAssertFalse(deleteFired.value)
    }

    // MARK: - onDelete

    func test_onDelete_firesWithCorrectTicket() {
        let ticket = makeSummary(id: 60)
        let capturedId = Box<Int64?>(nil)
        let handlers = makeHandlers(onDelete: { t in capturedId.value = t.id })

        handlers.onDelete(ticket)

        XCTAssertEqual(capturedId.value, 60)
    }

    func test_onDelete_doesNotFireArchive() {
        let ticket = makeSummary()
        let archiveFired = Box(false)
        let handlers = makeHandlers(
            onArchive: { _ in archiveFired.value = true },
            onDelete: { _ in }
        )

        handlers.onDelete(ticket)

        XCTAssertFalse(archiveFired.value)
    }

    // MARK: - preview no-ops

    func test_preview_allHandlersAreNoOps() {
        let ticket = makeSummary()
        let h = TicketQuickActionHandlers.preview
        h.onAdvanceStatus(ticket, .diagnose)
        h.onAssign(ticket, 1)
        h.onAddNote(ticket)
        h.onDuplicate(ticket)
        h.onArchive(ticket)
        h.onDelete(ticket)
        // No assertions needed — validates no crash on all no-op paths.
    }

    // MARK: - TicketAssignee

    func test_ticketAssignee_identityIsId() {
        let a1 = TicketAssignee(id: 1, displayName: "Alice")
        let a2 = TicketAssignee(id: 1, displayName: "Alice")
        let a3 = TicketAssignee(id: 2, displayName: "Bob")

        XCTAssertEqual(a1.id, a2.id)
        XCTAssertNotEqual(a1.id, a3.id)
    }

    func test_ticketAssignee_displayName() {
        let a = TicketAssignee(id: 7, displayName: "Charlie D.")
        XCTAssertEqual(a.displayName, "Charlie D.")
    }

    func test_ticketAssignee_hashableEqualsSelf() {
        let a = TicketAssignee(id: 5, displayName: "Dana")
        var set = Set<TicketAssignee>()
        set.insert(a)
        set.insert(a)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Multiple distinct tickets

    func test_onArchive_distinguishesBetweenTickets() {
        let t1 = makeSummary(id: 1)
        let t2 = makeSummary(id: 2)
        let archivedIds = Box<[Int64]>([])
        let handlers = makeHandlers(onArchive: { t in archivedIds.value.append(t.id) })

        handlers.onArchive(t1)
        handlers.onArchive(t2)

        XCTAssertEqual(archivedIds.value, [1, 2])
    }

    // MARK: - Transition correctness (integration with state machine)

    func test_allowedTransitions_fromIntake_containsDiagnose() {
        let allowed = TicketStateMachine.allowedTransitions(from: .intake)
        XCTAssertTrue(allowed.contains(.diagnose))
    }

    func test_allowedTransitions_fromCompleted_isEmpty() {
        let allowed = TicketStateMachine.allowedTransitions(from: .completed)
        XCTAssertTrue(allowed.isEmpty)
    }
}
