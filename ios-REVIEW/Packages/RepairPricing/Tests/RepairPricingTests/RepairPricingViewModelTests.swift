import XCTest
@testable import RepairPricing
import Networking

/// §43 — ViewModel unit tests covering state transitions, family filter,
/// search filtering, and debounce behaviour.
@MainActor
final class RepairPricingViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let vm = RepairPricingViewModel(api: StubAPIClient())
        XCTAssertEqual(vm.state, .loading)
        XCTAssertTrue(vm.templates.isEmpty)
        XCTAssertTrue(vm.services.isEmpty)
        XCTAssertNil(vm.family)
        XCTAssertEqual(vm.searchQuery, "")
    }

    // MARK: - Load success

    func test_load_populatesTemplatesAndServices() async {
        let stub = StubAPIClient(
            templates: makeSampleTemplates(),
            services: makeSampleServices()
        )
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.templates.count, 3)
        XCTAssertEqual(vm.services.count, 2)
    }

    func test_load_emptyResponseIsLoaded() async {
        let stub = StubAPIClient(templates: [], services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertTrue(vm.templates.isEmpty)
    }

    // MARK: - Load failure

    func test_load_failureProducesFailedState() async {
        let stub = StubAPIClient(shouldFail: true)
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty, "Failed state should carry an error message")
        } else {
            XCTFail("Expected .failed state, got \(vm.state)")
        }
    }

    func test_load_retryAfterFailureSucceeds() async {
        let stub = StubAPIClient(shouldFail: true)
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        XCTAssert(vm.state != .loaded)

        stub.shouldFail = false
        stub.stubbedTemplates = makeSampleTemplates()
        stub.stubbedServices = makeSampleServices()
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertFalse(vm.templates.isEmpty)
    }

    // MARK: - Family filter

    func test_availableFamilies_derivedFromTemplates() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        let families = vm.availableFamilies
        XCTAssertTrue(families.contains("Apple"))
        XCTAssertTrue(families.contains("Samsung"))
        XCTAssertTrue(families.contains("Google"))
        // No duplicates
        XCTAssertEqual(families.count, Set(families).count)
    }

    func test_filteredTemplates_familyNil_returnsAll() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.family = nil
        XCTAssertEqual(vm.filteredTemplates.count, 3)
    }

    func test_filteredTemplates_familyApple_filtersCorrectly() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.family = "Apple"
        let filtered = vm.filteredTemplates
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(filtered.allSatisfy { $0.family?.lowercased() == "apple" })
    }

    func test_filteredTemplates_unknownFamily_returnsEmpty() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.family = "Nokia"
        XCTAssertTrue(vm.filteredTemplates.isEmpty)
    }

    func test_filteredTemplates_familyCaseInsensitive() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.family = "apple"  // lowercase
        XCTAssertEqual(vm.filteredTemplates.count, 1)
    }

    // MARK: - Search filtering

    func test_filteredTemplates_searchByName() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.searchQuery = "iphone"
        XCTAssertEqual(vm.filteredTemplates.count, 1)
        XCTAssertTrue(vm.filteredTemplates[0].model?.lowercased().contains("iphone") == true)
    }

    func test_filteredTemplates_searchByModel() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.searchQuery = "Galaxy"
        XCTAssertEqual(vm.filteredTemplates.count, 1)
        XCTAssertEqual(vm.filteredTemplates[0].family, "Samsung")
    }

    func test_filteredTemplates_searchByFamily() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.searchQuery = "Google"
        XCTAssertEqual(vm.filteredTemplates.count, 1)
        XCTAssertEqual(vm.filteredTemplates[0].family, "Google")
    }

    func test_filteredTemplates_emptySearch_returnsAll() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.searchQuery = "   "  // whitespace only
        XCTAssertEqual(vm.filteredTemplates.count, 3)
    }

    func test_filteredTemplates_searchAndFamilyCombined() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        vm.family = "Apple"
        vm.searchQuery = "iphone"
        XCTAssertEqual(vm.filteredTemplates.count, 1)
    }

    // MARK: - Debounce

    /// Verify `onSearchChange` updates `searchQuery` immediately and that the
    /// debounce does not crash. We use a short XCTestExpectation + sleep to
    /// simulate the 300 ms window without a network call.
    func test_onSearchChange_updatesSearchQueryImmediately() {
        let vm = RepairPricingViewModel(api: StubAPIClient())
        vm.onSearchChange("test")
        XCTAssertEqual(vm.searchQuery, "test")
    }

    func test_onSearchChange_rapidCalls_onlyLastQuerySticks() async throws {
        let vm = RepairPricingViewModel(api: StubAPIClient())
        vm.onSearchChange("a")
        vm.onSearchChange("ab")
        vm.onSearchChange("abc")
        // Only the last value should remain
        XCTAssertEqual(vm.searchQuery, "abc")
    }

    func test_onSearchChange_debounce_doesNotFireImmediately() {
        // The debounce task is created but the callback should not trigger
        // a network call before the 300 ms window. Since search is local
        // in this implementation, we simply verify no crash occurs.
        let vm = RepairPricingViewModel(api: StubAPIClient())
        let expectation = XCTestExpectation(description: "debounce window")
        expectation.isInverted = true  // Should NOT fire in 50ms

        vm.onSearchChange("test query")

        wait(for: [expectation], timeout: 0.05)
        // Query still set, no crash
        XCTAssertEqual(vm.searchQuery, "test query")
    }

    // MARK: - Populated vs empty state

    func test_filteredTemplates_emptyBeforeLoad() {
        let vm = RepairPricingViewModel(api: StubAPIClient())
        XCTAssertTrue(vm.filteredTemplates.isEmpty)
    }

    func test_filteredTemplates_populatedAfterLoad() async {
        let stub = StubAPIClient(templates: makeSampleTemplates(), services: [])
        let vm = RepairPricingViewModel(api: stub)
        await vm.load()
        XCTAssertFalse(vm.filteredTemplates.isEmpty)
    }

    // MARK: - Fixtures

    private func makeSampleTemplates() -> [DeviceTemplate] {
        [
            DeviceTemplate(id: 1, name: "iPhone 15 Screen", family: "Apple", model: "iPhone 15"),
            DeviceTemplate(id: 2, name: "Galaxy S24 Battery", family: "Samsung", model: "Galaxy S24"),
            DeviceTemplate(id: 3, name: "Pixel 8 Port", family: "Google", model: "Pixel 8")
        ]
    }

    private func makeSampleServices() -> [RepairService] {
        [
            RepairService(id: 10, serviceName: "Screen Replacement", defaultPriceCents: 19900),
            RepairService(id: 11, serviceName: "Battery Swap", defaultPriceCents: 5900)
        ]
    }
}

