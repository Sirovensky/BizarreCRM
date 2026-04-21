import XCTest
@testable import RepairPricing
import Networking

/// §43.3 — PriceOverrideEditorViewModel unit tests.
@MainActor
final class PriceOverrideEditorViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_defaultsCorrect() {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        XCTAssertEqual(vm.scope, .tenant)
        XCTAssertEqual(vm.customerId, "")
        XCTAssertEqual(vm.rawPrice, "")
        XCTAssertEqual(vm.reason, "")
        XCTAssertFalse(vm.isSaving)
        XCTAssertNil(vm.saveError)
        XCTAssertNil(vm.savedOverride)
    }

    // MARK: - Validation in save

    func test_save_emptyPrice_setsError() async {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        await vm.save()
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedOverride)
    }

    func test_save_invalidPrice_setsError() async {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        vm.rawPrice = "notanumber"
        await vm.save()
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedOverride)
    }

    func test_save_customerScopeWithNoCustomerId_setsError() async {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        vm.scope = .customer
        vm.rawPrice = "29.99"
        vm.customerId = ""
        await vm.save()
        XCTAssertNotNil(vm.saveError)
    }

    // MARK: - Successful save

    func test_save_validTenantScope_populatesSaved() async {
        let stub = OverrideAPIStub(shouldSucceed: true)
        let vm = PriceOverrideEditorViewModel(api: stub, serviceId: "svc-42")
        vm.scope = .tenant
        vm.rawPrice = "49.99"
        vm.reason = "Promo"
        await vm.save()
        XCTAssertNil(vm.saveError)
        XCTAssertNotNil(vm.savedOverride)
        XCTAssertEqual(stub.capturedServiceId, "svc-42")
    }

    func test_save_validCustomerScope_includesCustomerId() async {
        let stub = OverrideAPIStub(shouldSucceed: true)
        let vm = PriceOverrideEditorViewModel(api: stub, serviceId: "svc-7")
        vm.scope = .customer
        vm.rawPrice = "19.99"
        vm.customerId = "cust-abc"
        await vm.save()
        XCTAssertNil(vm.saveError)
        XCTAssertEqual(stub.capturedCustomerId, "cust-abc")
    }

    func test_save_apiFailure_setsError() async {
        let stub = OverrideAPIStub(shouldSucceed: false)
        let vm = PriceOverrideEditorViewModel(api: stub, serviceId: "svc-1")
        vm.rawPrice = "10.00"
        await vm.save()
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedOverride)
    }

    // MARK: - Reset

    func test_reset_clearsAllFields() async {
        let stub = OverrideAPIStub(shouldSucceed: true)
        let vm = PriceOverrideEditorViewModel(api: stub, serviceId: "svc-1")
        vm.rawPrice = "10.00"
        vm.reason = "test"
        await vm.save()
        vm.reset()
        XCTAssertEqual(vm.rawPrice, "")
        XCTAssertEqual(vm.reason, "")
        XCTAssertNil(vm.saveError)
        XCTAssertNil(vm.savedOverride)
    }

    // MARK: - Inline validation message

    func test_priceValidationMessage_nilWhenEmpty() {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        XCTAssertNil(vm.priceValidationMessage)
    }

    func test_priceValidationMessage_notNilForInvalidInput() {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        vm.rawPrice = "xyz"
        XCTAssertNotNil(vm.priceValidationMessage)
    }

    func test_priceValidationMessage_nilForValidPrice() {
        let vm = PriceOverrideEditorViewModel(api: OverrideAPIStub(), serviceId: "svc-1")
        vm.rawPrice = "29.99"
        XCTAssertNil(vm.priceValidationMessage)
    }
}

// MARK: - OverrideAPIStub

@MainActor
final class OverrideAPIStub: APIClient {
    var shouldSucceed: Bool
    var capturedServiceId: String?
    var capturedCustomerId: String?

    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        guard shouldSucceed else { throw TestError.forced }
        if path.contains("/repair-pricing/overrides"), let req = body as? CreatePriceOverrideRequest {
            capturedServiceId = req.serviceId
            capturedCustomerId = req.customerId
            let json = """
            {"id":"override-1","service_id":"\(req.serviceId)","scope":"\(req.scope.rawValue)",
             "price_cents":\(req.priceCents),"created_at":"2026-01-01T00:00:00Z"}
            """.data(using: .utf8)!
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try dec.decode(type, from: json)
        }
        throw TestError.notImplemented
    }

    // Required stubs
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func delete(_ path: String) async throws { throw TestError.notImplemented }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw TestError.notImplemented }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// TestError is defined in TestHelpers.swift
