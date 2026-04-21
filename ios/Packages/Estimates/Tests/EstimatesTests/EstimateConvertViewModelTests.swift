import XCTest
@testable import Estimates
import Networking
import Core

// MARK: - EstimateConvertViewModelTests
// TDD: written before EstimateConvertViewModel was implemented.

@MainActor
final class EstimateConvertViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeEstimate(id: Int64 = 1, status: String = "sent") -> Estimate {
        // Build via CodingKeys-compatible decoder workaround
        let dict: [String: Any] = [
            "id": id,
            "order_id": "EST-00\(id)",
            "customer_first_name": "John",
            "customer_last_name": "Doe",
            "total": 249.99,
            "status": status
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Estimate.self, from: data)
    }

    private func makeSUT(
        result: Result<ConvertEstimateResponse, Error> = .success(ConvertEstimateResponse(ticketId: 42)),
        onSuccess: @escaping @MainActor (Int64) -> Void = { _ in }
    ) -> EstimateConvertViewModel {
        let api = ConvertStubAPIClient(result: result)
        return EstimateConvertViewModel(estimate: makeEstimate(), api: api, onSuccess: onSuccess)
    }

    // MARK: - Initial state

    func test_initialState_notConverting() {
        let vm = makeSUT()
        XCTAssertFalse(vm.isConverting)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.createdTicketId)
    }

    func test_customerName_fromEstimate() {
        let vm = makeSUT()
        XCTAssertEqual(vm.customerName, "John Doe")
    }

    func test_orderId_fromEstimate() {
        let vm = makeSUT()
        XCTAssertEqual(vm.orderId, "EST-001")
    }

    func test_totalFormatted_nonEmpty() {
        let vm = makeSUT()
        XCTAssertFalse(vm.totalFormatted.isEmpty)
        XCTAssertTrue(vm.totalFormatted.contains("249"))
    }

    // MARK: - Happy path

    func test_convert_success_setsCreatedTicketId() async {
        var callbackId: Int64?
        let vm = makeSUT(result: .success(ConvertEstimateResponse(ticketId: 99))) { id in
            callbackId = id
        }
        await vm.convert()
        XCTAssertEqual(vm.createdTicketId, 99)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(callbackId, 99)
    }

    func test_convert_success_notConverting_after() async {
        let vm = makeSUT(result: .success(ConvertEstimateResponse(ticketId: 1)))
        await vm.convert()
        XCTAssertFalse(vm.isConverting)
    }

    // MARK: - Error paths

    func test_convert_conflict_showsAlreadyConvertedMessage() async {
        let vm = makeSUT(result: .failure(APITransportError.httpStatus(409, message: "conflict")))
        await vm.convert()
        XCTAssertNil(vm.createdTicketId)
        XCTAssertEqual(vm.errorMessage, "This estimate has already been converted to a ticket.")
    }

    func test_convert_notFound_showsNotFoundMessage() async {
        let vm = makeSUT(result: .failure(APITransportError.httpStatus(404, message: nil)))
        await vm.convert()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_convert_offline_showsOfflineMessage() async {
        let vm = makeSUT(result: .failure(AppError.offline))
        await vm.convert()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("offline") == true || vm.errorMessage?.contains("offline") == true)
    }

    func test_convert_genericError_showsMessage() async {
        let vm = makeSUT(result: .failure(APITransportError.networkUnavailable))
        await vm.convert()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Idempotency guard

    func test_convert_calledTwice_doesNotDoubleSubmit() async {
        let stub = ConvertStubAPIClient(result: .success(ConvertEstimateResponse(ticketId: 5)))
        let vm = EstimateConvertViewModel(estimate: makeEstimate(), api: stub) { _ in }
        // Fire both concurrently; only first should proceed
        async let a: Void = vm.convert()
        async let b: Void = vm.convert()
        _ = await (a, b)
        let count = await stub.callCount
        XCTAssertEqual(count, 1)
    }
}

// MARK: - ConvertStubAPIClient

private actor ConvertStubAPIClient: APIClient {
    private(set) var callCount: Int = 0
    private let result: Result<ConvertEstimateResponse, Error>

    init(result: Result<ConvertEstimateResponse, Error>) {
        self.result = result
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        callCount += 1
        switch result {
        case .success(let r):
            guard let t = r as? T else { throw APITransportError.decoding("type mismatch") }
            return t
        case .failure(let e):
            throw e
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
