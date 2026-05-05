import XCTest
@testable import Core

// §63 ext — DraftAutoSaver unit tests
// Uses a unique DraftStore suite per test for isolation.

@MainActor
final class DraftAutoSaverTests: XCTestCase {

    private struct SimpleDraft: Codable, Sendable, Equatable {
        var value: String
    }

    private func makeStore() -> DraftStore {
        DraftStore(suiteName: "test.autoSaver.\(UUID().uuidString)")
    }

    // MARK: — push + debounce fires and persists

    func test_push_savesAfterDebounce() async throws {
        let store = makeStore()
        let saver = DraftAutoSaver<SimpleDraft>(
            screen: "test.screen",
            entityId: nil,
            debounceSeconds: 0.05,   // 50 ms in tests
            store: store
        )

        saver.push(SimpleDraft(value: "hello"))

        // Wait longer than debounce.
        try await Task.sleep(nanoseconds: 200_000_000) // 200 ms

        let loaded = try await store.load(SimpleDraft.self, screen: "test.screen", entityId: nil)
        XCTAssertEqual(loaded, SimpleDraft(value: "hello"))
    }

    // MARK: — rapid pushes → only last value persisted

    func test_push_rapidUpdates_onlyLastSaved() async throws {
        let store = makeStore()
        let saver = DraftAutoSaver<SimpleDraft>(
            screen: "test.screen",
            entityId: nil,
            debounceSeconds: 0.1,
            store: store
        )

        saver.push(SimpleDraft(value: "first"))
        saver.push(SimpleDraft(value: "second"))
        saver.push(SimpleDraft(value: "third"))

        // Wait for debounce to fire once.
        try await Task.sleep(nanoseconds: 300_000_000)

        let loaded = try await store.load(SimpleDraft.self, screen: "test.screen", entityId: nil)
        XCTAssertEqual(loaded?.value, "third")
    }

    // MARK: — clear removes draft and cancels pending

    func test_clear_removesDraftAndCancelsPending() async throws {
        let store = makeStore()
        let saver = DraftAutoSaver<SimpleDraft>(
            screen: "test.screen",
            entityId: nil,
            debounceSeconds: 0.1,
            store: store
        )

        // Seed a saved draft.
        try await store.save(SimpleDraft(value: "seed"), screen: "test.screen", entityId: nil)

        // Schedule another push, then immediately clear.
        saver.push(SimpleDraft(value: "should-not-persist"))
        await saver.clear()

        // Wait past debounce.
        try await Task.sleep(nanoseconds: 250_000_000)

        let loaded = try await store.load(SimpleDraft.self, screen: "test.screen", entityId: nil)
        XCTAssertNil(loaded, "clear must remove draft and cancel pending push")
    }

    // MARK: — cancelPending does not clear existing draft

    func test_cancelPending_keepsExistingDraft() async throws {
        let store = makeStore()
        let saver = DraftAutoSaver<SimpleDraft>(
            screen: "test.screen",
            entityId: nil,
            debounceSeconds: 0.2,
            store: store
        )

        // Persist a draft directly.
        try await store.save(SimpleDraft(value: "kept"), screen: "test.screen", entityId: nil)

        // Push a new value but cancel before it fires.
        saver.push(SimpleDraft(value: "cancelled"))
        saver.cancelPending()

        try await Task.sleep(nanoseconds: 400_000_000)

        let loaded = try await store.load(SimpleDraft.self, screen: "test.screen", entityId: nil)
        XCTAssertEqual(loaded?.value, "kept", "cancelPending must NOT clear existing draft")
    }

    // MARK: — entityId is forwarded correctly

    func test_push_withEntityId_savesUnderCorrectKey() async throws {
        let store = makeStore()
        let saver = DraftAutoSaver<SimpleDraft>(
            screen: "test.edit",
            entityId: "42",
            debounceSeconds: 0.05,
            store: store
        )

        saver.push(SimpleDraft(value: "entity-draft"))
        try await Task.sleep(nanoseconds: 200_000_000)

        let loadedWithId   = try await store.load(SimpleDraft.self, screen: "test.edit", entityId: "42")
        let loadedWithoutId = try await store.load(SimpleDraft.self, screen: "test.edit", entityId: nil)

        XCTAssertEqual(loadedWithId?.value, "entity-draft")
        XCTAssertNil(loadedWithoutId, "draft must be keyed by entityId, not nil slot")
    }

    // MARK: — save completion arrives (no throw)

    func test_push_doesNotThrowOnValidDraft() async throws {
        let store = makeStore()
        let saver = DraftAutoSaver<SimpleDraft>(
            screen: "test.screen",
            entityId: nil,
            debounceSeconds: 0.05,
            store: store
        )
        // No assertion — just checking no uncaught error surfaces.
        saver.push(SimpleDraft(value: "safe"))
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}
