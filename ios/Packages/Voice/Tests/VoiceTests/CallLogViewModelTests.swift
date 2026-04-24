import XCTest
@testable import Voice
import Networking

/// §42 — `CallLogViewModel` tests: filter logic and 404 → comingSoon state.
///
/// Uses a lightweight `MockAPIClient` that intercepts `listCalls` by
/// implementing the protocol method and round-tripping through JSON so the
/// generic `T = CallLogListPayload` resolves correctly.
@MainActor
final class CallLogViewModelTests: XCTestCase {

    // MARK: - Mock API client

    /// Intercepts calls at the JSON level: stubs are stored as pre-encoded
    /// Data so we can decode into whatever `T` the extension asks for.
    final class MockAPIClient: APIClient, @unchecked Sendable {

        /// Pre-encoded JSON data keyed by path prefix.
        var pathData: [String: Data] = [:]
        /// Errors keyed by path prefix (checked before pathData).
        var pathErrors: [String: Error] = [:]

        func stub(path: String, calls: [CallLogEntry]) throws {
            // listCalls decodes CallLogListPayload = { calls: [...] }
            let payload = CallListWrapper(calls: calls)
            pathData[path] = try JSONEncoder().encode(payload)
        }

        func stubError(path: String, error: Error) {
            pathErrors[path] = error
        }

        func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
            for (prefix, error) in pathErrors where path.hasPrefix(prefix) {
                throw error
            }
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
        {
            throw APITransportError.httpStatus(501, message: "Not implemented")
        }

        func put<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
            where T: Decodable, T: Sendable, B: Encodable, B: Sendable
        {
            throw APITransportError.httpStatus(501, message: "Not implemented")
        }

        func patch<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
            where T: Decodable, T: Sendable, B: Encodable, B: Sendable
        {
            throw APITransportError.httpStatus(501, message: "Not implemented")
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
    }

    // Encodable mirror of the internal CallLogListPayload so stub() can
    // serialise a list into the expected JSON shape.
    private struct CallListWrapper: Encodable {
        let calls: [CallEntry]
        struct CallEntry: Encodable {
            let id: Int64
            let direction: String
            let conv_phone: String
            let customer_id: Int64?
            let user_name: String?
            let created_at: String?
            let duration_secs: Int?
            let recording_url: String?
            let transcription: String?
        }
        init(calls: [CallLogEntry]) {
            self.calls = calls.map {
                CallEntry(
                    id: $0.id,
                    direction: $0.direction,
                    conv_phone: $0.phoneNumber,
                    customer_id: $0.customerId,
                    user_name: $0.customerName,
                    created_at: $0.startedAt,
                    duration_secs: $0.durationSeconds,
                    recording_url: $0.recordingUrl,
                    transcription: $0.transcriptText
                )
            }
        }
    }

    // MARK: - Helpers

    private func makeEntry(
        id: Int64,
        direction: String = "inbound",
        phone: String = "5551234567",
        customerName: String? = nil,
        durationSeconds: Int? = nil
    ) -> CallLogEntry {
        CallLogEntry(
            id: id,
            direction: direction,
            phoneNumber: phone,
            customerId: nil,
            customerName: customerName,
            startedAt: "2026-04-20T10:00:00Z",
            durationSeconds: durationSeconds,
            recordingUrl: nil,
            transcriptText: nil
        )
    }

    // MARK: - Load state transitions

    func test_load_successTransitionsToLoaded() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [makeEntry(id: 1)])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        if case .loaded(let calls) = vm.state {
            XCTAssertEqual(calls.count, 1)
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    func test_load_404TransitionsToComingSoon() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voice/calls", error: APITransportError.httpStatus(404, message: "Not found"))
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        if case .comingSoon = vm.state {
            // success
        } else {
            XCTFail("Expected .comingSoon for 404, got \(vm.state)")
        }
    }

