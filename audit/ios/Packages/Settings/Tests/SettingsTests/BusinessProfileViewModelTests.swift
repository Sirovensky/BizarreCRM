import Testing
import Foundation
@testable import Settings
import Networking

// MARK: - Stub clients

private actor BusinessProfileStubClient: APIClient {
    let config: StoreConfigResponse
    var savedRequest: StoreConfigRequest?

    init(config: StoreConfigResponse) { self.config = config }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let r = config as? T { return r }
        throw URLError(.badServerResponse)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badServerResponse)
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let req = body as? StoreConfigRequest {
            savedRequest = req
        }
        if let r = config as? T { return r }
        // Return a minimal valid response
        if let r = StoreConfigResponse() as? T { return r }
        throw URLError(.badServerResponse)
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badServerResponse)
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.badServerResponse)
    }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}

private actor PreferencesStubClient: APIClient {
    let prefs: UserPreferencesResponse
    var lastPut: UserPreferencesResponse?

    init(prefs: UserPreferencesResponse) { self.prefs = prefs }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let r = prefs as? T { return r }
        throw URLError(.badServerResponse)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badServerResponse)
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let req = body as? UserPreferencesResponse {
            lastPut = req
        }
        if let r = prefs as? T { return r }
        throw URLError(.badServerResponse)
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badServerResponse)
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.badServerResponse)
    }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}

private actor FailingAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func delete(_ path: String) async throws { throw URLError(.notConnectedToInternet) }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.notConnectedToInternet)
    }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}

// MARK: - BusinessProfileViewModel Tests

@Suite("BusinessProfileViewModel")
struct BusinessProfileViewModelTests {

    @Test("Initial state is empty and not loading")
    @MainActor
    func initialState() {
        let vm = BusinessProfileViewModel()
        #expect(vm.storeName == "")
        #expect(vm.address == "")
        #expect(vm.phone == "")
        #expect(vm.email == "")
        #expect(vm.currency == "USD")
        #expect(!vm.isLoading)
        #expect(!vm.isSaving)
        #expect(vm.errorMessage == nil)
        #expect(vm.successMessage == nil)
    }

    @Test("isValid is false when storeName is empty")
    @MainActor
    func isValidFalseForEmptyName() {
        let vm = BusinessProfileViewModel()
        vm.storeName = ""
        #expect(!vm.isValid)
    }

    @Test("isValid is false when storeName is whitespace only")
    @MainActor
    func isValidFalseForWhitespaceName() {
        let vm = BusinessProfileViewModel()
        vm.storeName = "   "
        #expect(!vm.isValid)
    }

    @Test("isValid is true when storeName is non-empty")
    @MainActor
    func isValidTrueForNonEmptyName() {
        let vm = BusinessProfileViewModel()
        vm.storeName = "My Shop"
        #expect(vm.isValid)
    }

    @Test("Load populates fields from API response")
    @MainActor
    func loadPopulatesFields() async {
        let cfg = StoreConfigResponse(
            storeName: "Acme Repairs",
            address: "123 Main St",
            phone: "555-0001",
            email: "info@acme.com",
            timezone: "America/Chicago",
            currency: "CAD",
            receiptHeader: "Welcome!",
            receiptFooter: "Thank you"
        )
        let stub = BusinessProfileStubClient(config: cfg)
        let vm = BusinessProfileViewModel(api: stub)
        await vm.load()
        #expect(vm.storeName == "Acme Repairs")
        #expect(vm.address == "123 Main St")
        #expect(vm.phone == "555-0001")
        #expect(vm.email == "info@acme.com")
        #expect(vm.timezone == "America/Chicago")
        #expect(vm.currency == "CAD")
        #expect(vm.receiptHeader == "Welcome!")
        #expect(vm.receiptFooter == "Thank you")
        #expect(vm.errorMessage == nil)
    }

    @Test("Load sets errorMessage on network failure")
    @MainActor
    func loadSetsErrorOnFailure() async {
        let vm = BusinessProfileViewModel(api: FailingAPIClient())
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(!vm.isLoading)
    }

    @Test("Load clears previous error on success")
    @MainActor
    func loadClearsPreviousError() async {
        let cfg = StoreConfigResponse(storeName: "Test Store")
        let stub = BusinessProfileStubClient(config: cfg)
        let vm = BusinessProfileViewModel(api: stub)
        vm.errorMessage = "Previous error"
        await vm.load()
        #expect(vm.errorMessage == nil)
    }

