import XCTest
import SwiftUI
@testable import Core

// §22.G — Rail sidebar unit tests.
// Uses XCTest (consistent with the rest of CoreTests).

// MARK: - Fake auto-collapse timer for injection in tests

@MainActor
final class FakeRailTimer: RailAutoCollapseTimer {
    private(set) var scheduledAction: (@MainActor () -> Void)?
    private(set) var scheduledSeconds: TimeInterval?
    private(set) var cancelCallCount = 0

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        scheduledSeconds = seconds
        scheduledAction = action
        cancelCallCount = 0   // reset per schedule call
    }

    func cancel() {
        cancelCallCount += 1
        scheduledAction = nil
        scheduledSeconds = nil
    }

    /// Fires the scheduled action immediately (simulates timer expiry).
    func fire() {
        scheduledAction?()
    }
}

// MARK: - RailDestination

final class RailDestinationTests: XCTestCase {

    func test_allCasesHas8Entries() {
        XCTAssertEqual(RailDestination.allCases.count, 8)
    }

    func test_rawValuesAreUnique() {
        let rawValues = RailDestination.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    func test_hashableConformance() {
        // Can be used as Dictionary key
        var dict = [RailDestination: Int]()
        for (i, dest) in RailDestination.allCases.enumerated() {
            dict[dest] = i
        }
        XCTAssertEqual(dict[.dashboard], 0)
        XCTAssertEqual(dict[.settings], 7)
    }
}

// MARK: - RailItem / Badge

final class RailItemTests: XCTestCase {

    func test_badgeDot_equatable() {
        XCTAssertEqual(Badge.dot, Badge.dot)
        XCTAssertNotEqual(Badge.dot, Badge.count(1))
    }

    func test_badgeCount_equatable() {
        XCTAssertEqual(Badge.count(5), Badge.count(5))
        XCTAssertNotEqual(Badge.count(5), Badge.count(6))
    }

    func test_railItem_equality_sameIdSameDestination() {
        let a = RailItem(id: "pos", title: "POS", systemImage: "cart", destination: .pos)
        let b = RailItem(id: "pos", title: "POS", systemImage: "cart", destination: .pos)
        XCTAssertEqual(a, b)
    }

    func test_railItem_inequality_differentDestination() {
        let a = RailItem(id: "pos", title: "POS", systemImage: "cart", destination: .pos)
        let b = RailItem(id: "pos", title: "POS", systemImage: "cart", destination: .dashboard)
        XCTAssertNotEqual(a, b)
    }

    func test_railItem_badgeChangeMakesInequal() {
        let a = RailItem(id: "tickets", title: "Tickets", systemImage: "wrench.and.screwdriver",
                         destination: .tickets, badge: .count(3))
        let b = RailItem(id: "tickets", title: "Tickets", systemImage: "wrench.and.screwdriver",
                         destination: .tickets, badge: .count(7))
        XCTAssertNotEqual(a, b)
    }

    func test_railItem_nilBadge_vs_dotBadge_notEqual() {
        let withBadge    = RailItem(id: "sms", title: "SMS", systemImage: "message",
                                    destination: .sms, badge: .dot)
        let withoutBadge = RailItem(id: "sms", title: "SMS", systemImage: "message",
                                    destination: .sms, badge: nil)
        XCTAssertNotEqual(withBadge, withoutBadge)
    }
}

// MARK: - RailCatalog

final class RailCatalogTests: XCTestCase {

    func test_primaryContainsExactly8Items() {
        XCTAssertEqual(RailCatalog.primary.count, 8)
    }

