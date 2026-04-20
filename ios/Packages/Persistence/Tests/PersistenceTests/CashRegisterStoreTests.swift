import XCTest
@testable import Persistence

/// §39 — integration tests for `CashRegisterStore`. Each test opens a
/// throwaway temp-dir DB via `Database.reopen(at:)` so the actor-level
/// shared store can be exercised without clobbering other fixtures.
final class CashRegisterStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cash-register-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("test.sqlite")
        try await Database.shared.reopen(at: tempURL)
    }

    override func tearDown() async throws {
        await Database.shared.close()
        if let url = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Open

    func test_openSession_writesRowAndReturnsId() async throws {
        let opened = try await CashRegisterStore.shared.openSession(
            openingFloat: 10_000,
            userId: 7
        )
        XCTAssertNotNil(opened.id)
        XCTAssertEqual(opened.openingFloat, 10_000)
        XCTAssertEqual(opened.openedBy, 7)
        XCTAssertTrue(opened.isOpen)
        XCTAssertNil(opened.closedAt)
    }

    func test_openSession_rejectsWhenAlreadyOpen() async throws {
        _ = try await CashRegisterStore.shared.openSession(
            openingFloat: 5_000,
            userId: 1
        )
        do {
            _ = try await CashRegisterStore.shared.openSession(
                openingFloat: 5_000,
                userId: 1
            )
            XCTFail("Expected .alreadyOpen when re-opening")
        } catch CashRegisterError.alreadyOpen {
            // Expected.
        }
    }

    // MARK: - Current

    func test_currentSession_returnsOpenRow_andNilAfterClose() async throws {
        let initial = try await CashRegisterStore.shared.currentSession()
        XCTAssertNil(initial)

        let opened = try await CashRegisterStore.shared.openSession(
            openingFloat: 20_000,
            userId: 2
        )
        let current = try await CashRegisterStore.shared.currentSession()
        XCTAssertEqual(current?.id, opened.id)

        _ = try await CashRegisterStore.shared.closeSession(
            countedCash: 22_500,
            expectedCash: 22_500,
            notes: nil,
            closedBy: 2
        )
        let afterClose = try await CashRegisterStore.shared.currentSession()
        XCTAssertNil(afterClose, "currentSession must be nil once the register is closed")
    }

    // MARK: - Close

    func test_closeSession_writesClosedAtAndVariance() async throws {
        _ = try await CashRegisterStore.shared.openSession(
            openingFloat: 10_000,
            userId: 3
        )
        let closed = try await CashRegisterStore.shared.closeSession(
            countedCash: 9_500,        // short $5
            expectedCash: 10_000,
            notes: "Short change-drop",
            closedBy: 3
        )
        XCTAssertNotNil(closed.closedAt)
        XCTAssertEqual(closed.closedBy, 3)
        XCTAssertEqual(closed.countedCash, 9_500)
        XCTAssertEqual(closed.expectedCash, 10_000)
        XCTAssertEqual(closed.varianceCents, -500)
        XCTAssertEqual(closed.notes, "Short change-drop")
    }

    func test_closeSession_throwsWhenNoOpenSession() async throws {
        do {
            _ = try await CashRegisterStore.shared.closeSession(
                countedCash: 0,
                expectedCash: 0,
                notes: nil,
                closedBy: 1
            )
            XCTFail("Expected .noOpenSession")
        } catch CashRegisterError.noOpenSession {
            // Expected.
        }
    }

    // MARK: - Recent

    func test_recentSessions_returnsDescendingOrder() async throws {
        // Three shifts: seed each with an explicit open date spaced
        // 1h apart so the ordering is deterministic (otherwise sub-ms
        // writes can race).
        let now = Date()
        let shift1 = try await CashRegisterStore.shared.openSession(
            openingFloat: 100,
            userId: 9,
            at: now.addingTimeInterval(-7200)
        )
        _ = try await CashRegisterStore.shared.closeSession(
            countedCash: 100,
            expectedCash: 100,
            notes: nil,
            closedBy: 9,
            at: now.addingTimeInterval(-7100)
        )
        let shift2 = try await CashRegisterStore.shared.openSession(
            openingFloat: 200,
            userId: 9,
            at: now.addingTimeInterval(-3600)
        )
        _ = try await CashRegisterStore.shared.closeSession(
            countedCash: 200,
            expectedCash: 200,
            notes: nil,
            closedBy: 9,
            at: now.addingTimeInterval(-3500)
        )
        let shift3 = try await CashRegisterStore.shared.openSession(
            openingFloat: 300,
            userId: 9,
            at: now
        )

        let recent = try await CashRegisterStore.shared.recentSessions(limit: 10)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].id, shift3.id, "newest session must be first")
        XCTAssertEqual(recent[1].id, shift2.id)
        XCTAssertEqual(recent[2].id, shift1.id, "oldest session must be last")
    }

    func test_recentSessions_respectsLimit() async throws {
        for i in 0..<5 {
            let opened = try await CashRegisterStore.shared.openSession(
                openingFloat: 100 * (i + 1),
                userId: 1,
                at: Date().addingTimeInterval(-Double(5 - i) * 60)
            )
            _ = try await CashRegisterStore.shared.closeSession(
                countedCash: opened.openingFloat,
                expectedCash: opened.openingFloat,
                notes: nil,
                closedBy: 1,
                at: Date().addingTimeInterval(-Double(5 - i) * 60 + 1)
            )
        }
        let limited = try await CashRegisterStore.shared.recentSessions(limit: 3)
        XCTAssertEqual(limited.count, 3)
    }

    // MARK: - Sync stamp

    func test_markSynced_populatesServerId() async throws {
        let opened = try await CashRegisterStore.shared.openSession(
            openingFloat: 50,
            userId: 1
        )
        let id = try XCTUnwrap(opened.id)

        try await CashRegisterStore.shared.markSynced(localId: id, serverId: "srv-42")

        let reloaded = try await CashRegisterStore.shared.session(id: id)
        XCTAssertEqual(reloaded?.serverId, "srv-42")
    }
}
