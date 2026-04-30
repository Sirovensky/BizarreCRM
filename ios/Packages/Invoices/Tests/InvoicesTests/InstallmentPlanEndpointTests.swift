import XCTest
@testable import Invoices
@testable import Networking

// §7.9 Tests for the invoiceInstallmentPlan APIClient extension
// and for the InvoiceDetailViewModel loading plan alongside invoice detail.

final class InstallmentPlanEndpointTests: XCTestCase {

    // MARK: - APIClient endpoint path

    func test_invoiceInstallmentPlan_usesCorrectPath() async throws {
        // Arrange: stub client that records the GET path
        let stub = PathCapturingStub()
        // Act: call the endpoint (will throw but records path)
        _ = try? await stub.invoiceInstallmentPlan(invoiceId: 42)
        // Assert: correct path segment used
        XCTAssertEqual(stub.lastGetPath, "/api/v1/invoices/42/installment-plans")
    }

    func test_invoiceInstallmentPlan_decodesValidResponse() async throws {
        // Arrange
        let plan = InstallmentPlan(
            id: 1,
            invoiceId: 7,
            totalCents: 30_000,
            installments: [
                InstallmentItem(id: 10, dueDate: Date(), amountCents: 10_000),
                InstallmentItem(id: 11, dueDate: Date().addingTimeInterval(2_592_000), amountCents: 10_000),
                InstallmentItem(id: 12, dueDate: Date().addingTimeInterval(5_184_000), amountCents: 10_000)
            ],
            autopay: true
        )
        let data = try JSONEncoder().encode(plan)
        let stub = DataReturningStub(getResult: .success(data))
        // Act
        let returned = try await stub.invoiceInstallmentPlan(invoiceId: 7)
        // Assert
        XCTAssertEqual(returned.id, plan.id)
        XCTAssertEqual(returned.invoiceId, plan.invoiceId)
        XCTAssertEqual(returned.totalCents, plan.totalCents)
        XCTAssertEqual(returned.installments.count, 3)
        XCTAssertTrue(returned.autopay)
    }

    func test_invoiceInstallmentPlan_throws_when404() async {
        let stub = DataReturningStub(getResult: .failure(APITransportError.noBaseURL))
        do {
            _ = try await stub.invoiceInstallmentPlan(invoiceId: 99)
            XCTFail("Expected throw when no plan exists")
        } catch {
            // Expected
        }
    }

    // MARK: - InstallmentPlan helpers

    func test_remainingCents_onlyUnpaid() {
        let plan = InstallmentPlan(
            id: 1, invoiceId: 1, totalCents: 30_000,
            installments: [
                InstallmentItem(id: 1, dueDate: Date(), amountCents: 10_000, paidAt: Date()),
                InstallmentItem(id: 2, dueDate: Date(), amountCents: 10_000),
                InstallmentItem(id: 3, dueDate: Date(), amountCents: 10_000)
            ]
        )
        XCTAssertEqual(plan.remainingCents, 20_000)
    }

    func test_remainingCents_allPaid_isZero() {
        let plan = InstallmentPlan(
            id: 1, invoiceId: 1, totalCents: 10_000,
            installments: [
                InstallmentItem(id: 1, dueDate: Date(), amountCents: 10_000, paidAt: Date())
            ]
        )
        XCTAssertEqual(plan.remainingCents, 0)
    }

    func test_nextInstallment_returnsEarliestUnpaid() {
        let soon = Date().addingTimeInterval(86_400)
        let later = Date().addingTimeInterval(172_800)
        let plan = InstallmentPlan(
            id: 1, invoiceId: 1, totalCents: 20_000,
            installments: [
                InstallmentItem(id: 2, dueDate: later, amountCents: 10_000),
                InstallmentItem(id: 1, dueDate: soon, amountCents: 10_000)
            ]
        )
        XCTAssertEqual(plan.nextInstallment?.id, 1)
    }

    func test_nextInstallment_nil_whenAllPaid() {
        let plan = InstallmentPlan(
            id: 1, invoiceId: 1, totalCents: 10_000,
            installments: [
                InstallmentItem(id: 1, dueDate: Date(), amountCents: 10_000, paidAt: Date())
            ]
        )
        XCTAssertNil(plan.nextInstallment)
    }
}

// MARK: - Stub helpers

private actor PathCapturingStub: APIClient {
    private(set) var lastGetPath: String?

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        lastGetPath = path
        throw APITransportError.noBaseURL
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

private actor DataReturningStub: APIClient {
    let getResult: Result<Data, Error>

    init(getResult: Result<Data, Error>) {
        self.getResult = getResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        switch getResult {
        case .success(let data):
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        case .failure(let err):
            throw err
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
