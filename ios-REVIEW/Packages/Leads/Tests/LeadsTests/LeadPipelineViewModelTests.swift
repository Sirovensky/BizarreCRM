import XCTest
@testable import Leads
@testable import Networking

final class LeadPipelineViewModelTests: XCTestCase {

    // MARK: - Stage grouping

    func test_grouping_byStatus() async throws {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: "new"),
            .fixture(id: 2, status: "qualified"),
            .fixture(id: 3, status: "won"),
            .fixture(id: 4, status: "new"),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        await MainActor.run {
            XCTAssertEqual(vm.leads(in: .new).count, 2)
            XCTAssertEqual(vm.leads(in: .qualified).count, 1)
            XCTAssertEqual(vm.leads(in: .won).count, 1)
            XCTAssertEqual(vm.leads(in: .lost).count, 0)
        }
    }

    func test_unknownStatus_fallsToNew() async {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: "foobar"),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        await MainActor.run {
            XCTAssertEqual(vm.leads(in: .new).count, 1)
        }
    }

    func test_nilStatus_fallsToNew() async {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: nil),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        await MainActor.run {
            XCTAssertEqual(vm.leads(in: .new).count, 1)
        }
    }

    func test_emptyLeads_allColumnsEmpty() async {
        let api = MockPipelineAPI(leads: [])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        await MainActor.run {
            for stage in PipelineStage.allCases {
                XCTAssertEqual(vm.leads(in: stage).count, 0, "Expected empty column for \(stage.displayName)")
            }
        }
    }

    // MARK: - Source filter

    func test_sourceFilter_narrowsResults() async {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: "new", source: "web"),
            .fixture(id: 2, status: "new", source: "referral"),
            .fixture(id: 3, status: "new", source: "web"),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        await MainActor.run {
            vm.setSourceFilter("web")
            XCTAssertEqual(vm.leads(in: .new).count, 2)
        }
    }

    func test_clearSourceFilter_showsAll() async {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: "new", source: "web"),
            .fixture(id: 2, status: "new", source: "referral"),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        await MainActor.run {
            vm.setSourceFilter("web")
            XCTAssertEqual(vm.leads(in: .new).count, 1)
            vm.setSourceFilter(nil)
            XCTAssertEqual(vm.leads(in: .new).count, 2)
        }
    }

    // MARK: - Drag-drop (optimistic update)

    func test_moveCard_optimisticallyUpdatesColumn() async {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: "new"),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        let lead = await MainActor.run { vm.leads(in: .new).first! }
        await vm.moveCard(lead: lead, to: .qualified)
        await MainActor.run {
            XCTAssertEqual(vm.leads(in: .new).count, 0)
            XCTAssertEqual(vm.leads(in: .qualified).count, 1)
        }
    }

    func test_moveCard_toSameStage_noOp() async {
        let api = MockPipelineAPI(leads: [
            .fixture(id: 1, status: "new"),
        ])
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        let lead = await MainActor.run { vm.leads(in: .new).first! }
        await vm.moveCard(lead: lead, to: .new) // same stage
        await MainActor.run {
            XCTAssertEqual(vm.leads(in: .new).count, 1, "Move to same stage should be a no-op")
        }
    }

    func test_moveCard_apiFailure_rollsBack() async {
        let api = MockPipelineAPI(leads: [.fixture(id: 1, status: "new")], updateShouldFail: true)
        let vm = await LeadPipelineViewModel(api: api)
        await vm.load()
        let lead = await MainActor.run { vm.leads(in: .new).first! }
        await vm.moveCard(lead: lead, to: .qualified)
        // After rollback (reload from API), the lead is back in 'new'.
        await MainActor.run {
            XCTAssertEqual(vm.leads(in: .new).count, 1)
            XCTAssertEqual(vm.leads(in: .qualified).count, 0)
        }
    }
}

// MARK: - PipelineStage.from tests

final class PipelineStageTests: XCTestCase {

    func test_fromStatus_caseInsensitive() {
        XCTAssertEqual(PipelineStage.from(status: "QUALIFIED"), .qualified)
        XCTAssertEqual(PipelineStage.from(status: "Quoted"),    .quoted)
        XCTAssertEqual(PipelineStage.from(status: "WON"),       .won)
    }

    func test_fromStatus_nilFallsToNew() {
        XCTAssertEqual(PipelineStage.from(status: nil), .new)
    }

    func test_allStages_haveDisplayName() {
        for stage in PipelineStage.allCases {
            XCTAssertFalse(stage.displayName.isEmpty)
        }
    }
}

// MARK: - Mock API

actor MockPipelineAPI: APIClient {
    private let stubbedLeads: [Lead]
    private let updateShouldFail: Bool

    init(leads: [Lead], updateShouldFail: Bool = false) {
        self.stubbedLeads = leads
        self.updateShouldFail = updateShouldFail
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasPrefix("/api/v1/leads/followups") {
            let empty: [LeadFollowUpResponse] = []
            guard let r = empty as? T else { throw APITransportError.decoding("type") }
            return r
        }
        if path == "/api/v1/leads" {
            let r = LeadsListResponse(leads: stubbedLeads)
            guard let cast = r as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if updateShouldFail { throw APITransportError.noBaseURL }
        // Return first stubbed lead as detail (simplification for test).
        guard let first = stubbedLeads.first else { throw APITransportError.noBaseURL }
        // Build minimal LeadDetail from the stub.
        let detail = try buildDetail(from: first)
        guard let cast = detail as? T else { throw APITransportError.decoding("type") }
        return cast
    }

    private func buildDetail(from lead: Lead) throws -> LeadDetail {
        let dict: [String: Any] = [
            "id": lead.id,
            "first_name": lead.firstName as Any,
            "last_name": lead.lastName as Any,
            "devices": [] as [Any],
            "appointments": [] as [Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(LeadDetail.self, from: data)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Lead fixture extension (with source)

extension Lead {
    static func fixture(
        id: Int64 = 1,
        firstName: String = "Jane",
        lastName: String = "Doe",
        status: String? = nil,
        source: String? = nil
    ) -> Lead {
        Lead(id: id, firstName: firstName, lastName: lastName, status: status, source: source)
    }
}
