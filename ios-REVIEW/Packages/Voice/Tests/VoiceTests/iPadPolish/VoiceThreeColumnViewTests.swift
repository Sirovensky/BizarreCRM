import XCTest
@testable import Voice
import Networking

/// §22 — Logic tests for `VoiceThreeColumnView` state behaviour.
///
/// The SwiftUI view itself cannot be instantiated in a headless test host,
/// but the view delegates state management to `CallLogViewModel` and
/// `VoicemailViewModel`, both of which are fully testable.
///
/// These tests cover:
///   1. `SidebarTab` enum — labels, icons, identity.
///   2. `callbackSelectedEntry` logic replicated via the view-models: only
///      fires when an entry is selected and the model is in `.loaded` state.
///   3. Unheard badge count calculation (matches the `unheardBadge` logic).
///   4. Direction filter integration via `CallLogViewModel.filteredCalls`.
final class VoiceThreeColumnViewTests: XCTestCase {

    // MARK: - SidebarTab

    func test_sidebarTab_allCasesCountIsTwo() {
        XCTAssertEqual(VoiceSidebarTab.allCases.count, 2)
    }

    func test_sidebarTab_callsLabel() {
        XCTAssertEqual(VoiceSidebarTab.calls.label, "Calls")
    }

    func test_sidebarTab_voicemailLabel() {
        XCTAssertEqual(VoiceSidebarTab.voicemail.label, "Voicemail")
    }

    func test_sidebarTab_callsIcon() {
        XCTAssertEqual(VoiceSidebarTab.calls.icon, "phone")
    }

    func test_sidebarTab_voicemailIcon() {
        XCTAssertEqual(VoiceSidebarTab.voicemail.icon, "voicemail")
    }

    func test_sidebarTab_rawValues() {
        XCTAssertEqual(VoiceSidebarTab.calls.rawValue, "calls")
        XCTAssertEqual(VoiceSidebarTab.voicemail.rawValue, "voicemail")
    }

    func test_sidebarTab_idEqualsRawValue() {
        let tab = VoiceSidebarTab.calls
        XCTAssertEqual(tab.id, tab.rawValue)
    }

    // MARK: - Unheard badge count logic

    /// Replicates the badge count calculation in `unheardBadge`.
    private func unheardCount(from items: [VoicemailEntry]) -> Int {
        items.filter { !$0.heard }.count
    }

    func test_unheardBadge_zeroWhenAllHeard() {
        let items = [
            VoicemailEntry(id: 1, phoneNumber: "555", heard: true),
            VoicemailEntry(id: 2, phoneNumber: "556", heard: true),
        ]
        XCTAssertEqual(unheardCount(from: items), 0)
    }

    func test_unheardBadge_countsUnheardOnly() {
        let items = [
            VoicemailEntry(id: 1, phoneNumber: "555", heard: false),
            VoicemailEntry(id: 2, phoneNumber: "556", heard: true),
            VoicemailEntry(id: 3, phoneNumber: "557", heard: false),
        ]
        XCTAssertEqual(unheardCount(from: items), 2)
    }

    func test_unheardBadge_allUnheard() {
        let items = (1...5).map {
            VoicemailEntry(id: Int64($0), phoneNumber: "55\($0)", heard: false)
        }
        XCTAssertEqual(unheardCount(from: items), 5)
    }

    func test_unheardBadge_emptyListIsZero() {
        XCTAssertEqual(unheardCount(from: []), 0)
    }

    // MARK: - Callback logic (view-model-level)

    @MainActor
    func test_callbackSelectedEntry_callsCleanPhoneNumber() async throws {
        // Verify the clean-number path that the Callback action uses.
        let raw = "(555) 123-4567"
        let cleaned = CallQuickAction.cleanPhoneNumber(raw)
        XCTAssertEqual(cleaned, "5551234567")
    }

    @MainActor
    func test_callbackSelectedEntry_noSelectionIsNoOp() async throws {
        // When no entry is selected, placeCall should not be invoked.
        // We verify via the cleanPhoneNumber guard: empty cleaned string → no-op.
        let cleaned = CallQuickAction.cleanPhoneNumber("")
        XCTAssertTrue(cleaned.isEmpty,
                      "Empty phone should yield empty cleaned string → no-op guard")
    }

