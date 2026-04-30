import XCTest
@testable import Leads
import Networking

// MARK: - LeadPipelineBulkArchiveTests
//
// §9.2 Bulk archive won/lost leads.

@MainActor
final class LeadPipelineBulkArchiveTests: XCTestCase {

    // MARK: - Optimistic update

    func test_bulkArchive_won_clearsWonColumn() async {
        let api = BulkArchiveStubAPI(leadCount: 3, stage: "won")
        let vm = LeadPipelineViewModel(api: api)
        await vm.load()

        XCTAssertEqual(vm.leads(in: .won).count, 3, "precondition: 3 won leads")

        // Start archive — optimistic update should clear column.
        await vm.bulkArchive(stage: .won)

        // Reload happens inside bulkArchive; stub returns 0 won leads after archive.
        XCTAssertEqual(vm.leads(in: .won).count, 0)
    }

    func test_bulkArchive_lost_clearsLostColumn() async {
        let api = BulkArchiveStubAPI(leadCount: 2, stage: "lost")
        let vm = LeadPipelineViewModel(api: api)
        await vm.load()

        XCTAssertEqual(vm.leads(in: .lost).count, 2, "precondition: 2 lost leads")

        await vm.bulkArchive(stage: .lost)

        XCTAssertEqual(vm.leads(in: .lost).count, 0)
    }

    func test_bulkArchive_new_doesNothing() async {
        let api = BulkArchiveStubAPI(leadCount: 1, stage: "new")
        let vm = LeadPipelineViewModel(api: api)
        await vm.load()

        let before = vm.leads(in: .new).count
        await vm.bulkArchive(stage: .new) // should be a no-op
        XCTAssertEqual(vm.leads(in: .new).count, before, "only won/lost can be bulk-archived")
    }

    func test_bulkArchive_callsUpdateStatus_forEachLead() async {
        let api = BulkArchiveStubAPI(leadCount: 4, stage: "won")
        let vm = LeadPipelineViewModel(api: api)
        await vm.load()

        await vm.bulkArchive(stage: .won)

        let callCount = await api.updateStatusCallCount
        XCTAssertEqual(callCount, 4, "must patch 4 leads to archived status")

        let lastStatus = await api.lastArchivedStatus
        XCTAssertEqual(lastStatus, "archived", "must patch status to 'archived'")
    }

    func test_bulkArchive_emptyColumn_doesNothing() async {
        let api = BulkArchiveStubAPI(leadCount: 0, stage: "won")
        let vm = LeadPipelineViewModel(api: api)
        await vm.load()

        await vm.bulkArchive(stage: .won)

        let callCount = await api.updateStatusCallCount
        XCTAssertEqual(callCount, 0, "nothing to archive — no API calls")
    }
}

// MARK: - BulkArchiveStubAPI

/// Minimal stub that populates one column and tracks updateLeadStatus calls.
private actor BulkArchiveStubAPI: APIClient {
    private var leadCount: Int
    private let stage: String
    private var archived: Bool = false

    private(set) var updateStatusCallCount: Int = 0
    private(set) var lastArchivedStatus: String?

    init(leadCount: Int, stage: String) {
        self.leadCount = leadCount
        self.stage = stage
    }

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // /api/v1/leads — return stub leads
        let leads = makeLeads()
        let wrapper = LeadListWrapper(leads: leads)
        let data = try JSONEncoder().encode(wrapper)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        // Capture the archived status update.
        if let body = body as? LeadStatusUpdateBody {
            updateStatusCallCount += 1
            lastArchivedStatus = body.status
        }
        // After archive, return empty leads list so reload shows 0 in column.
        archived = true
        let leadDetail = makeLeadDetail(status: "archived")
        guard let cast = leadDetail as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    // MARK: - Helpers

    private func makeLeads() -> [Lead] {
        guard !archived else { return [] }
        return (0..<leadCount).map { index in
            let json = """
            { "id": \(index), "first_name": "Lead", "last_name": "\(index)", "status": "\(stage)" }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(Lead.self, from: json)
        }
    }

    private func makeLeadDetail(status: String) -> LeadDetail {
        let json = """
        { "id": 0, "status": "\(status)", "devices": [], "appointments": [] }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LeadDetail.self, from: json)
    }
}

// Minimal wrapper matching server list shape.
private struct LeadListWrapper: Encodable {
    let leads: [Lead]
}