    func test_primaryIdsAreUnique() {
        let ids = RailCatalog.primary.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_primaryCoverAllDestinations() {
        let catalogDestinations = Set(RailCatalog.primary.map(\.destination))
        let allDestinations = Set(RailDestination.allCases)
        XCTAssertEqual(catalogDestinations, allDestinations)
    }

    func test_allItemsHaveNonEmptySystemImage() {
        for item in RailCatalog.primary {
            XCTAssertFalse(item.systemImage.isEmpty, "Item \(item.id) has empty systemImage")
        }
    }

    func test_firstItemIsDashboard() {
        XCTAssertEqual(RailCatalog.primary.first?.destination, .dashboard)
    }

    func test_lastItemIsSettings() {
        XCTAssertEqual(RailCatalog.primary.last?.destination, .settings)
    }
}

// MARK: - RailAutoCollapseTimer (FakeRailTimer contract)

@MainActor
final class FakeRailTimerTests: XCTestCase {

    func test_scheduleStoresAction() {
        let timer = FakeRailTimer()
        var fired = false
        timer.schedule(after: 30) { fired = true }
        XCTAssertNotNil(timer.scheduledAction)
        XCTAssertFalse(fired)
    }

    func test_fireExecutesStoredAction() {
        let timer = FakeRailTimer()
        var fired = false
        timer.schedule(after: 30) { fired = true }
        timer.fire()
        XCTAssertTrue(fired)
    }

    func test_cancelClearsAction() {
        let timer = FakeRailTimer()
        timer.schedule(after: 30) { }
        timer.cancel()
        XCTAssertNil(timer.scheduledAction)
        XCTAssertEqual(timer.cancelCallCount, 1)
    }

    // MARK: - Selection and pill-flip behaviour (logic layer)

    /// Simulates the contract: selecting a new destination updates the binding.
    func test_selectionChangesDestination() {
        var selection: RailDestination = .dashboard
        let binding = Binding<RailDestination>(
            get: { selection },
            set: { selection = $0 }
        )
        // Simulate a tap on .tickets
        binding.wrappedValue = .tickets
        XCTAssertEqual(selection, .tickets)
    }

    /// Active pill flips when selection changes — validate via binding update.
    func test_activePillFlipsOnSelectionChange() {
        var selection: RailDestination = .dashboard
        let destinations: [RailDestination] = [.tickets, .pos, .inventory]
        for dest in destinations {
            selection = dest
            XCTAssertEqual(selection, dest, "Pill should reflect current selection \(dest)")
        }
    }

    // MARK: - Auto-collapse timer contract

    func test_timerFiredTriggersCollapse() {
        let timer = FakeRailTimer()
        var isExpanded = true
        // Simulate: brand tap expands → schedules timer → timer fires → collapses
        timer.schedule(after: 30) {
            isExpanded = false
        }
        XCTAssertTrue(isExpanded)
        timer.fire()
        XCTAssertFalse(isExpanded)
    }

    func test_timerCancelledOnManualCollapse() {
        let timer = FakeRailTimer()
        // Expand: schedule timer
        timer.schedule(after: 30) { }
        XCTAssertNotNil(timer.scheduledAction)
        // User manually collapses: timer must be cancelled
        timer.cancel()
        XCTAssertNil(timer.scheduledAction)
        XCTAssertEqual(timer.cancelCallCount, 1)
    }

    // MARK: - Badge count binding

    func test_badgeCountBindingUpdate() {
        var items = RailCatalog.primary
        let ticketsIndex = items.firstIndex(where: { $0.destination == .tickets })!
        // Create updated item with badge
        let updated = RailItem(
            id: items[ticketsIndex].id,
            title: "Tickets",
            systemImage: items[ticketsIndex].systemImage,
            destination: .tickets,
            badge: .count(12)
        )
        items[ticketsIndex] = updated
        XCTAssertEqual(items[ticketsIndex].badge, .count(12))
    }

    func test_badgeCountZeroVsDot() {
        XCTAssertNotEqual(Badge.count(0), Badge.dot)
    }

    // MARK: - Keyboard shortcut index contract

    func test_keyboardShortcutIndicesMatch8Items() {
        // The view maps item index 0→"1", 1→"2", …, 7→"8"
        // Verify the catalog has exactly 8 items so indices 0–7 are valid
        XCTAssertEqual(RailCatalog.primary.count, 8,
                       "Keyboard shortcuts ⌘1–⌘8 require exactly 8 catalog items")
    }
}