    func test_load_networkErrorTransitionsToFailed() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voice/calls", error: APITransportError.networkUnavailable)
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        if case .failed = vm.state {
            // success
        } else {
            XCTFail("Expected .failed for network error, got \(vm.state)")
        }
    }

    func test_load_500ErrorTransitionsToFailed() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voice/calls", error: APITransportError.httpStatus(500, message: "Internal server error"))
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        if case .failed = vm.state {
            // success
        } else {
            XCTFail("Expected .failed for 500, got \(vm.state)")
        }
    }

    // MARK: - Filter logic

    func test_filter_emptyQueryReturnsAll() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, customerName: "Alice"),
            makeEntry(id: 2, customerName: "Bob"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let result = vm.filteredCalls("")
        XCTAssertEqual(result.count, 2)
    }

    func test_filter_matchesCustomerNameCaseInsensitive() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, customerName: "Alice Smith"),
            makeEntry(id: 2, customerName: "Bob Jones"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let result = vm.filteredCalls("alice")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func test_filter_matchesPhoneDigits() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, phone: "5551234567"),
            makeEntry(id: 2, phone: "8005550100"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let result = vm.filteredCalls("800")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 2)
    }

    func test_filter_matchesDirection() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, direction: "inbound"),
            makeEntry(id: 2, direction: "outbound"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let outbound = vm.filteredCalls("outbound")
        XCTAssertEqual(outbound.count, 1)
        XCTAssertEqual(outbound.first?.id, 2)
    }

    func test_filter_noMatchReturnsEmpty() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [makeEntry(id: 1, customerName: "Alice")])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let result = vm.filteredCalls("zzznomatch")
        XCTAssertTrue(result.isEmpty)
    }

    func test_filter_whitespaceQueryReturnsAll() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [makeEntry(id: 1), makeEntry(id: 2)])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let result = vm.filteredCalls("   ")
        XCTAssertEqual(result.count, 2)
    }

    func test_filter_onComingSoonStateReturnsEmpty() async {
        let mock = MockAPIClient()
        mock.stubError(path: "/api/v1/voice/calls", error: APITransportError.httpStatus(404, message: nil))
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        let result = vm.filteredCalls("anything")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Direction filter

    func test_directionFilter_defaultIsAll() {
        let mock = MockAPIClient()
        let vm = CallLogViewModel(api: mock)
        XCTAssertEqual(vm.directionFilter, .all)
    }

    func test_directionFilter_inboundShowsOnlyInbound() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, direction: "inbound"),
            makeEntry(id: 2, direction: "outbound"),
            makeEntry(id: 3, direction: "inbound"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .inbound
        let result = vm.filteredCalls("")
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.direction == "inbound" })
    }

    func test_directionFilter_outboundShowsOnlyOutbound() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, direction: "inbound"),
            makeEntry(id: 2, direction: "outbound"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .outbound
        let result = vm.filteredCalls("")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 2)
    }

    func test_directionFilter_allShowsEverything() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, direction: "inbound"),
            makeEntry(id: 2, direction: "outbound"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .all
        let result = vm.filteredCalls("")
        XCTAssertEqual(result.count, 2)
    }

    func test_directionFilter_combinedWithTextSearch() async throws {
        let mock = MockAPIClient()
        try mock.stub(path: "/api/v1/voice/calls", calls: [
            makeEntry(id: 1, direction: "inbound",  phone: "5551111111", customerName: "Alice"),
            makeEntry(id: 2, direction: "outbound", phone: "5552222222", customerName: "Alice"),
            makeEntry(id: 3, direction: "inbound",  phone: "5553333333", customerName: "Bob"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .inbound
        let result = vm.filteredCalls("alice")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func test_directionFilter_allCases() {
        XCTAssertEqual(CallLogViewModel.DirectionFilter.allCases.count, 3)
        XCTAssertTrue(CallLogViewModel.DirectionFilter.allCases.contains(.all))
        XCTAssertTrue(CallLogViewModel.DirectionFilter.allCases.contains(.inbound))
        XCTAssertTrue(CallLogViewModel.DirectionFilter.allCases.contains(.outbound))
    }

    func test_directionFilter_labels() {
        XCTAssertEqual(CallLogViewModel.DirectionFilter.all.label,      "All")
        XCTAssertEqual(CallLogViewModel.DirectionFilter.inbound.label,  "Inbound")
        XCTAssertEqual(CallLogViewModel.DirectionFilter.outbound.label, "Outbound")
    }
}
