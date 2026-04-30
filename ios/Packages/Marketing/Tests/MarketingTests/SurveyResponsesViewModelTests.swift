import XCTest
@testable import Marketing
import Networking

// MARK: - §37.3 Survey response tracking tests

@MainActor
final class SurveyResponsesViewModelTests: XCTestCase {

    // MARK: load

    func test_load_happyPath_populatesResponses() async {
        let responses = [
            SurveyResponse(id: 1, kind: "csat", score: 5, comment: "Great!"),
            SurveyResponse(id: 2, kind: "nps", score: 8),
        ]
        let api = StubbedSurveyAPI(result: .success(responses))
        let vm = SurveyResponsesViewModel(api: api)

        await vm.load()

        XCTAssertEqual(vm.responses.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_empty_populatesEmpty() async {
        let api = StubbedSurveyAPI(result: .success([]))
        let vm = SurveyResponsesViewModel(api: api)

        await vm.load()

        XCTAssertTrue(vm.responses.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_failure_setsErrorMessage() async {
        let api = StubbedSurveyAPI(result: .failure(APITransportError.noBaseURL))
        let vm = SurveyResponsesViewModel(api: api)

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.responses.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_setsIsLoadingFalse_afterCompletion() async {
        let api = StubbedSurveyAPI(result: .success([]))
        let vm = SurveyResponsesViewModel(api: api)

        await vm.load()

        XCTAssertFalse(vm.isLoading)
    }

    // MARK: selectedKind filter

    func test_selectedKind_defaultIsNil() {
        let api = StubbedSurveyAPI(result: .success([]))
        let vm = SurveyResponsesViewModel(api: api)
        XCTAssertNil(vm.selectedKind)
    }

    func test_selectedKind_canBeSetToCsat() async {
        let api = StubbedSurveyAPI(result: .success([]))
        let vm = SurveyResponsesViewModel(api: api)
        vm.selectedKind = "csat"

        await vm.load()

        XCTAssertEqual(await api.lastKindPassed, "csat")
    }

    func test_selectedKind_canBeSetToNps() async {
        let api = StubbedSurveyAPI(result: .success([]))
        let vm = SurveyResponsesViewModel(api: api)
        vm.selectedKind = "nps"

        await vm.load()

        XCTAssertEqual(await api.lastKindPassed, "nps")
    }

    func test_selectedKind_nil_passesNilToApi() async {
        let api = StubbedSurveyAPI(result: .success([]))
        let vm = SurveyResponsesViewModel(api: api)
        vm.selectedKind = nil

        await vm.load()

        XCTAssertNil(await api.lastKindPassed)
    }
}

// MARK: - SurveyResponse model tests

final class SurveyResponseModelTests: XCTestCase {

    func test_surveyResponse_init() {
        let r = SurveyResponse(id: 1, kind: "csat", customerId: 42, customerName: "Alice",
                               score: 5, comment: "Excellent", submittedAt: "2026-04-26")
        XCTAssertEqual(r.id, 1)
        XCTAssertEqual(r.kind, "csat")
        XCTAssertEqual(r.customerId, 42)
        XCTAssertEqual(r.customerName, "Alice")
        XCTAssertEqual(r.score, 5)
        XCTAssertEqual(r.comment, "Excellent")
        XCTAssertEqual(r.submittedAt, "2026-04-26")
    }

    func test_surveyResponse_decoding() throws {
        let json = """
        {"id":99,"kind":"nps","customer_id":7,"customer_name":"Bob",
         "score":9,"comment":"Very likely","submitted_at":"2026-04-01"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(SurveyResponse.self, from: json)
        XCTAssertEqual(r.id, 99)
        XCTAssertEqual(r.kind, "nps")
        XCTAssertEqual(r.score, 9)
        XCTAssertEqual(r.customerName, "Bob")
    }

    func test_surveyResponse_hashable() {
        let a = SurveyResponse(id: 1, kind: "csat", score: 5)
        let b = SurveyResponse(id: 1, kind: "csat", score: 5)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }
}

// MARK: - Stub

actor StubbedSurveyAPI: APIClient {
    private(set) var lastKindPassed: String?? = nil // optional optional: outer=was set, inner=value

    private let result: Result<[SurveyResponse], Error>
    init(result: Result<[SurveyResponse], Error>) { self.result = result }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Capture the kind param
        if path.hasPrefix("/api/v1/surveys/responses") {
            let kindItem = query?.first(where: { $0.name == "kind" })
            lastKindPassed = kindItem?.value
        }
        switch result {
        case .success(let responses):
            guard let cast = responses as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let error):
            throw error
        }
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
