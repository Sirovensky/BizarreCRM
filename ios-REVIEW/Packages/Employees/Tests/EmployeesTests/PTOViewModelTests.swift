import XCTest
@testable import Employees
import Networking

// MARK: - MockAPIClientForPTO

final class MockAPIClientForPTO: APIClient, @unchecked Sendable {
    var stubbedPTORequests: [PTORequest] = []
    var stubbedScorecard: EmployeeScorecard = EmployeeScorecard(employeeId: "e1")
    var shouldThrow = false
    var reviewedRequests: [(String, ReviewPTORequest)] = []
    var createdPTO: [CreatePTORequest] = []

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldThrow { throw NSError(domain: "mock", code: 1) }
        if T.self == PTOListResponse.self {
            return PTOListResponse(requests: stubbedPTORequests) as! T
        }
        if T.self == ScorecardResponse.self {
            return ScorecardResponse(scorecard: stubbedScorecard) as! T
        }
        throw NSError(domain: "mock", code: 99)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldThrow { throw NSError(domain: "mock", code: 1) }
        if let req = body as? CreatePTORequest {
            createdPTO.append(req)
            let ptoResp = PTORequest(id: "new-pto", employeeId: req.employeeId,
                                     type: req.type, startDate: req.startDate,
                                     endDate: req.endDate, reason: req.reason)
            return PTOResponse(request: ptoResp) as! T
        }
        throw NSError(domain: "mock", code: 99)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw NSError(domain: "mock", code: 99)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldThrow { throw NSError(domain: "mock", code: 1) }
        if let req = body as? ReviewPTORequest {
            reviewedRequests.append((path, req))
            let id = path.components(separatedBy: "/").dropLast().last ?? "x"
            let pto = PTORequest(id: id, employeeId: "e1", type: .vacation,
                                 startDate: Date(), endDate: Date(), status: req.status)
            return PTOResponse(request: pto) as! T
        }
        throw NSError(domain: "mock", code: 99)
    }

    func delete(_ path: String) async throws {
        if shouldThrow { throw NSError(domain: "mock", code: 1) }
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw NSError(domain: "mock", code: 99)
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

// MARK: - PTOApprovalListViewModelTests

@MainActor
final class PTOApprovalListViewModelTests: XCTestCase {

    private func makeRequest(id: String = "r1") -> PTORequest {
        PTORequest(id: id, employeeId: "emp1", type: .vacation,
                   startDate: Date(), endDate: Date().addingTimeInterval(86400 * 3))
    }

    func test_load_populatesPending() async {
        let api = MockAPIClientForPTO()
        api.stubbedPTORequests = [makeRequest(id: "r1"), makeRequest(id: "r2")]
        let vm = PTOApprovalListViewModel(api: api, managerId: "mgr1")
        await vm.load()
        XCTAssertEqual(vm.pending.count, 2)
    }

    func test_load_setsErrorOnFailure() async {
        let api = MockAPIClientForPTO()
        api.shouldThrow = true
        let vm = PTOApprovalListViewModel(api: api, managerId: "mgr1")
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_approve_removesFromPending() async {
        let api = MockAPIClientForPTO()
        let req = makeRequest(id: "approve-me")
        api.stubbedPTORequests = [req]
        let vm = PTOApprovalListViewModel(api: api, managerId: "mgr1")
        await vm.load()
        await vm.approve(request: req)
        XCTAssertTrue(vm.pending.isEmpty)
    }

    func test_deny_removesFromPending() async {
        let api = MockAPIClientForPTO()
        let req = makeRequest(id: "deny-me")
        api.stubbedPTORequests = [req]
        let vm = PTOApprovalListViewModel(api: api, managerId: "mgr1")
        await vm.load()
        await vm.deny(request: req)
        XCTAssertTrue(vm.pending.isEmpty)
    }
}

// MARK: - PTORequestSheetViewModelTests

@MainActor
final class PTORequestSheetViewModelTests: XCTestCase {

    func test_submit_createsRequest() async {
        let api = MockAPIClientForPTO()
        var saved: PTORequest?
        let vm = PTORequestSheetViewModel(api: api, employeeId: "emp1") { req in
            saved = req
        }
        vm.ptoType = .vacation
        vm.startDate = Date()
        vm.endDate = Date().addingTimeInterval(86400 * 3)
        vm.reason = "Family trip"

        await vm.submit()

        XCTAssertNotNil(saved)
        XCTAssertEqual(api.createdPTO.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_failsWhenEndBeforeStart() async {
        let api = MockAPIClientForPTO()
        let vm = PTORequestSheetViewModel(api: api, employeeId: "emp1") { _ in }
        vm.startDate = Date()
        vm.endDate = Date().addingTimeInterval(-86400)
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
    }
}

// MARK: - ScorecardViewModelTests

@MainActor
final class ScorecardViewModelTests: XCTestCase {

    func test_load_populatesScorecard() async {
        let api = MockAPIClientForPTO()
        api.stubbedScorecard = EmployeeScorecard(
            employeeId: "emp1",
            ticketCloseRate: 0.9,
            slaCompliance: 0.85,
            avgCustomerRating: 4.2
        )
        let vm = ScorecardViewModel(api: api, employeeId: "emp1")
        await vm.load()
        XCTAssertNotNil(vm.scorecard)
        XCTAssertEqual(vm.scorecard?.ticketCloseRate ?? 0, 0.9, accuracy: 0.001)
    }

    func test_compositeScore_nonZero() async {
        let api = MockAPIClientForPTO()
        api.stubbedScorecard = EmployeeScorecard(
            employeeId: "e1",
            ticketCloseRate: 0.8,
            slaCompliance: 0.8,
            avgCustomerRating: 4.0
        )
        let vm = ScorecardViewModel(api: api, employeeId: "e1")
        await vm.load()
        XCTAssertGreaterThan(vm.compositeScore, 0)
    }

    func test_load_setsErrorOnFailure() async {
        let api = MockAPIClientForPTO()
        api.shouldThrow = true
        let vm = ScorecardViewModel(api: api, employeeId: "e1")
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.scorecard)
    }
}