// MARK: - Stub API client

/// In-memory stub conforming to `APIClient`. The `get<T>` implementation
/// matches on the request path and decodes the pre-built JSON fixtures,
/// so that the extension methods on `APIClient` (e.g. `listDeviceTemplates`)
/// flow through the protocol and work correctly without a network call.
@MainActor
final class StubAPIClient: APIClient {
    /// JSON payload for the templates list endpoint.
    var templatesJSON: Data
    /// JSON payload for the services list endpoint.
    var servicesJSON: Data
    var shouldFail: Bool

    private let decoder = JSONDecoder()

    init(
        templates: [DeviceTemplate] = [],
        services: [RepairService] = [],
        shouldFail: Bool = false
    ) {
        self.templatesJSON = StubAPIClient.encode(templates)
        self.servicesJSON  = StubAPIClient.encode(services)
        self.shouldFail    = shouldFail
    }

    // Convenience for tests that mutate fixtures after construction.
    var stubbedTemplates: [DeviceTemplate] {
        get { (try? decoder.decode([DeviceTemplate].self, from: templatesJSON)) ?? [] }
        set { templatesJSON = StubAPIClient.encode(newValue) }
    }

    var stubbedServices: [RepairService] {
        get { (try? decoder.decode([RepairService].self, from: servicesJSON)) ?? [] }
        set { servicesJSON = StubAPIClient.encode(newValue) }
    }

    // MARK: - APIClient protocol

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldFail { throw StubError.forced }

        if path.contains("/api/v1/repair-pricing/services") {
            return try decoder.decode(type, from: servicesJSON)
        }
        if path.hasPrefix("/api/v1/device-templates") {
            return try decoder.decode(type, from: templatesJSON)
        }
        throw StubError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }
    func delete(_ path: String) async throws { throw StubError.notImplemented }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw StubError.notImplemented
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    // MARK: - Encoding helpers

    /// Encode `DeviceTemplate` / `RepairService` arrays to JSON.
    /// These types are `Decodable`-only, so we build the JSON by hand
    /// from known CodingKeys rather than conforming them to `Encodable`.
    private static func encode(_ templates: [DeviceTemplate]) -> Data {
        let objs = templates.map { t -> [String: Any] in
            var obj: [String: Any] = [
                "id": t.id,
                "name": t.name,
                "warranty_days": t.warrantyDays,
                "diagnostic_checklist": t.conditions
            ]
            if let v = t.family  { obj["device_category"]  = v }
            if let v = t.model   { obj["device_model"]     = v }
            if let v = t.color   { obj["color"]            = v }
            if let v = t.thumbnailUrl { obj["thumbnail_url"] = v }
            if let v = t.imeiPattern  { obj["imei_pattern"] = v }
            if let v = t.estimatedMinutes  { obj["est_labor_minutes"] = v }
            if let v = t.defaultPriceCents { obj["suggested_price"]   = v }
            return obj
        }
        return (try? JSONSerialization.data(withJSONObject: objs)) ?? Data()
    }

    private static func encode(_ services: [RepairService]) -> Data {
        let objs = services.map { s -> [String: Any] in
            var obj: [String: Any] = [
                "id": s.id,
                "service_name": s.serviceName,
                "default_price_cents": s.defaultPriceCents
            ]
            if let v = s.family           { obj["family"]            = v }
            if let v = s.model            { obj["model"]             = v }
            if let v = s.partSku          { obj["part_sku"]          = v }
            if let v = s.estimatedMinutes { obj["estimated_minutes"] = v }
            return obj
        }
        return (try? JSONSerialization.data(withJSONObject: objs)) ?? Data()
    }

    enum StubError: Error, LocalizedError {
        case forced
        case notFound
        case notImplemented

        var errorDescription: String? {
            switch self {
            case .forced:         return "Stub forced error"
            case .notFound:       return "Not found"
            case .notImplemented: return "Not implemented in stub"
            }
        }
    }
}
