import XCTest
@testable import RepairPricing
import Networking

// MARK: - §22 iPad Polish Test Suite

// ────────────────────────────────────────────────────────────────────────────
// MARK: DeviceFamily tests
// ────────────────────────────────────────────────────────────────────────────

final class DeviceFamilyTests: XCTestCase {

    // MARK: - from(string:)

    func test_from_nil_returnsOther() {
        XCTAssertEqual(DeviceFamily.from(string: nil), .other)
    }

    func test_from_empty_returnsOther() {
        XCTAssertEqual(DeviceFamily.from(string: ""), .other)
    }

    func test_from_iphone_exact() {
        XCTAssertEqual(DeviceFamily.from(string: "iPhone"), .iphone)
    }

    func test_from_iphone_caseInsensitive() {
        XCTAssertEqual(DeviceFamily.from(string: "IPHONE"), .iphone)
    }

    func test_from_apple_mapsToIphone() {
        // Legacy server value "Apple" → iPhone bucket (primary Apple device)
        XCTAssertEqual(DeviceFamily.from(string: "Apple"), .iphone)
    }

    func test_from_ipad_exact() {
        XCTAssertEqual(DeviceFamily.from(string: "iPad"), .ipad)
    }

    func test_from_ipad_withModel() {
        XCTAssertEqual(DeviceFamily.from(string: "iPad Pro"), .ipad)
    }

    func test_from_mac() {
        XCTAssertEqual(DeviceFamily.from(string: "Mac"), .mac)
    }

    func test_from_macbook() {
        XCTAssertEqual(DeviceFamily.from(string: "MacBook"), .mac)
    }

    func test_from_android_generic() {
        XCTAssertEqual(DeviceFamily.from(string: "Android"), .android)
    }

    func test_from_samsung() {
        XCTAssertEqual(DeviceFamily.from(string: "Samsung"), .android)
    }

    func test_from_google() {
        XCTAssertEqual(DeviceFamily.from(string: "Google"), .android)
    }

    func test_from_pixel() {
        XCTAssertEqual(DeviceFamily.from(string: "Pixel"), .android)
    }

    func test_from_unknownBrand_returnsOther() {
        XCTAssertEqual(DeviceFamily.from(string: "Nokia"), .other)
    }

    func test_from_motorola_returnsOther() {
        // Not in the current mapping — should be "other" until explicitly added
        XCTAssertEqual(DeviceFamily.from(string: "Motorola"), .other)
    }

    // MARK: - Identifiable

    func test_id_equalsRawValue() {
        for family in DeviceFamily.allCases {
            XCTAssertEqual(family.id, family.rawValue)
        }
    }

    // MARK: - systemImageName

    func test_systemImageName_nonEmpty() {
        for family in DeviceFamily.allCases {
            XCTAssertFalse(family.systemImageName.isEmpty, "\(family) has empty systemImageName")
        }
    }

    // MARK: - displayName

    func test_displayName_equalsRawValue() {
        for family in DeviceFamily.allCases {
            XCTAssertEqual(family.displayName, family.rawValue)
        }
    }

    // MARK: - CaseIterable

    func test_allCases_count() {
        XCTAssertEqual(DeviceFamily.allCases.count, 5)
    }

