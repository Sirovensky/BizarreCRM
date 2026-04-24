import XCTest
@testable import RepairPricing
import Networking

/// §43 — Unit tests for `DeviceTemplateListViewModel`.
///
/// Coverage targets:
///   • Initial state
///   • load() success / failure / retry
///   • familyFilter derived list
///   • availableFamilies deduplication
///   • onSaved() insert + update
///   • delete() removes item + clears selection
@MainActor
final class DeviceTemplateListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        templates: [DeviceTemplate] = [],
        shouldFail: Bool = false
    ) -> (DeviceTemplateListViewModel, TemplateListStub) {
        let stub = TemplateListStub(templates: templates, shouldFail: shouldFail)
        let vm = DeviceTemplateListViewModel(api: stub)
        return (vm, stub)
    }

    private func makeTemplates() -> [DeviceTemplate] {
        [
            DeviceTemplate(id: 1, name: "iPhone 15 Screen", family: "Apple",   model: "iPhone 15"),
            DeviceTemplate(id: 2, name: "Galaxy S24 Battery", family: "Samsung", model: "Galaxy S24"),
            DeviceTemplate(id: 3, name: "Pixel 8 Port",      family: "Google",  model: "Pixel 8"),
            DeviceTemplate(id: 4, name: "iPad Air Screen",   family: "Apple",   model: "iPad Air"),
        ]
    }

    // MARK: - Initial state

    func test_initialState() {
        let (vm, _) = makeVM()
        XCTAssertTrue(vm.templates.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.familyFilter)
        XCTAssertNil(vm.selectedTemplate)
        XCTAssertFalse(vm.showingEditor)
    }

    // MARK: - load() success

    func test_load_populatesTemplates() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        XCTAssertEqual(vm.templates.count, 4)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_emptyResponseIsValid() async {
        let (vm, _) = makeVM(templates: [])
        await vm.load()
        XCTAssertTrue(vm.templates.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - load() failure

    func test_load_failureSetsErrorMessage() async {
        let (vm, _) = makeVM(shouldFail: true)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.templates.isEmpty)
    }

    func test_load_retryAfterFailure_succeeds() async {
        let (vm, stub) = makeVM(shouldFail: true)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)

        stub.shouldFail = false
        stub.stubbedTemplates = makeTemplates()
        await vm.load()
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.templates.count, 4)
    }

    func test_load_clearsErrorMessageOnRetry() async {
        let (vm, stub) = makeVM(shouldFail: true)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)

        stub.shouldFail = false
        stub.stubbedTemplates = []
        await vm.load()
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - availableFamilies

    func test_availableFamilies_deduplicates() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let families = vm.availableFamilies
        // Apple appears twice (iPhone 15 + iPad Air) → should be once
        XCTAssertEqual(families.filter { $0 == "Apple" }.count, 1)
    }

    func test_availableFamilies_containsAllDistinctFamilies() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let families = vm.availableFamilies
        XCTAssertTrue(families.contains("Apple"))
        XCTAssertTrue(families.contains("Samsung"))
        XCTAssertTrue(families.contains("Google"))
        XCTAssertEqual(families.count, 3)
    }

    func test_availableFamilies_emptyWhenNoTemplates() async {
        let (vm, _) = makeVM(templates: [])
        await vm.load()
        XCTAssertTrue(vm.availableFamilies.isEmpty)
    }

    func test_availableFamilies_skipsNilFamily() async {
        let templates = [
            DeviceTemplate(id: 1, name: "Unknown", family: nil, model: nil),
            DeviceTemplate(id: 2, name: "iPhone",  family: "Apple", model: "15"),
        ]
        let (vm, _) = makeVM(templates: templates)
        await vm.load()
        XCTAssertEqual(vm.availableFamilies, ["Apple"])
    }

    // MARK: - familyFilter

    func test_filteredTemplates_nilFilter_returnsAll() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.familyFilter = nil
        XCTAssertEqual(vm.filteredTemplates.count, 4)
    }

    func test_filteredTemplates_appleFilter() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.familyFilter = "Apple"
        XCTAssertEqual(vm.filteredTemplates.count, 2)
        XCTAssertTrue(vm.filteredTemplates.allSatisfy { $0.family?.lowercased() == "apple" })
    }

    func test_filteredTemplates_caseInsensitiveFilter() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.familyFilter = "apple"  // lowercase
        XCTAssertEqual(vm.filteredTemplates.count, 2)
    }

    func test_filteredTemplates_unknownFamilyReturnsEmpty() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.familyFilter = "Nokia"
        XCTAssertTrue(vm.filteredTemplates.isEmpty)
    }

    // MARK: - onSaved() — insert

    func test_onSaved_insertsNewTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let newTemplate = DeviceTemplate(id: 99, name: "New Device", family: "Apple", model: "iPhone 99")
        vm.onSaved(newTemplate)
        XCTAssertEqual(vm.templates.count, 5)
        XCTAssertTrue(vm.templates.contains(where: { $0.id == 99 }))
    }

    func test_onSaved_selectsInsertedTemplate() {
        let (vm, _) = makeVM(templates: [])
        let t = DeviceTemplate(id: 1, name: "New", family: "Apple", model: "iPhone")
        vm.onSaved(t)
        XCTAssertEqual(vm.selectedTemplate?.id, 1)
    }

    // MARK: - onSaved() — update (immutable replace)

    func test_onSaved_updatesExistingTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let updated = DeviceTemplate(id: 1, name: "iPhone 15 Pro Screen", family: "Apple", model: "iPhone 15 Pro")
        vm.onSaved(updated)
        XCTAssertEqual(vm.templates.count, 4)  // count unchanged
        let found = vm.templates.first(where: { $0.id == 1 })
        XCTAssertEqual(found?.name, "iPhone 15 Pro Screen")
        XCTAssertEqual(found?.model, "iPhone 15 Pro")
    }

    func test_onSaved_updatedTemplateIsImmutable() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let original = vm.templates.first(where: { $0.id == 2 })!
        let updated = DeviceTemplate(id: 2, name: "Galaxy S25 Battery", family: "Samsung", model: "Galaxy S25")
        vm.onSaved(updated)
        // Original value must be unchanged (we test immutability of in-memory array)
        XCTAssertEqual(original.name, "Galaxy S24 Battery")
    }

    // MARK: - delete()

    func test_delete_removesTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let toDelete = vm.templates.first(where: { $0.id == 3 })!
        await vm.delete(template: toDelete)
        XCTAssertFalse(vm.templates.contains(where: { $0.id == 3 }))
        XCTAssertEqual(vm.templates.count, 3)
    }

    func test_delete_clearsSelectedIfSameTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let t = vm.templates.first(where: { $0.id == 1 })!
        vm.selectedTemplate = t
        vm.showingEditor = true
        await vm.delete(template: t)
        XCTAssertNil(vm.selectedTemplate)
        XCTAssertFalse(vm.showingEditor)
    }

    func test_delete_keepsSelectionIfDifferentTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let selected = vm.templates.first(where: { $0.id == 1 })!
        let toDelete = vm.templates.first(where: { $0.id == 2 })!
        vm.selectedTemplate = selected
        await vm.delete(template: toDelete)
        XCTAssertEqual(vm.selectedTemplate?.id, 1)
    }

    func test_delete_failure_setsErrorMessage() async {
        let (vm, stub) = makeVM(templates: makeTemplates())
        await vm.load()
        stub.shouldFailDelete = true
        let t = vm.templates.first!
        await vm.delete(template: t)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.templates.count, 4)  // unchanged on failure
    }
}