    @Test("Save sets successMessage on success")
    @MainActor
    func saveSuccess() async {
        let cfg = StoreConfigResponse(storeName: "Test")
        let stub = BusinessProfileStubClient(config: cfg)
        let vm = BusinessProfileViewModel(api: stub)
        vm.storeName = "Test Store"
        await vm.save()
        #expect(vm.successMessage == "Business profile saved.")
        #expect(vm.errorMessage == nil)
        #expect(!vm.isSaving)
    }

    @Test("Save sets errorMessage when storeName is empty")
    @MainActor
    func saveRequiresStoreName() async {
        let vm = BusinessProfileViewModel(api: nil)
        vm.storeName = ""
        await vm.save()
        #expect(vm.errorMessage == "Store name is required.")
        #expect(vm.successMessage == nil)
    }

    @Test("Save sets errorMessage on network failure")
    @MainActor
    func saveSetsErrorOnFailure() async {
        let vm = BusinessProfileViewModel(api: FailingAPIClient())
        vm.storeName = "Test Store"
        await vm.save()
        #expect(vm.errorMessage != nil)
        #expect(vm.successMessage == nil)
        #expect(!vm.isSaving)
    }

    @Test("isLoading is false after load completes")
    @MainActor
    func isLoadingFalseAfterLoad() async {
        let cfg = StoreConfigResponse()
        let stub = BusinessProfileStubClient(config: cfg)
        let vm = BusinessProfileViewModel(api: stub)
        await vm.load()
        #expect(!vm.isLoading)
    }

    @Test("Nil API does not crash on load")
    @MainActor
    func nilAPIdoesNotCrash() async {
        let vm = BusinessProfileViewModel(api: nil)
        await vm.load()
        #expect(vm.storeName == "")
        #expect(!vm.isLoading)
    }
}

// MARK: - PreferencesViewModel Tests

@Suite("PreferencesViewModel")
struct PreferencesViewModelTests {

    @Test("Initial state has correct defaults")
    @MainActor
    func initialState() {
        let vm = PreferencesViewModel()
        #expect(vm.theme == "system")
        #expect(vm.defaultView == "list")
        #expect(vm.compactMode == false)
        #expect(vm.ticketPageSize == 25)
        #expect(vm.notificationSound == true)
        #expect(!vm.isLoading)
        #expect(!vm.isSaving)
        #expect(vm.errorMessage == nil)
    }

    @Test("themeOptions has system, light, dark")
    func themeOptionsComplete() {
        let values = PreferencesViewModel.themeOptions.map(\.value)
        #expect(values.contains("system"))
        #expect(values.contains("light"))
        #expect(values.contains("dark"))
        #expect(values.count == 3)
    }

    @Test("defaultViewOptions contains list and grid")
    func defaultViewOptionsComplete() {
        let values = PreferencesViewModel.defaultViewOptions.map(\.value)
        #expect(values.contains("list"))
        #expect(values.contains("grid"))
    }

    @Test("ticketSortOptions are non-empty and have unique values")
    func ticketSortOptionsValid() {
        let opts = PreferencesViewModel.ticketSortOptions
        #expect(!opts.isEmpty)
        let values = opts.map(\.value)
        let unique = Set(values)
        #expect(values.count == unique.count)
    }

    @Test("pageSizeOptions contains 25")
    func pageSizeOptionsContains25() {
        #expect(PreferencesViewModel.pageSizeOptions.contains(25))
    }

    @Test("Load populates fields from API response")
    @MainActor
    func loadPopulatesFields() async {
        let prefs = UserPreferencesResponse(
            theme: "dark",
            defaultView: "grid",
            timezone: "Europe/London",
            language: "en-GB",
            sidebarCollapsed: true,
            ticketDefaultSort: "customer_asc",
            ticketDefaultFilter: "closed",
            ticketPageSize: 50,
            notificationSound: false,
            notificationDesktop: false,
            compactMode: true
        )
        let stub = PreferencesStubClient(prefs: prefs)
        let vm = PreferencesViewModel(api: stub)
        await vm.load()
        #expect(vm.theme == "dark")
        #expect(vm.defaultView == "grid")
        #expect(vm.timezone == "Europe/London")
        #expect(vm.language == "en-GB")
        #expect(vm.sidebarCollapsed == true)
        #expect(vm.ticketDefaultSort == "customer_asc")
        #expect(vm.ticketDefaultFilter == "closed")
        #expect(vm.ticketPageSize == 50)
        #expect(vm.notificationSound == false)
        #expect(vm.notificationDesktop == false)
        #expect(vm.compactMode == true)
        #expect(vm.errorMessage == nil)
    }

    @Test("Load sets errorMessage on network failure")
    @MainActor
    func loadSetsErrorOnFailure() async {
        let vm = PreferencesViewModel(api: FailingAPIClient())
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(!vm.isLoading)
    }

