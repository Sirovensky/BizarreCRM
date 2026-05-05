import XCTest
@testable import Voice
import Networking

/// §42.5 — `VoicemailViewModel` tests.
///
/// Exercises:
/// - 404 → `.comingSoon` state transition
/// - Network error → `.failed` state transition
/// - Successful load → `.loaded` state transition
/// - `markHeard` optimistic update
/// - `markHeard` swallows errors silently
///
/// Uses a shared `MockAPIClient` that stubs `listVoicemails` and
/// `markVoicemailHeard` by intercepting the known URL paths.
@MainActor
final class VoicemailViewModelTests: XCTestCase {

    // MARK: - Mock API client

    final class MockAPIClient: APIClient, @unchecked Sendable {

        var pathData: [String: Data] = [:]
        var pathErrors: [String: Error] = [:]
        var patchErrors: [String: Error] = [:]
        var patchCallCount: Int = 0

        // Encode voicemails as a bare array (listVoicemails decodes `[VoicemailEntry]`)
        func stubVoicemails(_ items: [VoicemailEntry]) throws {
            let encoded = try JSONEncoder().encode(items.map { EncEntry(from: $0) })
            pathData["/api/v1/voicemails"] = encoded
        }

        func stubError(path: String, error: Error) {
            pathErrors[path] = error
        }

        func stubPatchError(path: String, error: Error) {
            patchErrors[path] = error
        }

        func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
            for (prefix, error) in pathErrors where path.hasPrefix(prefix) { throw error }
            for (prefix, data) in pathData where path.hasPrefix(prefix) {
                return try JSONDecoder().decode(T.self, from: data)
            }
            throw APITransportError.httpStatus(404, message: "Not found")
        }

