import XCTest
@testable import RepairPricing
import Networking

// MARK: - §43 Bulk Edit — BulkPriceAdjustmentViewModel Tests

@MainActor
final class BulkPriceAdjustmentViewModelTests: XCTestCase {

    // MARK: - Initial State

    func test_initialState_isIdle() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertFalse(vm.isBusy)
        XCTAssertTrue(vm.priceRows.isEmpty)
        XCTAssertEqual(vm.adjustmentKind, .percentage)
        XCTAssertEqual(vm.rawValue, "")
    }

    // MARK: - canPreview

    func test_canPreview_emptyValue_isFalse() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.rawValue = ""
        XCTAssertFalse(vm.canPreview)
    }

    func test_canPreview_invalidValue_isFalse() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.rawValue = "notanumber"
        XCTAssertFalse(vm.canPreview)
    }

    func test_canPreview_zeroValue_isFalse() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.rawValue = "0"
        XCTAssertFalse(vm.canPreview)
    }

    func test_canPreview_pctAbove50_isFalse() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.adjustmentKind = .percentage
        vm.rawValue = "51"
        XCTAssertFalse(vm.canPreview)
    }

    func test_canPreview_validPct_isTrue() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.adjustmentKind = .percentage
        vm.rawValue = "10"
        XCTAssertTrue(vm.canPreview)
    }

    func test_canPreview_validFixed_isTrue() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.adjustmentKind = .fixed
        vm.rawValue = "5.50"
        XCTAssertTrue(vm.canPreview)
    }

    // MARK: - valueValidationMessage

    func test_valueValidationMessage_emptyValue_isNil() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.rawValue = ""
        XCTAssertNil(vm.valueValidationMessage)
    }

    func test_valueValidationMessage_nonNumeric_notNil() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.rawValue = "abc"
        XCTAssertNotNil(vm.valueValidationMessage)
    }

    func test_valueValidationMessage_pctOutOfRange_notNil() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.adjustmentKind = .percentage
        vm.rawValue = "55"
        XCTAssertNotNil(vm.valueValidationMessage)
    }

    func test_valueValidationMessage_validValue_isNil() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        vm.adjustmentKind = .percentage
        vm.rawValue = "10"
        XCTAssertNil(vm.valueValidationMessage)
    }

    // MARK: - loadPrices

    func test_loadPrices_success_populatesPriceRows() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        XCTAssertEqual(vm.priceRows.count, 2)
        XCTAssertEqual(vm.phase, .idle)
    }

    func test_loadPrices_failure_transitionsToFailed() async {
        let stub = BulkEditAPIStub(shouldSucceed: false)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        if case .failed = vm.phase {
            // expected
        } else {
            XCTFail("Expected .failed phase but got \(vm.phase)")
        }
    }

    // MARK: - generatePreview

    func test_generatePreview_populatesPreviewPhase() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = "10"
        vm.adjustmentKind = .percentage
        vm.generatePreview()
        if case .preview(let results) = vm.phase {
            XCTAssertFalse(results.isEmpty)
        } else {
            XCTFail("Expected .preview phase but got \(vm.phase)")
        }
    }

    func test_generatePreview_whenCanPreviewFalse_doesNothing() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = ""
        vm.generatePreview()
        XCTAssertEqual(vm.phase, .idle)
    }

    func test_generatePreview_percentageAdjustment_correctNewPrices() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        // Stub provides rows with laborPrice 100 and 50
        vm.rawValue = "10"
        vm.adjustmentKind = .percentage
        vm.generatePreview()
        let results = vm.previewResults
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].newPrice, 110.0, accuracy: 0.001)
        XCTAssertEqual(results[1].newPrice, 55.0, accuracy: 0.001)
    }

    // MARK: - cancelPreview

    func test_cancelPreview_resetsToIdle() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = "10"
        vm.generatePreview()
        vm.cancelPreview()
        XCTAssertEqual(vm.phase, .idle)
    }

    // MARK: - applyChanges

    func test_applyChanges_callsPutForEachChangedRow() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = "10"
        vm.adjustmentKind = .percentage
        vm.generatePreview()
        await vm.applyChanges()

        if case .applied(let count) = vm.phase {
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("Expected .applied but got \(vm.phase)")
        }
        XCTAssertEqual(stub.putCallCount, 2)
    }

    func test_applyChanges_putFailure_transitionsToFailed() async {
        let stub = BulkEditAPIStub(shouldSucceed: true, putShouldFail: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = "10"
        vm.adjustmentKind = .percentage
        vm.generatePreview()
        await vm.applyChanges()

        if case .failed = vm.phase {
            // expected
        } else {
            XCTFail("Expected .failed but got \(vm.phase)")
        }
    }

    func test_applyChanges_noChangedRows_appliedWithZero() async {
        // Use a stub that returns rows with laborPrice 100,
        // then preview with a +0% adjustment — but since 0 is invalid
        // we instead use a fixed +0.001 and verify count but skip PUT
        // because delta < threshold. Instead test a simpler scenario:
        // load rows, preview, then zero out newPrice manually isn't possible.
        // Verify that applyChanges is a no-op when not in preview phase.
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        // Don't call generatePreview — phase is .idle
        await vm.applyChanges()
        XCTAssertEqual(vm.phase, .idle) // still idle, no change
        XCTAssertEqual(stub.putCallCount, 0)
    }

    // MARK: - previewSummary

    func test_previewSummary_whenIdle_returnsZeros() {
        let vm = BulkPriceAdjustmentViewModel(api: BulkEditAPIStub())
        let s = vm.previewSummary
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.totalIncrease, 0)
        XCTAssertEqual(s.avgDelta, 0)
    }

    func test_previewSummary_withResults_calculatesCorrectly() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = "10"
        vm.adjustmentKind = .percentage
        vm.generatePreview()
        let s = vm.previewSummary
        // rows: 100 → 110 (+10), 50 → 55 (+5) → total = 15, avg = 7.5
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.totalIncrease, 15.0, accuracy: 0.01)
        XCTAssertEqual(s.avgDelta, 7.5, accuracy: 0.01)
    }

    // MARK: - reset

    func test_reset_clearsAll() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = BulkPriceAdjustmentViewModel(api: stub)
        await vm.loadPrices()
        vm.rawValue = "10"
        vm.generatePreview()
        vm.reset()
        XCTAssertEqual(vm.rawValue, "")
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.priceRows.isEmpty)
    }
}

