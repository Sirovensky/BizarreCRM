import XCTest
@testable import Core

// §20 Draft Recovery — DraftLifecycle constant tests
// Verifies that the policy constants have the expected values and that
// they integrate correctly with UserDefaultsDraftStore.prune().

final class DraftLifecycleTests: XCTestCase {

    // MARK: — Constants have correct values

    func test_defaultExpirationInterval_is30Days() {
        XCTAssertEqual(DraftLifecycle.defaultExpirationInterval, 30 * 86_400,
                       accuracy: 1, "default expiration must be exactly 30 days")
    }

    func test_autosaveInterval_is3Seconds() {
        XCTAssertEqual(DraftLifecycle.autosaveInterval, 3,
                       accuracy: 0.001, "autosave interval must be exactly 3 seconds")
    }

    func test_minimumPruneInterval_is1Hour() {
        XCTAssertEqual(DraftLifecycle.minimumPruneInterval, 3_600,
                       accuracy: 1, "minimum prune interval must be 1 hour")
    }

    // MARK: — Integration: prune respects defaultExpirationInterval

    private struct MinimalDraft: Codable, Sendable, Equatable { var v: String }

    func test_prune_withDefaultInterval_keepsRecentDraft() async throws {
        let store = UserDefaultsDraftStore(suiteName: "test.lc.\(UUID().uuidString)")
        try await store.save(MinimalDraft(v: "now"), forKey: .ticketCreate)

        await store.prune(olderThan: DraftLifecycle.defaultExpirationInterval)

        let all = await store.listPending()
        XCTAssertEqual(all.count, 1, "a draft created now is not 30 days old and must survive")
    }

    func test_prune_withNegativeInterval_removesAll() async throws {
        let store = UserDefaultsDraftStore(suiteName: "test.lc.\(UUID().uuidString)")
        try await store.save(MinimalDraft(v: "a"), forKey: .ticketCreate)
        try await store.save(MinimalDraft(v: "b"), forKey: .customerCreate)

        // Negative interval → cutoff is in the future → every draft is "older".
        await store.prune(olderThan: -1)

        let all = await store.listPending()
        XCTAssertTrue(all.isEmpty)
    }
}