// MARK: - Stub

/// Stub `APIClient` for `DeviceTemplateListViewModelTests`.
///
/// Extends `StubAPIClient` (from RepairPricingViewModelTests) with
/// delete support and explicit `shouldFailDelete`.
@MainActor
final class TemplateListStub: APIClient {
    var stubbedTemplates: [DeviceTemplate]
    var shouldFail: Bool
    var shouldFailDelete: Bool = false

    private let decoder = JSONDecoder()

    init(templates: [DeviceTemplate] = [], shouldFail: Bool = false) {
        self.stubbedTemplates = templates
        self.shouldFail = shouldFail
    }

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldFail { throw TemplateListStubError.forced }
        if path.hasPrefix("/api/v1/device-templates") {
            let data = Self.encodeTemplates(stubbedTemplates)
            return try decoder.decode(type, from: data)
        }
        throw TemplateListStubError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw TemplateListStubError.notImplemented
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw TemplateListStubError.notImplemented
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw TemplateListStubError.notImplemented
    }
    func delete(_ path: String) async throws {
        if shouldFailDelete { throw TemplateListStubError.forced }
        // No-op on success — the VM handles the local array update
    }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw TemplateListStubError.notImplemented
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    // MARK: - JSON helpers

    private static func encodeTemplates(_ templates: [DeviceTemplate]) -> Data {
        let objs = templates.map { t -> [String: Any] in
            var obj: [String: Any] = [
                "id": t.id,
                "name": t.name,
                "warranty_days": t.warrantyDays,
                "diagnostic_checklist": t.conditions
            ]
            if let v = t.family           { obj["device_category"]  = v }
            if let v = t.model            { obj["device_model"]      = v }
            if let v = t.color            { obj["color"]             = v }
            if let v = t.thumbnailUrl     { obj["thumbnail_url"]     = v }
            if let v = t.imeiPattern      { obj["imei_pattern"]      = v }
            if let v = t.estimatedMinutes { obj["est_labor_minutes"]  = v }
            if let v = t.defaultPriceCents { obj["suggested_price"]  = v }
            return obj
        }
        return (try? JSONSerialization.data(withJSONObject: objs)) ?? Data()
    }

    enum TemplateListStubError: Error, LocalizedError {
        case forced, notImplemented
        var errorDescription: String? {
            switch self {
            case .forced:         return "Stub forced error"
            case .notImplemented: return "Not implemented"
            }
        }
    }
}