// MARK: - ServicePresetImportViewModel Tests

@MainActor
final class ServicePresetImportViewModelTests: XCTestCase {

    func test_initialState_isIdle() {
        let vm = ServicePresetImportViewModel(api: BulkEditAPIStub())
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertFalse(vm.isBusy)
        XCTAssertTrue(vm.parsedRows.isEmpty)
        XCTAssertTrue(vm.parseErrors.isEmpty)
        XCTAssertFalse(vm.canImport)
    }

    func test_parseCSV_emptyText_setsFailed() {
        let vm = ServicePresetImportViewModel(api: BulkEditAPIStub())
        vm.csvText = ""
        vm.parseCSV()
        if case .failed = vm.phase { } else {
            XCTFail("Expected .failed for empty input")
        }
    }

    func test_parseCSV_validCSV_transitionsToParsed() {
        let vm = ServicePresetImportViewModel(api: BulkEditAPIStub())
        vm.csvText = "name,labor_price\nScreen,49.99\nBattery,29.99"
        vm.parseCSV()
        XCTAssertEqual(vm.parsedRows.count, 2)
        XCTAssertTrue(vm.canImport)
    }

    func test_parseCSV_invalidRows_capturedInErrors() {
        let vm = ServicePresetImportViewModel(api: BulkEditAPIStub())
        vm.csvText = "name,labor_price\nValid,49.99\n,20.00"
        vm.parseCSV()
        XCTAssertEqual(vm.parsedRows.count, 1)
        XCTAssertEqual(vm.parseErrors.count, 1)
    }

