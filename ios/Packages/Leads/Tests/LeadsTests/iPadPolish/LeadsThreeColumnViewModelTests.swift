import XCTest
@testable import Leads
@testable import Networking

// MARK: - LeadsThreeColumnViewModelTests

@MainActor
final class LeadsThreeColumnViewModelTests: XCTestCase {

    // MARK: - load

    func test_load_populatesLeads() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, status: "new"),
            .fixture(id: 2, status: "contacted"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.leads.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsIsLoadingFalseOnSuccess() async {
        let api = ThreeColMockAPI(leads: [.fixture(id: 1, status: "new")])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_setsErrorMessageOnFailure() async {
        let api = ThreeColMockAPI(leads: [], shouldFail: true)
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.leads.isEmpty)
    }

    func test_load_updatesSidebarCounts() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, status: "new"),
            .fixture(id: 2, status: "new"),
            .fixture(id: 3, status: "lost"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.sidebar.count(for: .new), 2)
        XCTAssertEqual(vm.sidebar.count(for: .lost), 1)
    }

    // MARK: - forceRefresh

    func test_forceRefresh_updatesLeads() async {
        let api = ThreeColMockAPI(leads: [.fixture(id: 1, status: "qualified")])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.leads.count, 1)

        await api.setLeads([
            .fixture(id: 1, status: "qualified"),
            .fixture(id: 2, status: "converted"),
        ])
        await vm.forceRefresh()
        XCTAssertEqual(vm.leads.count, 2)
    }

    // MARK: - filteredLeads

    func test_filteredLeads_noFilter_returnsAll() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, status: "new"),
            .fixture(id: 2, status: "lost"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.filteredLeads.count, 2)
    }

    func test_filteredLeads_sidebarFilter_narrowsToStatus() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, status: "new"),
            .fixture(id: 2, status: "new"),
            .fixture(id: 3, status: "lost"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.sidebar.selectedStatus = .new
        XCTAssertEqual(vm.filteredLeads.count, 2)
    }

    func test_filteredLeads_sidebarFilter_lost() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, status: "new"),
            .fixture(id: 2, status: "lost"),
            .fixture(id: 3, status: "lost"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.sidebar.selectedStatus = .lost
        XCTAssertEqual(vm.filteredLeads.count, 2)
    }

    func test_filteredLeads_sidebarFilter_emptyForNonMatchingStatus() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.sidebar.selectedStatus = .converted
        XCTAssertEqual(vm.filteredLeads.count, 0)
    }

    func test_filteredLeads_searchQuery_filtersByName() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, firstName: "Alice", status: "new"),
            .fixture(id: 2, firstName: "Bob", status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.searchQuery = "alice"
        XCTAssertEqual(vm.filteredLeads.count, 1)
        XCTAssertEqual(vm.filteredLeads.first?.firstName, "Alice")
    }

    func test_filteredLeads_searchAndStatusFilter_combined() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 1, firstName: "Alice", status: "new"),
            .fixture(id: 2, firstName: "Alice", status: "lost"),
            .fixture(id: 3, firstName: "Bob", status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.sidebar.selectedStatus = .new
        vm.searchQuery = "alice"
        XCTAssertEqual(vm.filteredLeads.count, 1)
        XCTAssertEqual(vm.filteredLeads.first?.id, 1)
    }

    // MARK: - selectNext / selectPrevious

    func test_selectNext_fromNil_selectsFirst() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 10, status: "new"),
            .fixture(id: 11, status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        XCTAssertNil(vm.selectedLeadId)
        vm.selectNext()
        XCTAssertEqual(vm.selectedLeadId, 10)
    }

    func test_selectNext_advancesToNextLead() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 10, status: "new"),
            .fixture(id: 11, status: "new"),
            .fixture(id: 12, status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.selectedLeadId = 10
        vm.selectNext()
        XCTAssertEqual(vm.selectedLeadId, 11)
    }

    func test_selectNext_atLastItem_doesNotWrap() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 10, status: "new"),
            .fixture(id: 11, status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.selectedLeadId = 11
        vm.selectNext()
        XCTAssertEqual(vm.selectedLeadId, 11, "Should stay on last item")
    }

    func test_selectPrevious_fromFirstItem_doesNotWrap() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 10, status: "new"),
            .fixture(id: 11, status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.selectedLeadId = 10
        vm.selectPrevious()
        XCTAssertEqual(vm.selectedLeadId, 10, "Should stay on first item")
    }

    func test_selectPrevious_movesBackward() async {
        let api = ThreeColMockAPI(leads: [
            .fixture(id: 10, status: "new"),
            .fixture(id: 11, status: "new"),
        ])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.selectedLeadId = 11
        vm.selectPrevious()
        XCTAssertEqual(vm.selectedLeadId, 10)
    }

    func test_selectNext_emptyList_isNoop() async {
        let api = ThreeColMockAPI(leads: [])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.selectNext()
        XCTAssertNil(vm.selectedLeadId)
    }

    // MARK: - handleContextAction: changeStatus

    func test_handleContextAction_changeStatus_callsAPI() async {
        let api = ThreeColMockAPI(leads: [.fixture(id: 1, status: "new")])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        let lead = vm.leads.first!
        await vm.handleContextAction(.changeStatus("qualified"), for: lead)
        let callCount = await api.updateStatusCallCount
        XCTAssertEqual(callCount, 1)
    }

    func test_handleContextAction_changeStatus_failure_setsErrorMessage() async {
        let api = ThreeColMockAPI(leads: [.fixture(id: 1, status: "new")], updateShouldFail: true)
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        let lead = vm.leads.first!
        await vm.handleContextAction(.changeStatus("qualified"), for: lead)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - handleContextAction: archive

    func test_handleContextAction_archive_clearsSelectedLeadIfMatching() async {
        let api = ThreeColMockAPI(leads: [.fixture(id: 1, status: "new")])
        let vm = LeadsThreeColumnViewModel(api: api)
        await vm.load()
        vm.selectedLeadId = 1
        let lead = vm.leads.first!
        await vm.handleContextAction(.archive, for: lead)
        let callCount = await api.loseLeadCallCount
        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - ThreeColMockAPI

actor ThreeColMockAPI: APIClient {
    private var stubbedLeads: [Lead]
    private let shouldFail: Bool
    private let updateShouldFail: Bool
    private(set) var updateStatusCallCount = 0
    private(set) var loseLeadCallCount = 0

    init(leads: [Lead], shouldFail: Bool = false, updateShouldFail: Bool = false) {
        self.stubbedLeads = leads
        self.shouldFail = shouldFail
        self.updateShouldFail = updateShouldFail
    }

    func setLeads(_ leads: [Lead]) {
        stubbedLeads = leads
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldFail { throw APITransportError.noBaseURL }
        if path == "/api/v1/leads" {
            let r = LeadsListResponse(leads: stubbedLeads)
            guard let cast = r as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if updateShouldFail { throw APITransportError.noBaseURL }
        updateStatusCallCount += 1
        // Return a minimal LeadDetail JSON decode for the first stub lead.
        guard let first = stubbedLeads.first else { throw APITransportError.noBaseURL }
        let dict: [String: Any] = [
            "id": first.id,
            "devices": [] as [Any],
            "appointments": [] as [Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let detail = try JSONDecoder().decode(LeadDetail.self, from: data)
        guard let cast = detail as? T else { throw APITransportError.decoding("type") }
        return cast
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if updateShouldFail { throw APITransportError.noBaseURL }
        // Handle /lose endpoint
        if path.hasSuffix("/lose") {
            loseLeadCallCount += 1
            let r = LeadLoseResponse(success: true)
            guard let cast = r as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        // Handle /convert endpoint
        if path.hasSuffix("/convert") {
            guard let first = stubbedLeads.first else { throw APITransportError.noBaseURL }
            let dict: [String: Any] = [
                "ticket": ["id": 99, "order_id": NSNull(), "customer_id": NSNull()] as [String: Any],
                "message": "converted"
            ]
            let data = try JSONSerialization.data(withJSONObject: dict)
            let r = try JSONDecoder().decode(LeadConvertResponse.self, from: data)
            _ = first
            guard let cast = r as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Lead fixture helpers (local to this file)

private extension Lead {
    static func fixture(
        id: Int64 = 1,
        firstName: String = "Jane",
        lastName: String = "Doe",
        status: String? = nil
    ) -> Lead {
        Lead(id: id, firstName: firstName, lastName: lastName, status: status)
    }
}
