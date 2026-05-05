import XCTest
@testable import RepairPricing
import Networking

/// §43.5 — DeviceTemplateEditorViewModel unit tests.
@MainActor
final class DeviceTemplateEditorViewModelTests: XCTestCase {

    // MARK: - Initial state (create mode)

    func test_createMode_initialState() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        XCTAssertEqual(vm.name, "")
        XCTAssertEqual(vm.family, "")
        XCTAssertTrue(vm.inlineServices.isEmpty)
        XCTAssertTrue(vm.selectedConditionIds.isEmpty)
        XCTAssertFalse(vm.isEditing)
        XCTAssertFalse(vm.isSaving)
        XCTAssertNil(vm.saveError)
        XCTAssertNil(vm.savedTemplate)
    }

    func test_editMode_prefillsFromTemplate() {
        let template = DeviceTemplate(
            id: 99,
            name: "iPhone 15 Screen",
            family: "Apple",
            model: "iPhone 15",
            conditions: ["new", "used"]
        )
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub(), editingTemplate: template)
        XCTAssertEqual(vm.name, "iPhone 15 Screen")
        XCTAssertEqual(vm.family, "Apple")
        XCTAssertTrue(vm.selectedConditionIds.contains("new"))
        XCTAssertTrue(vm.selectedConditionIds.contains("used"))
        XCTAssertTrue(vm.isEditing)
    }

    // MARK: - Inline services (immutable)

    func test_addInlineService_appendsEmpty() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.addInlineService()
        XCTAssertEqual(vm.inlineServices.count, 1)
        XCTAssertEqual(vm.inlineServices[0].name, "")
    }

    func test_addInlineService_doesNotMutatePreviousSnapshot() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.addInlineService()
        let snapshot = vm.inlineServices
        vm.addInlineService()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(vm.inlineServices.count, 2)
    }

    func test_removeInlineService_removesCorrectIndex() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.addInlineService()
        vm.addInlineService()
        vm.removeInlineService(at: 0)
        XCTAssertEqual(vm.inlineServices.count, 1)
    }

    func test_removeInlineService_outOfBounds_noChange() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.addInlineService()
        vm.removeInlineService(at: 99)
        XCTAssertEqual(vm.inlineServices.count, 1)
    }

    func test_updateInlineService_updatesName() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.addInlineService()
        vm.updateInlineService(at: 0, name: "Battery")
        XCTAssertEqual(vm.inlineServices[0].name, "Battery")
    }

    func test_updateInlineService_updatesPrice() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.addInlineService()
        vm.updateInlineService(at: 0, rawPrice: "59.99")
        XCTAssertEqual(vm.inlineServices[0].rawPrice, "59.99")
        XCTAssertEqual(vm.inlineServices[0].priceCents, 5999)
    }

    // MARK: - Condition toggle

    func test_toggleCondition_addsCondition() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.toggleCondition("new")
        XCTAssertTrue(vm.selectedConditionIds.contains("new"))
    }

    func test_toggleCondition_removesExistingCondition() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.toggleCondition("used")
        vm.toggleCondition("used")
        XCTAssertFalse(vm.selectedConditionIds.contains("used"))
    }

    // MARK: - Validation on save

    func test_save_emptyName_setsValidationErrors() async {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.name = ""
        vm.family = "Apple"
        await vm.save()
        XCTAssertTrue(vm.validationErrors.contains(.nameEmpty))
        XCTAssertNil(vm.savedTemplate)
    }

    func test_save_emptyFamily_setsValidationErrors() async {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.name = "iPhone 16"
        vm.family = ""
        await vm.save()
        XCTAssertTrue(vm.validationErrors.contains(.familyEmpty))
    }

    // MARK: - Successful save (create)

    func test_save_validForm_populatesSavedTemplate() async {
        let stub = TemplateAPIStub(shouldSucceed: true)
        let vm = DeviceTemplateEditorViewModel(api: stub)
        vm.name = "iPhone 16"
        vm.family = "Apple"
        vm.addInlineService()
        vm.updateInlineService(at: 0, name: "Screen", rawPrice: "199.00")
        await vm.save()
        XCTAssertNil(vm.saveError)
        XCTAssertTrue(vm.validationErrors.isEmpty)
        XCTAssertNotNil(vm.savedTemplate)
    }

    func test_save_apiFailure_setsError() async {
        let stub = TemplateAPIStub(shouldSucceed: false)
        let vm = DeviceTemplateEditorViewModel(api: stub)
        vm.name = "iPhone 16"
        vm.family = "Apple"
        await vm.save()
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedTemplate)
    }

    // MARK: - effectiveFamily

    func test_effectiveFamily_notCustom_usesFamily() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.family = "Samsung"
        vm.isCustomFamily = false
        XCTAssertEqual(vm.effectiveFamily, "Samsung")
    }

    func test_effectiveFamily_custom_usesCustomFamily() {
        let vm = DeviceTemplateEditorViewModel(api: TemplateAPIStub())
        vm.isCustomFamily = true
        vm.customFamily = "OnePlus"
        XCTAssertEqual(vm.effectiveFamily, "OnePlus")
    }

    // MARK: - Load families

    func test_loadFamilies_populatesFromTemplates() async {
        let stub = TemplateAPIStub(shouldSucceed: true)
        let vm = DeviceTemplateEditorViewModel(api: stub)
        await vm.loadFamilies()
        XCTAssertTrue(vm.availableFamilies.contains("Apple"))
        XCTAssertTrue(vm.availableFamilies.contains("Samsung"))
    }
}

// MARK: - TemplateAPIStub

@MainActor
final class TemplateAPIStub: APIClient {
    var shouldSucceed: Bool

    private let templatesJSON = """
    [{"id":1,"name":"iPhone 15","device_category":"Apple","warranty_days":30,"diagnostic_checklist":[]},
     {"id":2,"name":"Galaxy S24","device_category":"Samsung","warranty_days":30,"diagnostic_checklist":[]}]
    """.data(using: .utf8)!

    private let newTemplateJSON = """
    {"id":999,"name":"New Template","device_category":"Apple","warranty_days":30,"diagnostic_checklist":[]}
    """.data(using: .utf8)!

    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/device-templates") {
            return try JSONDecoder().decode(type, from: templatesJSON)
        }
        throw TestError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard shouldSucceed else { throw TestError.forced }
        if path.contains("/device-templates") {
            return try JSONDecoder().decode(type, from: newTemplateJSON)
        }
        throw TestError.notImplemented
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard shouldSucceed else { throw TestError.forced }
        if path.contains("/device-templates") {
            return try JSONDecoder().decode(type, from: newTemplateJSON)
        }
        throw TestError.notImplemented
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func delete(_ path: String) async throws { guard shouldSucceed else { throw TestError.forced } }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw TestError.notImplemented }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
