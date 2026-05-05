import Testing
import Foundation
@testable import CommandPalette

@Suite("RecentUsageStore")
struct RecentUsageStoreTests {

    private func makeSuite() -> RecentUsageStore {
        // Use a unique key per test to avoid cross-test pollution
        let key = "test_recent_\(UUID().uuidString)"
        return RecentUsageStore(userDefaultsKey: key)
    }

    @Test("starts with empty recent IDs")
    func startsEmpty() {
        let store = makeSuite()
        #expect(store.recentIDs.isEmpty)
    }

    @Test("recording an ID adds it to recent list")
    func recordingAddsID() {
        let store = makeSuite()
        store.record(id: "new-ticket")
        #expect(store.recentIDs.contains("new-ticket"))
    }

    @Test("most recently used appears first")
    func mostRecentFirst() {
        let store = makeSuite()
        store.record(id: "action-a")
        store.record(id: "action-b")
        #expect(store.recentIDs.first == "action-b")
    }

    @Test("duplicate recording moves ID to front")
    func duplicateMoveToFront() {
        let store = makeSuite()
        store.record(id: "action-a")
        store.record(id: "action-b")
        store.record(id: "action-a")
        #expect(store.recentIDs.first == "action-a")
        // action-a should appear only once
        #expect(store.recentIDs.filter { $0 == "action-a" }.count == 1)
    }

    @Test("capped at 10 entries")
    func cappedAtTen() {
        let store = makeSuite()
        for i in 0..<15 {
            store.record(id: "action-\(i)")
        }
        #expect(store.recentIDs.count == 10)
    }

    @Test("oldest entry evicted when cap exceeded")
    func oldestEvicted() {
        let store = makeSuite()
        for i in 0..<10 {
            store.record(id: "action-\(i)")
        }
        // action-0 is the oldest
        store.record(id: "action-new")
        #expect(!store.recentIDs.contains("action-0"))
        #expect(store.recentIDs.contains("action-new"))
    }

    @Test("boost returns non-zero for a known recent ID")
    func boostForKnownID() {
        let store = makeSuite()
        store.record(id: "clock-in")
        let boost = store.boost(for: "clock-in")
        #expect(boost > 0)
    }

    @Test("boost returns zero for unknown ID")
    func boostForUnknownID() {
        let store = makeSuite()
        let boost = store.boost(for: "unknown-action")
        #expect(boost == 0)
    }

    @Test("boost is higher for more recent items")
    func moreRecentHigherBoost() {
        let store = makeSuite()
        store.record(id: "older-action")
        store.record(id: "newer-action")
        let olderBoost = store.boost(for: "older-action")
        let newerBoost = store.boost(for: "newer-action")
        #expect(newerBoost >= olderBoost)
    }

    @Test("persistence across store instances with same key")
    func persistsAcrossInstances() {
        let key = "test_persist_\(UUID().uuidString)"
        let store1 = RecentUsageStore(userDefaultsKey: key)
        store1.record(id: "persistent-action")

        let store2 = RecentUsageStore(userDefaultsKey: key)
        #expect(store2.recentIDs.contains("persistent-action"))

        // Cleanup
        UserDefaults.standard.removeObject(forKey: key)
    }
}
