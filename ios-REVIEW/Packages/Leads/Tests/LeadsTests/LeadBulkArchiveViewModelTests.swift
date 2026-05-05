import XCTest
@testable import Leads
import Networking

// MARK: - §9.2 Bulk archive unit tests

@MainActor
final class LeadBulkArchiveViewModelTests: XCTestCase {

    // MARK: computePreview

    func test_computePreview_wonAndLost_countsCorrectly() {
        let leads = [
            Lead.stub(id: 1, status: "converted"),
            Lead.stub(id: 2, status: "lost"),
            Lead.stub(id: 3, status: "new"),
            Lead.stub(id: 4, status: "converted"),
        ]
        let api = FailingLeadStubAPI()
        let vm = LeadBulkArchiveViewModel(api: api, allLeads: leads)
        vm.selectedScope = .wonAndLost
        vm.computePreview()
        XCTAssertEqual(vm.affectedCount, 3)
    }

    func test_computePreview_wonOnly_excludesLost() {
        let leads = [
            Lead.stub(id: 1, status: "converted"),
            Lead.stub(id: 2, status: "lost"),
        ]
        let vm = LeadBulkArchiveViewModel(api: FailingLeadStubAPI(), allLeads: leads)
        vm.selectedScope = .wonOnly
        vm.computePreview()
        XCTAssertEqual(vm.affectedCount, 1)
    }

    func test_computePreview_lostOnly_excludesConverted() {
        let leads = [
            Lead.stub(id: 1, status: "converted"),
            Lead.stub(id: 2, status: "lost"),
            Lead.stub(id: 3, status: "lost"),
        ]
        let vm = LeadBulkArchiveViewModel(api: FailingLeadStubAPI(), allLeads: leads)
        vm.selectedScope = .lostOnly
        vm.computePreview()
        XCTAssertEqual(vm.affectedCount, 2)
    }

    func test_computePreview_empty_isZero() {
        let vm = LeadBulkArchiveViewModel(api: FailingLeadStubAPI(), allLeads: [])
        vm.selectedScope = .wonAndLost
        vm.computePreview()
        XCTAssertEqual(vm.affectedCount, 0)
    }

    // MARK: archive - success

    func test_archive_success_phaseIsDone() async {
        let leads = [
            Lead.stub(id: 1, status: "converted"),
            Lead.stub(id: 2, status: "lost"),
        ]
        let api = SucceedingLeadStubAPI()
        let vm = LeadBulkArchiveViewModel(api: api, allLeads: leads)
        vm.selectedScope = .wonAndLost
        vm.computePreview()

        await vm.archive()

        if case .done(let count) = vm.phase {
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("Expected .done(2), got \(vm.phase)")
        }
    }

    func test_archive_emptySet_phaseIsDoneZero() async {
        let vm = LeadBulkArchiveViewModel(api: FailingLeadStubAPI(), allLeads: [])
        vm.selectedScope = .wonAndLost
        vm.computePreview()

        await vm.archive()

        if case .done(let count) = vm.phase {
            XCTAssertEqual(count, 0)
        } else {
            XCTFail("Expected .done(0), got \(vm.phase)")
        }
    }

    // MARK: BulkArchiveScope

    func test_bulkArchiveScope_allCases() {
        XCTAssertEqual(BulkArchiveScope.allCases.count, 3)
    }
}

// MARK: - Lead stub factory

private extension Lead {
    static func stub(id: Int64, status: String) -> Lead {
        Lead(
            id: id,
            orderId: nil,
            firstName: "Lead",
            lastName: "\(id)",
            status: status,
            leadScore: 50
        )
    }
}

// MARK: - Minimal APIClient stubs for Lead tests

private actor FailingLeadStubAPI: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor SucceedingLeadStubAPI: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Return a minimal LeadDetail for any PUT /api/v1/leads/... call
        let json = """
        {"id":1,"status":"archived","first_name":null,"last_name":null,"email":null,
         "phone":null,"source":null,"notes":null,"lead_score":50,
         "assigned_first_name":null,"assigned_last_name":null,
         "customer_id":null,"customer_first_name":null,"customer_last_name":null,
         "created_at":null,"updated_at":null,"devices":[],"appointments":[]}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let detail = try decoder.decode(LeadDetail.self, from: json)
        guard let cast = detail as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
