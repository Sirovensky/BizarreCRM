import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsFolderTests
//
// Unit tests for SmsFolder filter logic (§22 iPad polish).
// These run headless — no UI or async I/O needed.

final class SmsFolderTests: XCTestCase {

    // MARK: - Fixtures

    private func makeConversation(
        phone: String = "+10005550000",
        isFlagged: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        unreadCount: Int = 0
    ) -> SmsConversation {
        SmsConversation(
            convPhone: phone,
            lastMessageAt: "2026-04-23T10:00:00Z",
            lastMessage: "Hello",
            lastDirection: "inbound",
            messageCount: 1,
            unreadCount: unreadCount,
            isFlagged: isFlagged,
            isPinned: isPinned,
            isArchived: isArchived
        )
    }

    // MARK: - .all folder

    func test_allFolder_includesNonArchivedConversations() {
        let conv = makeConversation()
        XCTAssertTrue(SmsFolder.all.matches(conv))
    }

    func test_allFolder_excludesArchivedConversations() {
        let conv = makeConversation(isArchived: true)
        XCTAssertFalse(SmsFolder.all.matches(conv))
    }

    func test_allFolder_includesFlaggedNonArchived() {
        let conv = makeConversation(isFlagged: true)
        XCTAssertTrue(SmsFolder.all.matches(conv))
    }

    func test_allFolder_includesPinnedNonArchived() {
        let conv = makeConversation(isPinned: true)
        XCTAssertTrue(SmsFolder.all.matches(conv))
    }

    // MARK: - .flagged folder

    func test_flaggedFolder_matchesFlaggedNonArchived() {
        let conv = makeConversation(isFlagged: true)
        XCTAssertTrue(SmsFolder.flagged.matches(conv))
    }

    func test_flaggedFolder_excludesUnflagged() {
        let conv = makeConversation(isFlagged: false)
        XCTAssertFalse(SmsFolder.flagged.matches(conv))
    }

    func test_flaggedFolder_excludesFlaggedButArchived() {
        let conv = makeConversation(isFlagged: true, isArchived: true)
        XCTAssertFalse(SmsFolder.flagged.matches(conv))
    }

    // MARK: - .pinned folder

    func test_pinnedFolder_matchesPinnedNonArchived() {
        let conv = makeConversation(isPinned: true)
        XCTAssertTrue(SmsFolder.pinned.matches(conv))
    }

    func test_pinnedFolder_excludesUnpinned() {
        let conv = makeConversation(isPinned: false)
        XCTAssertFalse(SmsFolder.pinned.matches(conv))
    }

    func test_pinnedFolder_excludesPinnedButArchived() {
        let conv = makeConversation(isPinned: true, isArchived: true)
        XCTAssertFalse(SmsFolder.pinned.matches(conv))
    }

    // MARK: - .archived folder

    func test_archivedFolder_matchesArchivedConversations() {
        let conv = makeConversation(isArchived: true)
        XCTAssertTrue(SmsFolder.archived.matches(conv))
    }

    func test_archivedFolder_excludesNonArchived() {
        let conv = makeConversation(isArchived: false)
        XCTAssertFalse(SmsFolder.archived.matches(conv))
    }

    func test_archivedFolder_matchesFlaggedAndArchived() {
        let conv = makeConversation(isFlagged: true, isArchived: true)
        XCTAssertTrue(SmsFolder.archived.matches(conv))
    }

    // MARK: - SmsFolder identity

    func test_allCases_hasCorrectCount() {
        XCTAssertEqual(SmsFolder.allCases.count, 4)
    }

    func test_folderIds_areUnique() {
        let ids = SmsFolder.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_folderSystemImages_areNonEmpty() {
        for folder in SmsFolder.allCases {
            XCTAssertFalse(folder.systemImage.isEmpty, "\(folder) has empty systemImage")
        }
    }

    // MARK: - Filtering a list

    func test_filterList_allFolder_filtersArchived() {
        let convs: [SmsConversation] = [
            makeConversation(phone: "+1", isArchived: false),
            makeConversation(phone: "+2", isArchived: true),
            makeConversation(phone: "+3", isArchived: false),
        ]
        let result = convs.filter { SmsFolder.all.matches($0) }
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.isArchived })
    }

    func test_filterList_flaggedFolder_onlyFlagged() {
        let convs: [SmsConversation] = [
            makeConversation(phone: "+1", isFlagged: true),
            makeConversation(phone: "+2", isFlagged: false),
            makeConversation(phone: "+3", isFlagged: true, isArchived: true),
        ]
        let result = convs.filter { SmsFolder.flagged.matches($0) }
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.convPhone, "+1")
    }

    func test_filterList_archivedFolder_onlyArchived() {
        let convs: [SmsConversation] = [
            makeConversation(phone: "+1", isArchived: false),
            makeConversation(phone: "+2", isArchived: true),
            makeConversation(phone: "+3", isArchived: true),
        ]
        let result = convs.filter { SmsFolder.archived.matches($0) }
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy(\.isArchived))
    }
}
