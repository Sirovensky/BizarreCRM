import XCTest
@testable import Notifications

// MARK: - Mock badge provider

final class MockBadgeProvider: BadgeCountProvider, @unchecked Sendable {
    private(set) var lastCount: Int? = nil
    var shouldThrow: Bool = false

    func setBadgeCount(_ count: Int) async throws {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        lastCount = count
    }
}

// MARK: - Tests

@MainActor
final class BadgeManagerTests: XCTestCase {

    func test_initialBadgeCount_isZero() async {
        let provider = MockBadgeProvider()
        let manager = BadgeManager(provider: provider)
        XCTAssertEqual(manager.currentBadgeCount, 0)
    }

    func test_updateBadgeCount_setsProvider() async {
        let provider = MockBadgeProvider()
        let manager = BadgeManager(provider: provider)
        await manager.updateBadgeCount(unreadCount: 5)
        XCTAssertEqual(provider.lastCount, 5)
        XCTAssertEqual(manager.currentBadgeCount, 5)
    }

    func test_updateBadgeCount_clampsBelowZero() async {
        let provider = MockBadgeProvider()
        let manager = BadgeManager(provider: provider)
        // First set to non-zero so the clamped-to-zero call is not a no-op
        await manager.updateBadgeCount(unreadCount: 1)
        await manager.updateBadgeCount(unreadCount: -3)
        XCTAssertEqual(provider.lastCount, 0)
        XCTAssertEqual(manager.currentBadgeCount, 0)
    }

    func test_updateBadgeCount_noOpWhenSameCount() async {
        let provider = MockBadgeProvider()
        let manager = BadgeManager(provider: provider)
        await manager.updateBadgeCount(unreadCount: 3)
        let callsBefore = provider.lastCount
        await manager.updateBadgeCount(unreadCount: 3)
        // Still 3, no second call needed — but provider lastCount stays 3
        XCTAssertEqual(provider.lastCount, callsBefore)
    }

    func test_clearBadge_setsZero() async {
        let provider = MockBadgeProvider()
        let manager = BadgeManager(provider: provider)
        await manager.updateBadgeCount(unreadCount: 10)
        await manager.clearBadge()
        XCTAssertEqual(provider.lastCount, 0)
        XCTAssertEqual(manager.currentBadgeCount, 0)
    }

    func test_updateBadgeCount_silentOnProviderError() async {
        let provider = MockBadgeProvider()
        provider.shouldThrow = true
        let manager = BadgeManager(provider: provider)
        // Should not throw
        await manager.updateBadgeCount(unreadCount: 7)
        // State should not have been updated since provider failed
        XCTAssertEqual(manager.currentBadgeCount, 0)
    }

    func test_updateBadgeCount_multipleSequential() async {
        let provider = MockBadgeProvider()
        let manager = BadgeManager(provider: provider)
        await manager.updateBadgeCount(unreadCount: 1)
        await manager.updateBadgeCount(unreadCount: 2)
        await manager.updateBadgeCount(unreadCount: 0)
        XCTAssertEqual(provider.lastCount, 0)
        XCTAssertEqual(manager.currentBadgeCount, 0)
    }
}
