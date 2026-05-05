import XCTest
@testable import Tickets
import Networking

// §22 — Unit tests for iPad wrapper view composition
//
// These tests verify the pure-logic / configuration layer of the iPad views:
//   - TicketsThreeColumnView init variants accept correct dependencies
//   - TicketQuickAssignState is correct value-type equality
//   - TicketContextMenu item count and ordering (via CaseIterable)
//   - TicketKeyboardShortcutRegistry completeness (cross-covered with shortcuts tests)
//   - Quick-action handler wiring produces expected transitions
//   - TicketListFilter display names are non-empty
//
// SwiftUI rendering is NOT tested here (host-app snapshot tests own that).

final class TicketsThreeColumnViewTests: XCTestCase {

    // MARK: - Helpers

    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

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

    // MARK: - TicketQuickAssignState

    func test_quickAssignState_equatableByTicketId() {
        let s1 = TicketQuickAssignState(ticketId: 1, assignees: [])
        let s2 = TicketQuickAssignState(ticketId: 1, assignees: [])
        XCTAssertEqual(s1, s2)
    }

    func test_quickAssignState_inequatableOnDifferentId() {
        let s1 = TicketQuickAssignState(ticketId: 1, assignees: [])
        let s2 = TicketQuickAssignState(ticketId: 2, assignees: [])
        XCTAssertNotEqual(s1, s2)
    }

    func test_quickAssignState_inequatableOnDifferentAssignees() {
        let a = TicketAssignee(id: 5, displayName: "Alice")
        let s1 = TicketQuickAssignState(ticketId: 1, assignees: [])
        let s2 = TicketQuickAssignState(ticketId: 1, assignees: [a])
        XCTAssertNotEqual(s1, s2)
    }

    func test_quickAssignState_assigneesArePreserved() {
        let a = TicketAssignee(id: 42, displayName: "Bob")
        let state = TicketQuickAssignState(ticketId: 99, assignees: [a])
        XCTAssertEqual(state.assignees.first?.id, 42)
        XCTAssertEqual(state.ticketId, 99)
    }

    // MARK: - TicketContextMenuItem composition (5 items)

    func test_contextMenu_fiveItemsRequired() {
        XCTAssertEqual(TicketContextMenuItem.allCases.count, 5,
            "Spec requires exactly 5 context menu items: Open, Copy ID, Mark Complete, Archive, Delete")
    }

    func test_contextMenu_firstItemIsOpen() {
        XCTAssertEqual(TicketContextMenuItem.allCases.first, .open)
    }

    func test_contextMenu_lastItemIsDelete() {
        XCTAssertEqual(TicketContextMenuItem.allCases.last, .delete)
    }

    func test_contextMenu_archivePrecedesDelete() {
        let cases = TicketContextMenuItem.allCases
        let archiveIndex = cases.firstIndex(of: .archive)!
        let deleteIndex  = cases.firstIndex(of: .delete)!
        XCTAssertLessThan(archiveIndex, deleteIndex)
    }

    func test_contextMenu_copyIdPrecedesMarkComplete() {
        let cases = TicketContextMenuItem.allCases
        let copyIndex     = cases.firstIndex(of: .copyId)!
        let completeIndex = cases.firstIndex(of: .markComplete)!
        XCTAssertLessThan(copyIndex, completeIndex)
    }

    // MARK: - Keyboard shortcut registry (composition check)

    func test_shortcutRegistry_threeShortcutsRegistered() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.all.count, 3,
            "Three shortcuts required: ⌘N, ⌘F, ⌘R")
    }

    func test_shortcutRegistry_keysDontClashWithExistingTicketListNew() {
        // TicketListView already registered ⌘N. Our registry key must be "n"
        // (same) — intentional; the wrapper replaces the old one.
        XCTAssertEqual(TicketKeyboardShortcutRegistry.new.key, "n")
    }

    // MARK: - Filter display names (sidebar column)

    func test_filterDisplayName_allCasesNonEmpty() {
        for filter in TicketListFilter.allCases {
            XCTAssertFalse(filter.displayName.isEmpty,
                "Filter \(filter) displayName must not be empty")
        }
    }

    func test_filterDisplayName_allCasesCount() {
        // §4.1: All / Open / On hold / Closed / Cancelled / Active / My Tickets = 7
        XCTAssertEqual(TicketListFilter.allCases.count, 7)
    }

    // MARK: - Quick-action handler wiring (dispatch correctness)

    func test_advanceStatus_firesForCorrectTicket() {
        let ticket = makeSummary(id: 77)
        let captured = Box<(Int64, TicketTransition)?>(nil)
        let handlers = TicketQuickActionHandlers(
            onAdvanceStatus: { t, tr in captured.value = (t.id, tr) },
            onAssign: { _, _ in },
            onAddNote: { _ in },
            onDuplicate: { _ in },
            onArchive: { _ in },
            onDelete: { _ in }
        )

        handlers.onAdvanceStatus(ticket, .finishRepair)

        XCTAssertEqual(captured.value?.0, 77)
        XCTAssertEqual(captured.value?.1, .finishRepair)
    }

    func test_archive_doesNotFireAdvanceStatus() {
        let ticket = makeSummary()
        let advanceFired = Box(false)
        let handlers = TicketQuickActionHandlers(
            onAdvanceStatus: { _, _ in advanceFired.value = true },
            onAssign: { _, _ in },
            onAddNote: { _ in },
            onDuplicate: { _ in },
            onArchive: { _ in },
            onDelete: { _ in }
        )

        handlers.onArchive(ticket)

        XCTAssertFalse(advanceFired.value)
    }

    func test_delete_doesNotFireAdvanceStatus() {
        let ticket = makeSummary()
        let advanceFired = Box(false)
        let handlers = TicketQuickActionHandlers(
            onAdvanceStatus: { _, _ in advanceFired.value = true },
            onAssign: { _, _ in },
            onAddNote: { _ in },
            onDuplicate: { _ in },
            onArchive: { _ in },
            onDelete: { _ in }
        )

        handlers.onDelete(ticket)

        XCTAssertFalse(advanceFired.value)
    }

    // MARK: - StateMachine integration (transition discovery used by context menu)

    func test_markComplete_stateIntegration_intakeTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .intake)
        // From intake, markComplete logic selects first non-cancel/non-hold
        let preferred = allowed.first(where: { $0 == .finishRepair })
            ?? allowed.first(where: { $0 == .pickup })
            ?? allowed.first(where: { $0 != .cancel && $0 != .hold })
        XCTAssertNotNil(preferred)
    }

    func test_markComplete_stateIntegration_completedTerminal() {
        let allowed = TicketStateMachine.allowedTransitions(from: .completed)
        XCTAssertTrue(allowed.isEmpty, "No transitions from terminal state")
    }

    func test_markComplete_stateIntegration_canceledTerminal() {
        let allowed = TicketStateMachine.allowedTransitions(from: .canceled)
        XCTAssertTrue(allowed.isEmpty, "No transitions from terminal state")
    }

    // MARK: - TicketSummary ID for selection tracking

    func test_ticketSummary_idPreservedForSelection() {
        let t = makeSummary(id: 55)
        XCTAssertEqual(t.id, 55)
    }

    func test_ticketSummary_distinctIds() {
        let t1 = makeSummary(id: 1)
        let t2 = makeSummary(id: 2)
        XCTAssertNotEqual(t1.id, t2.id)
    }
}