        func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
            try await get(path, query: nil, as: type)
        }

        func post<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
            where T: Decodable, T: Sendable, B: Encodable, B: Sendable
        { throw APITransportError.httpStatus(501, message: "Not implemented") }

        func put<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
            where T: Decodable, T: Sendable, B: Encodable, B: Sendable
        { throw APITransportError.httpStatus(501, message: "Not implemented") }

        func patch<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
            where T: Decodable, T: Sendable, B: Encodable, B: Sendable
        {
            patchCallCount += 1
            for (prefix, error) in patchErrors where path.hasPrefix(prefix) { throw error }
            // Return an empty decodable ack
            let emptyJSON = Data("{}".utf8)
            return try JSONDecoder().decode(T.self, from: emptyJSON)
        }

        func delete(_ path: String) async throws {
            throw APITransportError.httpStatus(501, message: "Not implemented")
        }

        func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
            throw APITransportError.httpStatus(501, message: "Not implemented")
        }

        func setAuthToken(_ token: String?) async {}
        func setBaseURL(_ url: URL?) async {}
        func currentBaseURL() async -> URL? { nil }
        func setRefresher(_ refresher: AuthSessionRefresher?) async {}

        // Encodable mirror of VoicemailEntry for stubbing
        private struct EncEntry: Encodable {
            let id: Int64
            let phone_number: String
            let customer_name: String?
            let received_at: String?
            let duration_seconds: Int?
            let audio_url: String?
            let transcript_text: String?
            let heard: Bool

            init(from e: VoicemailEntry) {
                id = e.id
                phone_number = e.phoneNumber
                customer_name = e.customerName
                received_at = e.receivedAt
                duration_seconds = e.durationSeconds
                audio_url = e.audioUrl
                transcript_text = e.transcriptText
                heard = e.heard
            }
        }
    }

    // MARK: - Helpers

    private func makeVM(id: Int64 = 1, heard: Bool = false) -> VoicemailEntry {
        VoicemailEntry(
            id: id,
            phoneNumber: "5551234567",
            customerName: "Alice",
            receivedAt: "2026-04-20T10:00:00Z",
            durationSeconds: 30,
            audioUrl: "https://api.twilio.com/vm/\(id).mp3",
            transcriptText: "Please call me back.",
            heard: heard
        )
    }

    // MARK: - Load state transitions

    func test_load_404TransitionsToComingSoon() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voicemails",
                       error: APITransportError.httpStatus(404, message: "Not found"))
        let vm = VoicemailViewModel(api: mock)
        await vm.load()
        if case .comingSoon = vm.state { /* pass */ }
        else { XCTFail("Expected .comingSoon, got \(vm.state)") }
    }

    func test_load_networkErrorTransitionsToFailed() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voicemails",
                       error: APITransportError.networkUnavailable)
        let vm = VoicemailViewModel(api: mock)
        await vm.load()
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    func test_load_500TransitionsToFailed() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voicemails",
                       error: APITransportError.httpStatus(500, message: "Server error"))
        let vm = VoicemailViewModel(api: mock)
        await vm.load()
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed for 500, got \(vm.state)") }
    }

    func test_load_successTransitionsToLoaded() async throws {
        let mock = MockAPIClient()
        try mock.stubVoicemails([makeVM(id: 1), makeVM(id: 2)])
        let vm = VoicemailViewModel(api: mock)
        await vm.load()
        if case .loaded(let items) = vm.state {
            XCTAssertEqual(items.count, 2)
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    func test_load_emptyArrayTransitionsToLoadedEmpty() async throws {
        let mock = MockAPIClient()
        try mock.stubVoicemails([])
        let vm = VoicemailViewModel(api: mock)
        await vm.load()
        if case .loaded(let items) = vm.state {
            XCTAssertTrue(items.isEmpty)
        } else {
            XCTFail("Expected .loaded([]), got \(vm.state)")
        }
    }

    // MARK: - markHeard optimistic update

    func test_markHeard_updatesStateOptimistically() async throws {
        let mock = MockAPIClient()
        let entry = makeVM(id: 1, heard: false)
        try mock.stubVoicemails([entry])
        let vm = VoicemailViewModel(api: mock)
        await vm.load()

        await vm.markHeard(entry: entry)

        if case .loaded(let items) = vm.state {
            XCTAssertTrue(items.first?.heard == true, "Entry should be marked heard optimistically")
        } else {
            XCTFail("Expected .loaded after markHeard")
        }
    }

    func test_markHeard_otherEntriesUnchanged() async throws {
        let mock = MockAPIClient()
        let e1 = makeVM(id: 1, heard: false)
        let e2 = makeVM(id: 2, heard: false)
        try mock.stubVoicemails([e1, e2])
        let vm = VoicemailViewModel(api: mock)
        await vm.load()

        await vm.markHeard(entry: e1)

        if case .loaded(let items) = vm.state {
            XCTAssertTrue(items.first(where: { $0.id == 1 })?.heard == true)
            XCTAssertFalse(items.first(where: { $0.id == 2 })?.heard ?? true,
                           "Entry 2 should remain unheard")
        } else {
            XCTFail("Expected .loaded after markHeard")
        }
    }

    func test_markHeard_swallowsPatchError() async throws {
        let mock = MockAPIClient()
        let entry = makeVM(id: 1, heard: false)
        try mock.stubVoicemails([entry])
        mock.stubPatchError(path: "/api/v1/voicemails/1/heard",
                            error: APITransportError.httpStatus(500, message: "Server error"))
        let vm = VoicemailViewModel(api: mock)
        await vm.load()

        // Should NOT throw
        await vm.markHeard(entry: entry)

        // State should still be loaded (optimistic update applied despite server error)
        if case .loaded(let items) = vm.state {
            XCTAssertTrue(items.first?.heard == true)
        } else {
            XCTFail("State should remain .loaded after swallowed error")
        }
    }

    func test_markHeard_callsPatchEndpoint() async throws {
        let mock = MockAPIClient()
        let entry = makeVM(id: 42, heard: false)
        try mock.stubVoicemails([entry])
        let vm = VoicemailViewModel(api: mock)
        await vm.load()

        await vm.markHeard(entry: entry)

        XCTAssertEqual(mock.patchCallCount, 1, "PATCH should have been called once")
    }

    // MARK: - markHeard on non-loaded state is a no-op

    func test_markHeard_onLoadingStateIsNoOp() async {
        let mock = MockAPIClient()
        let entry = makeVM(id: 1)
        let vm = VoicemailViewModel(api: mock)
        // vm.state is .loading by default
        await vm.markHeard(entry: entry)
        // Should not crash; state remains .loading
        if case .loading = vm.state { /* pass */ }
        else { XCTFail("Expected state to remain .loading") }
    }

    // MARK: - Multiple loads

    func test_load_secondLoadReplacesData() async throws {
        let mock = MockAPIClient()
        try mock.stubVoicemails([makeVM(id: 1)])
        let vm = VoicemailViewModel(api: mock)
        await vm.load()

        try mock.stubVoicemails([makeVM(id: 2), makeVM(id: 3)])
        await vm.load()

        if case .loaded(let items) = vm.state {
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[0].id, 2)
        } else {
            XCTFail("Expected .loaded with 2 items after reload")
        }
    }
}