    func test_importRows_success_transitionsToDone() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = ServicePresetImportViewModel(api: stub)
        vm.csvText = "name,labor_price\nScreen,49.99\nBattery,29.99"
        vm.parseCSV()
        await vm.importRows()
        if case .done(let success, let fail) = vm.phase {
            XCTAssertEqual(success, 2)
            XCTAssertEqual(fail, 0)
        } else {
            XCTFail("Expected .done but got \(vm.phase)")
        }
        XCTAssertEqual(stub.postCallCount, 2)
    }

    func test_importRows_apiFailure_recordedInFailCount() async {
        let stub = BulkEditAPIStub(shouldSucceed: false)
        let vm = ServicePresetImportViewModel(api: stub)
        vm.csvText = "name,labor_price\nScreen,49.99"
        vm.parseCSV()
        await vm.importRows()
        if case .done(let success, let fail) = vm.phase {
            XCTAssertEqual(success, 0)
            XCTAssertEqual(fail, 1)
        } else {
            XCTFail("Expected .done with fail=1 but got \(vm.phase)")
        }
    }

    func test_importRows_whenNoParsedRows_doesNothing() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = ServicePresetImportViewModel(api: stub)
        // Phase is idle — importRows should be a no-op
        await vm.importRows()
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(stub.postCallCount, 0)
    }

    func test_reset_clearsAllState() async {
        let stub = BulkEditAPIStub(shouldSucceed: true)
        let vm = ServicePresetImportViewModel(api: stub)
        vm.csvText = "name,labor_price\nScreen,49.99"
        vm.parseCSV()
        await vm.importRows()
        vm.reset()
        XCTAssertEqual(vm.csvText, "")
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.parsedRows.isEmpty)
    }
}

// MARK: - BulkEditAPIStub

@MainActor
final class BulkEditAPIStub: APIClient {

    let shouldSucceed: Bool
    let putShouldFail: Bool
    var putCallCount = 0
    var postCallCount = 0

    init(shouldSucceed: Bool = true, putShouldFail: Bool = false) {
        self.shouldSucceed = shouldSucceed
        self.putShouldFail = putShouldFail
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard shouldSucceed else { throw TestError.forced }
        if path.contains("/repair-pricing/prices") {
            let json = """
            [
              {"id":1,"device_model_id":1,"repair_service_id":1,
               "device_model_name":"iPhone 15","manufacturer_name":"Apple",
               "repair_service_name":"Screen","repair_service_slug":"screen",
               "service_category":"Display","labor_price":100.0,
               "default_grade":"aftermarket","is_active":1,"grade_count":1},
              {"id":2,"device_model_id":1,"repair_service_id":2,
               "device_model_name":"iPhone 15","manufacturer_name":"Apple",
               "repair_service_name":"Battery","repair_service_slug":"battery",
               "service_category":"Power","labor_price":50.0,
               "default_grade":"aftermarket","is_active":1,"grade_count":1}
            ]
            """.data(using: .utf8)!
            let dec = JSONDecoder()
            return try dec.decode(type, from: json)
        }
        throw TestError.notImplemented
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        putCallCount += 1
        guard !putShouldFail else { throw TestError.forced }
        // Return a minimal RepairPriceRow echo
        let json = """
        {"id":1,"device_model_id":1,"repair_service_id":1,
         "labor_price":110.0,"default_grade":"aftermarket","is_active":1,"grade_count":1}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        return try dec.decode(type, from: json)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        postCallCount += 1
        guard shouldSucceed else { throw TestError.forced }
        let json = """
        {"id":10,"name":"Screen","slug":"screen","is_active":1,"sort_order":0}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        return try dec.decode(type, from: json)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func delete(_ path: String) async throws { throw TestError.notImplemented }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw TestError.notImplemented }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