    @Test("Load applies defaults for nil fields from API")
    @MainActor
    func loadAppliesDefaultsForNilFields() async {
        // API returns all nil fields → ViewModel uses its defaults
        let prefs = UserPreferencesResponse()
        let stub = PreferencesStubClient(prefs: prefs)
        let vm = PreferencesViewModel(api: stub)
        await vm.load()
        #expect(vm.theme == "system")
        #expect(vm.defaultView == "list")
        #expect(vm.compactMode == false)
        #expect(vm.ticketPageSize == 25)
        #expect(vm.notificationSound == true)
        #expect(vm.notificationDesktop == true)
    }

    @Test("Save sets successMessage on success")
    @MainActor
    func saveSuccess() async {
        let prefs = UserPreferencesResponse(theme: "light")
        let stub = PreferencesStubClient(prefs: prefs)
        let vm = PreferencesViewModel(api: stub)
        await vm.save()
        #expect(vm.successMessage == "Preferences saved.")
        #expect(vm.errorMessage == nil)
        #expect(!vm.isSaving)
    }

    @Test("Save sets errorMessage on network failure")
    @MainActor
    func saveSetsErrorOnFailure() async {
        let vm = PreferencesViewModel(api: FailingAPIClient())
        await vm.save()
        #expect(vm.errorMessage != nil)
        #expect(vm.successMessage == nil)
        #expect(!vm.isSaving)
    }

    @Test("Nil API does not crash on load")
    @MainActor
    func nilAPIdoesNotCrash() async {
        let vm = PreferencesViewModel(api: nil)
        await vm.load()
        #expect(vm.theme == "system")
        #expect(!vm.isLoading)
    }

    @Test("Save clears previous error")
    @MainActor
    func saveClearsPreviousError() async {
        let prefs = UserPreferencesResponse(theme: "dark")
        let stub = PreferencesStubClient(prefs: prefs)
        let vm = PreferencesViewModel(api: stub)
        vm.errorMessage = "Old error"
        await vm.save()
        #expect(vm.errorMessage == nil)
    }

    @Test("Empty timezone string becomes nil in request")
    @MainActor
    func emptyTimezoneBecomesNil() async {
        let prefs = UserPreferencesResponse(theme: "light")
        let stub = PreferencesStubClient(prefs: prefs)
        let vm = PreferencesViewModel(api: stub)
        vm.timezone = ""
        await vm.save()
        let sent = await stub.lastPut
        #expect(sent?.timezone == nil)
    }

    @Test("Non-empty timezone string is passed in request")
    @MainActor
    func nonEmptyTimezoneIsSent() async {
        let prefs = UserPreferencesResponse(theme: "light")
        let stub = PreferencesStubClient(prefs: prefs)
        let vm = PreferencesViewModel(api: stub)
        vm.timezone = "America/Toronto"
        await vm.save()
        let sent = await stub.lastPut
        #expect(sent?.timezone == "America/Toronto")
    }
}

// MARK: - Search index coverage for new pages

@Suite("SettingsSearchIndex new entries")
struct SettingsSearchIndexNewEntriesTests {

    @Test("Search index contains 'preferences' entry")
    func preferencesEntryExists() {
        #expect(SettingsSearchIndex.entries.contains { $0.id == "preferences" })
    }

    @Test("Search index contains 'businessProfile' entry")
    func businessProfileEntryExists() {
        #expect(SettingsSearchIndex.entries.contains { $0.id == "businessProfile" })
    }

    @Test("Query 'store name' finds businessProfile")
    func storeName() {
        let results = SettingsSearchIndex.filter(query: "store name")
        #expect(results.contains { $0.id == "businessProfile" })
    }

    @Test("Query 'receipt' finds businessProfile")
    func receiptFindsBusinessProfile() {
        let results = SettingsSearchIndex.filter(query: "receipt")
        #expect(results.contains { $0.id == "businessProfile" })
    }

    @Test("Query 'compact mode' finds preferences")
    func compactModeFindsPreferences() {
        let results = SettingsSearchIndex.filter(query: "compact mode")
        #expect(results.contains { $0.id == "preferences" })
    }

    @Test("Query 'page size' finds preferences")
    func pageSizeFindsPreferences() {
        let results = SettingsSearchIndex.filter(query: "page size")
        #expect(results.contains { $0.id == "preferences" })
    }

    @Test("Query 'notification sound' finds preferences")
    func notificationSoundFindsPreferences() {
        let results = SettingsSearchIndex.filter(query: "notification sound")
        #expect(results.contains { $0.id == "preferences" })
    }
}