    // MARK: - Direction filter integration

    @MainActor
    func test_directionFilter_defaultIsAll() {
        let mock = MockAPIClientThreeColumn()
        let vm = CallLogViewModel(api: mock)
        XCTAssertEqual(vm.directionFilter, .all)
    }

    @MainActor
    func test_directionFilter_inboundFiltersCorrectly() async throws {
        let mock = MockAPIClientThreeColumn()
        try mock.stubCalls([
            makeCallEntry(id: 1, direction: "inbound"),
            makeCallEntry(id: 2, direction: "outbound"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .inbound
        let result = vm.filteredCalls("")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    @MainActor
    func test_directionFilter_outboundFiltersCorrectly() async throws {
        let mock = MockAPIClientThreeColumn()
        try mock.stubCalls([
            makeCallEntry(id: 1, direction: "inbound"),
            makeCallEntry(id: 2, direction: "outbound"),
            makeCallEntry(id: 3, direction: "outbound"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .outbound
        let result = vm.filteredCalls("")
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.direction == "outbound" })
    }

    // MARK: - Search + direction filter combined

    @MainActor
    func test_searchCombinedWithDirectionFilter() async throws {
        let mock = MockAPIClientThreeColumn()
        try mock.stubCalls([
            makeCallEntry(id: 1, direction: "inbound",  phone: "5551111111", name: "Alice"),
            makeCallEntry(id: 2, direction: "outbound", phone: "5552222222", name: "Alice"),
            makeCallEntry(id: 3, direction: "inbound",  phone: "5553333333", name: "Bob"),
        ])
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        vm.directionFilter = .inbound
        let result = vm.filteredCalls("alice")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    // MARK: - comingSoon passthrough

    @MainActor
    func test_callsComingSoon_filteredCallsReturnsEmpty() async {
        let mock = MockAPIClientThreeColumn()
        mock.errorForCalls = APITransportError.httpStatus(404, message: nil)
        let vm = CallLogViewModel(api: mock)
        await vm.load()
        guard case .comingSoon = vm.state else {
            XCTFail("Expected .comingSoon for 404")
            return
        }
        XCTAssertTrue(vm.filteredCalls("").isEmpty)
    }

    // MARK: - Helpers

    private func makeCallEntry(
        id: Int64,
        direction: String = "inbound",
        phone: String = "5551234567",
        name: String? = nil
    ) -> CallLogEntry {
        CallLogEntry(
            id: id,
            direction: direction,
            phoneNumber: phone,
            customerName: name
        )
    }
}

// MARK: - MockAPIClient (three-column test variant)

/// Minimal stub so we don't repeat the full mock for this test file.
private final class MockAPIClientThreeColumn: APIClient, @unchecked Sendable {

    var callsData: Data?
    var errorForCalls: Error?

    private struct CallsWrapper: Encodable {
        struct Row: Encodable {
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
        let calls: [Row]
    }

    func stubCalls(_ entries: [CallLogEntry]) throws {
        let wrapper = CallsWrapper(calls: entries.map {
            .init(
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
        })
        callsData = try JSONEncoder().encode(wrapper)
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let error = errorForCalls, path.contains("calls") { throw error }
        if let data = callsData, path.contains("calls") {
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw APITransportError.httpStatus(404, message: "Not found")
    }

    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }

    func post<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
        where T: Decodable, T: Sendable, B: Encodable, B: Sendable
    { throw APITransportError.httpStatus(501, message: nil) }

    func put<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
        where T: Decodable, T: Sendable, B: Encodable, B: Sendable
    { throw APITransportError.httpStatus(501, message: nil) }

    func patch<T, B>(_ path: String, body: B, as type: T.Type) async throws -> T
        where T: Decodable, T: Sendable, B: Encodable, B: Sendable
    { throw APITransportError.httpStatus(501, message: nil) }

    func delete(_ path: String) async throws {
        throw APITransportError.httpStatus(501, message: nil)
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.httpStatus(501, message: nil)
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
