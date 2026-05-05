import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsListFilterTests
//
// §12.1 Filters — unit tests for SmsListFilter.apply(to:).

final class SmsListFilterTests: XCTestCase {

    // MARK: - Fixtures

    static let archived  = SmsConversation.fixture(phone: "+10001", isArchived: true)
    static let unread    = SmsConversation.fixture(phone: "+10002", unreadCount: 3)
    static let flagged   = SmsConversation.fixture(phone: "+10003", isFlagged: true)
    static let pinned    = SmsConversation.fixture(phone: "+10004", isPinned: true)
    static let plain     = SmsConversation.fixture(phone: "+10005")
    static let all: [SmsConversation] = [archived, unread, flagged, pinned, plain]

    // MARK: - Tab: All

    func testAllFilterExcludesArchived() {
        let filter = SmsListFilter(tab: .all)
        let result = filter.apply(to: Self.all)
        XCTAssertFalse(result.contains(Self.archived), "All tab should exclude archived")
        XCTAssertEqual(result.count, 4)
    }

    // MARK: - Tab: Unread

    func testUnreadFilterIncludesOnlyUnreadNonArchived() {
        let filter = SmsListFilter(tab: .unread)
        let result = filter.apply(to: Self.all)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.convPhone, "+10002")
    }

    func testUnreadFilterExcludesArchivedUnread() {
        let archivedUnread = SmsConversation.fixture(phone: "+10099", unreadCount: 1, isArchived: true)
        let filter = SmsListFilter(tab: .unread)
        let result = filter.apply(to: [archivedUnread])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Tab: Flagged

    func testFlaggedFilterIncludesOnlyFlaggedNonArchived() {
        let filter = SmsListFilter(tab: .flagged)
        let result = filter.apply(to: Self.all)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.convPhone, "+10003")
    }

    // MARK: - Tab: Pinned

    func testPinnedFilterIncludesOnlyPinnedNonArchived() {
        let filter = SmsListFilter(tab: .pinned)
        let result = filter.apply(to: Self.all)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.convPhone, "+10004")
    }

    // MARK: - Tab: Archived

    func testArchivedFilterIncludesOnlyArchived() {
        let filter = SmsListFilter(tab: .archived)
        let result = filter.apply(to: Self.all)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.convPhone, "+10001")
    }

    // MARK: - isDefault

    func testDefaultFilter() {
        let filter = SmsListFilter(tab: .all)
        XCTAssertTrue(filter.isDefault)
    }

    func testNonDefaultFilter() {
        let filter = SmsListFilter(tab: .unread)
        XCTAssertFalse(filter.isDefault)
    }

    // MARK: - Edge cases

    func testEmptyConversationList() {
        let filter = SmsListFilter(tab: .all)
        let result = filter.apply(to: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAllTabWithMixedConversations() {
        let filter = SmsListFilter(tab: .all)
        let result = filter.apply(to: Self.all)
        // Includes unread, flagged, pinned, plain. Excludes archived.
        XCTAssertTrue(result.contains(Self.unread))
        XCTAssertTrue(result.contains(Self.flagged))
        XCTAssertTrue(result.contains(Self.pinned))
        XCTAssertTrue(result.contains(Self.plain))
        XCTAssertFalse(result.contains(Self.archived))
    }
}

// MARK: - Extended SmsConversation fixture helper for filter tests

extension SmsConversation {
    static func fixture(
        phone: String,
        unreadCount: Int = 0,
        isFlagged: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false
    ) -> SmsConversation {
        SmsConversation(
            convPhone: phone,
            lastMessageAt: nil,
            lastMessage: nil,
            lastDirection: nil,
            messageCount: 1,
            unreadCount: unreadCount,
            isFlagged: isFlagged,
            isPinned: isPinned,
            isArchived: isArchived,
            customer: nil,
            recentTicket: nil
        )
    }
}