    func test_allCases_containsAll() {
        let cases = DeviceFamily.allCases
        XCTAssertTrue(cases.contains(.iphone))
        XCTAssertTrue(cases.contains(.ipad))
        XCTAssertTrue(cases.contains(.mac))
        XCTAssertTrue(cases.contains(.android))
        XCTAssertTrue(cases.contains(.other))
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: ServicePriceRow tests
// ────────────────────────────────────────────────────────────────────────────

final class ServicePriceRowTests: XCTestCase {

    func test_init_fromRepairService_mapsFields() {
        let svc = RepairService(
            id: 42,
            family: "Apple",
            model: "iPhone 15",
            serviceName: "Screen Replacement",
            defaultPriceCents: 19900,
            partSku: "SCR-IP15-OEM",
            estimatedMinutes: 45
        )
        let row = ServicePriceRow(svc)
        XCTAssertEqual(row.id, 42)
        XCTAssertEqual(row.serviceName, "Screen Replacement")
        XCTAssertEqual(row.laborCents, 19900)
        XCTAssertEqual(row.partsCents, 0)    // no parts price from API yet
        XCTAssertEqual(row.partSku, "SCR-IP15-OEM")
        XCTAssertEqual(row.estimatedMinutes, 45)
    }

    func test_totalCents_laborPlusParts() {
        let row = ServicePriceRow(id: 1, serviceName: "Battery", laborCents: 5900, partsCents: 2000)
        XCTAssertEqual(row.totalCents, 7900)
    }

    func test_totalCents_zeroParts() {
        let row = ServicePriceRow(id: 2, serviceName: "Screen", laborCents: 15000, partsCents: 0)
        XCTAssertEqual(row.totalCents, 15000)
    }

    func test_totalCents_zeroBoth() {
        let row = ServicePriceRow(id: 3, serviceName: "Diagnostic", laborCents: 0, partsCents: 0)
        XCTAssertEqual(row.totalCents, 0)
    }

    func test_memberwise_init() {
        let row = ServicePriceRow(
            id: 99,
            serviceName: "Custom",
            laborCents: 3000,
            partsCents: 500,
            partSku: "TEST-SKU",
            estimatedMinutes: 20
        )
        XCTAssertEqual(row.id, 99)
        XCTAssertEqual(row.serviceName, "Custom")
        XCTAssertEqual(row.laborCents, 3000)
        XCTAssertEqual(row.partsCents, 500)
        XCTAssertEqual(row.totalCents, 3500)
        XCTAssertEqual(row.partSku, "TEST-SKU")
        XCTAssertEqual(row.estimatedMinutes, 20)
    }

    func test_nilPartSku_acceptedGracefully() {
        let row = ServicePriceRow(id: 1, serviceName: "Port", laborCents: 4900)
        XCTAssertNil(row.partSku)
    }

    func test_nilEstimatedMinutes_acceptedGracefully() {
        let row = ServicePriceRow(id: 1, serviceName: "Port", laborCents: 4900)
        XCTAssertNil(row.estimatedMinutes)
    }

    func test_identifiable_idStable() {
        let svc = RepairService(id: 77, serviceName: "Camera Fix", defaultPriceCents: 8000)
        let row = ServicePriceRow(svc)
        XCTAssertEqual(row.id, 77)
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: RepairPricingThreeColumnViewModel tests
// ────────────────────────────────────────────────────────────────────────────

@MainActor
final class RepairPricingThreeColumnViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        templates: [DeviceTemplate] = [],
        shouldFail: Bool = false
    ) -> (RepairPricingThreeColumnViewModel, ThreeColumnStub) {
        let stub = ThreeColumnStub(templates: templates, shouldFail: shouldFail)
        let vm = RepairPricingThreeColumnViewModel(api: stub)
        return (vm, stub)
    }

    private func makeTemplates() -> [DeviceTemplate] {
        [
            DeviceTemplate(id: 1,  name: "iPhone 15 Screen",   family: "iPhone",  model: "iPhone 15"),
            DeviceTemplate(id: 2,  name: "iPad Air Battery",   family: "iPad",    model: "iPad Air"),
            DeviceTemplate(id: 3,  name: "MacBook Pro Port",   family: "Mac",     model: "MacBook Pro"),
            DeviceTemplate(id: 4,  name: "Galaxy S24 Screen",  family: "Samsung", model: "Galaxy S24"),
            DeviceTemplate(id: 5,  name: "Unknown Device",     family: nil,       model: nil),
        ]
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.state, .loading)
        XCTAssertTrue(vm.templates.isEmpty)
        XCTAssertNil(vm.selectedFamily)
        XCTAssertNil(vm.selectedTemplate)
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertFalse(vm.showDeleteConfirm)
        XCTAssertNil(vm.templatePendingDelete)
    }

    // MARK: - load()

    func test_load_success_populatesTemplates() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.templates.count, 5)
    }

    func test_load_failure_producesFailedState() async {
        let (vm, _) = makeVM(shouldFail: true)
        await vm.load()
        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_load_retry_afterFailure_succeeds() async {
        let (vm, stub) = makeVM(shouldFail: true)
        await vm.load()
        XCTAssertNotEqual(vm.state, .loaded)

        stub.shouldFail = false
        stub.stubbedTemplates = makeTemplates()
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
    }

    // MARK: - templateCountsByFamily

    func test_templateCountsByFamily_countsCorrectly() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let counts = vm.templateCountsByFamily
        XCTAssertEqual(counts[.iphone], 1)
        XCTAssertEqual(counts[.ipad], 1)
        XCTAssertEqual(counts[.mac], 1)
        XCTAssertEqual(counts[.android], 1)   // Samsung → .android
        XCTAssertEqual(counts[.other], 1)      // nil family → .other
    }

    func test_templateCountsByFamily_emptyTemplates() {
        let (vm, _) = makeVM(templates: [])
        XCTAssertTrue(vm.templateCountsByFamily.isEmpty)
    }

    // MARK: - filteredTemplates

    func test_filteredTemplates_nilFamily_returnsAll() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = nil
        XCTAssertEqual(vm.filteredTemplates.count, 5)
    }

    func test_filteredTemplates_iphoneFamily() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = .iphone
        XCTAssertEqual(vm.filteredTemplates.count, 1)
        XCTAssertEqual(vm.filteredTemplates.first?.id, 1)
    }

    func test_filteredTemplates_ipadFamily() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = .ipad
        XCTAssertEqual(vm.filteredTemplates.count, 1)
        XCTAssertEqual(vm.filteredTemplates.first?.id, 2)
    }

    func test_filteredTemplates_searchByName() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = nil
        vm.searchQuery = "Screen"
        XCTAssertEqual(vm.filteredTemplates.count, 2) // iPhone 15 Screen + Galaxy S24 Screen
    }

    func test_filteredTemplates_searchAndFamilyCombined() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = .iphone
        vm.searchQuery = "iPhone"
        XCTAssertEqual(vm.filteredTemplates.count, 1)
    }

    func test_filteredTemplates_noMatch_returnsEmpty() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.searchQuery = "ZZZNoMatch"
        XCTAssertTrue(vm.filteredTemplates.isEmpty)
    }

    func test_filteredTemplates_whitespaceSearch_returnsAll() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.searchQuery = "   "
        XCTAssertEqual(vm.filteredTemplates.count, 5)
    }

    // MARK: - selectedFamily clears selection

    func test_selectedFamilyChange_clearsSelectedTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = .iphone
        vm.selectedTemplate = vm.filteredTemplates.first
        XCTAssertNotNil(vm.selectedTemplate)

        vm.selectedFamily = .ipad
        XCTAssertNil(vm.selectedTemplate)
    }

    func test_selectedFamilySet_toSameValue_doesNotClearSelection() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        vm.selectedFamily = .iphone
        vm.selectedTemplate = vm.filteredTemplates.first
        // Setting to same value should NOT clear (didSet guard)
        vm.selectedFamily = .iphone
        XCTAssertNotNil(vm.selectedTemplate)
    }

    // MARK: - delete

    func test_requestDelete_setsConfirmState() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let t = vm.templates.first!
        vm.requestDelete(t)
        XCTAssertTrue(vm.showDeleteConfirm)
        XCTAssertEqual(vm.templatePendingDelete?.id, t.id)
    }

    func test_confirmDelete_removesTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let t = vm.templates.first(where: { $0.id == 1 })!
        await vm.confirmDelete(t)
        XCTAssertFalse(vm.templates.contains(where: { $0.id == 1 }))
    }

    func test_confirmDelete_clearsSelection_whenDeletedIsSelected() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let t = vm.templates.first!
        vm.selectedTemplate = t
        await vm.confirmDelete(t)
        XCTAssertNil(vm.selectedTemplate)
    }

    func test_confirmDelete_keepsSelection_whenDifferentTemplate() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let selected = vm.templates.first(where: { $0.id == 1 })!
        let toDelete  = vm.templates.first(where: { $0.id == 2 })!
        vm.selectedTemplate = selected
        await vm.confirmDelete(toDelete)
        XCTAssertEqual(vm.selectedTemplate?.id, 1)
    }

    func test_confirmDelete_resetsConfirmState() async {
        let (vm, _) = makeVM(templates: makeTemplates())
        await vm.load()
        let t = vm.templates.first!
        vm.requestDelete(t)
        await vm.confirmDelete(t)
        XCTAssertFalse(vm.showDeleteConfirm)
        XCTAssertNil(vm.templatePendingDelete)
    }

    // MARK: - duplicate

    func test_duplicate_addsNewTemplate() async {
        let (vm, stub) = makeVM(templates: makeTemplates())
        await vm.load()
        let original = vm.templates.first(where: { $0.id == 1 })!
        stub.createResult = DeviceTemplate(id: 100, name: "iPhone 15 Screen (Copy)", family: "iPhone", model: "iPhone 15")
        await vm.duplicate(original)
        XCTAssertTrue(vm.templates.contains(where: { $0.id == 100 }))
        XCTAssertEqual(vm.templates.count, 6)
    }

    func test_duplicate_failure_doesNotCrash() async {
        let (vm, stub) = makeVM(templates: makeTemplates())
        await vm.load()
        stub.shouldFailCreate = true
        let original = vm.templates.first!
        await vm.duplicate(original)
        // Template count unchanged — no crash
        XCTAssertEqual(vm.templates.count, 5)
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: ThreeColumnStub
// ────────────────────────────────────────────────────────────────────────────

/// APIClient stub for three-column VM tests.
@MainActor
final class ThreeColumnStub: APIClient {
    var stubbedTemplates: [DeviceTemplate]
    var shouldFail: Bool
    var shouldFailCreate: Bool = false
    var createResult: DeviceTemplate?

    private let decoder = JSONDecoder()

    init(templates: [DeviceTemplate] = [], shouldFail: Bool = false) {
        self.stubbedTemplates = templates
        self.shouldFail = shouldFail
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldFail { throw ThreeColStubError.forced }
        if path.hasPrefix("/api/v1/device-templates") {
            let data = Self.encodeTemplates(stubbedTemplates)
            return try decoder.decode(type, from: data)
        }
        throw ThreeColStubError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldFailCreate { throw ThreeColStubError.forced }
        if let template = createResult {
            // encodeTemplates encodes an array; we decode the first element.
            let arrayData = Self.encodeTemplates([template])
            if let decoded = try? decoder.decode([T].self, from: arrayData), let first = decoded.first {
                return first
            }
        }
        throw ThreeColStubError.notImplemented
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw ThreeColStubError.notImplemented
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw ThreeColStubError.notImplemented
    }
    func delete(_ path: String) async throws { }   // no-op; success
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw ThreeColStubError.notImplemented
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    private static func encodeTemplates(_ templates: [DeviceTemplate]) -> Data {
        let objs = templates.map { t -> [String: Any] in
            var obj: [String: Any] = [
                "id": t.id,
                "name": t.name,
                "warranty_days": t.warrantyDays,
                "diagnostic_checklist": t.conditions
            ]
            if let v = t.family           { obj["device_category"] = v }
            if let v = t.model            { obj["device_model"]    = v }
            if let v = t.color            { obj["color"]           = v }
            if let v = t.estimatedMinutes { obj["est_labor_minutes"] = v }
            if let v = t.defaultPriceCents { obj["suggested_price"] = v }
            return obj
        }
        return (try? JSONSerialization.data(withJSONObject: objs)) ?? Data()
    }

    enum ThreeColStubError: Error, LocalizedError {
        case forced, notImplemented
        var errorDescription: String? {
            switch self {
            case .forced:         return "Stub forced error"
            case .notImplemented: return "Not implemented"
            }
        }
    }
}
