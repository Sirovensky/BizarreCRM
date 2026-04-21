import Testing
import Foundation
@testable import Settings
import Core
import Networking

// MARK: - Stub API Clients

/// Stub that returns a preset profile.
private actor ProfileStubClient: APIClient {
    let profile: UserProfileResponse

    init(profile: UserProfileResponse) {
        self.profile = profile
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let r = profile as? T { return r }
        throw URLError(.badServerResponse)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let r = Networking.EmptyResponse() as? T { return r }
        throw URLError(.badServerResponse)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let r = Networking.EmptyResponse() as? T { return r }
        throw URLError(.badServerResponse)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let r = UserProfileResponse(firstName: "patched", lastName: nil, displayName: nil, email: nil, phone: nil, jobTitle: nil) as? T { return r }
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

/// Stub that always throws on network calls.
private actor FailingClient: APIClient {
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

/// Stub for CompanyInfo
private actor CompanyStubClient: APIClient {
    let info: CompanyInfoResponse
    init(info: CompanyInfoResponse) { self.info = info }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let r = info as? T { return r }
        throw URLError(.badServerResponse)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badServerResponse)
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badServerResponse)
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let r = info as? T { return r }
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

// MARK: - ProfileSettingsViewModel Tests

@Suite("ProfileSettingsViewModel")
struct ProfileSettingsViewModelTests {

    @Test("Initial state is empty and not loading")
    @MainActor
    func initialState() {
        let vm = ProfileSettingsViewModel()
        #expect(vm.firstName == "")
        #expect(vm.lastName == "")
        #expect(vm.email == "")
        #expect(!vm.isLoading)
        #expect(!vm.isSaving)
        #expect(vm.errorMessage == nil)
    }

    @Test("Load populates fields from API response")
    @MainActor
    func loadPopulatesFields() async {
        let stub = ProfileStubClient(profile: UserProfileResponse(
            firstName: "Jane", lastName: "Doe",
            displayName: "Jane D", email: "jane@example.com",
            phone: "555-1234", jobTitle: "Manager"
        ))
        let vm = ProfileSettingsViewModel(api: stub)
        await vm.load()
        #expect(vm.firstName == "Jane")
        #expect(vm.lastName == "Doe")
        #expect(vm.displayName == "Jane D")
        #expect(vm.email == "jane@example.com")
        #expect(vm.phone == "555-1234")
        #expect(vm.jobTitle == "Manager")
        #expect(vm.errorMessage == nil)
    }

    @Test("Load sets errorMessage on network failure")
    @MainActor
    func loadSetsErrorOnFailure() async {
        let vm = ProfileSettingsViewModel(api: FailingClient())
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    @Test("Password strength score is 0 for empty password")
    @MainActor
    func passwordStrengthEmpty() {
        let vm = ProfileSettingsViewModel()
        vm.newPassword = ""
        #expect(vm.passwordStrength == 0)
    }

    @Test("Password strength score is 4 for strong password")
    @MainActor
    func passwordStrengthStrong() {
        let vm = ProfileSettingsViewModel()
        vm.newPassword = "Secure#8"
        #expect(vm.passwordStrength == 4)
    }

    @Test("passwordsMatch is false when passwords differ")
    @MainActor
    func passwordsDoNotMatch() {
        let vm = ProfileSettingsViewModel()
        vm.newPassword = "abc123"
        vm.confirmPassword = "abc456"
        #expect(!vm.passwordsMatch)
    }

    @Test("passwordsMatch is true when passwords are identical and non-empty")
    @MainActor
    func passwordsMatch() {
        let vm = ProfileSettingsViewModel()
        vm.newPassword = "Abc!1234"
        vm.confirmPassword = "Abc!1234"
        #expect(vm.passwordsMatch)
    }

    @Test("changePassword sets error when passwords do not match")
    @MainActor
    func changePasswordMismatch() async {
        let vm = ProfileSettingsViewModel(api: nil)
        vm.newPassword = "foo"
        vm.confirmPassword = "bar"
        await vm.changePassword()
        #expect(vm.errorMessage == "Passwords do not match.")
    }

    @Test("Save sets successMessage on success")
    @MainActor
    func saveSuccess() async {
        let stub = ProfileStubClient(profile: UserProfileResponse(
            firstName: "J", lastName: "D", displayName: nil, email: nil, phone: nil, jobTitle: nil
        ))
        let vm = ProfileSettingsViewModel(api: stub)
        vm.firstName = "J"
        vm.lastName = "D"
        await vm.save()
        #expect(vm.successMessage == "Profile saved.")
    }
}

// MARK: - TaxSettingsViewModel Tests

@Suite("TaxSettingsViewModel")
struct TaxSettingsViewModelTests {

    @Test("Initial state has empty tax rates")
    @MainActor
    func initialState() {
        let vm = TaxSettingsViewModel()
        #expect(vm.taxRates.isEmpty)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
    }

    @Test("isDraftValid is false for empty name")
    @MainActor
    func draftInvalidEmptyName() {
        let vm = TaxSettingsViewModel()
        vm.draftName = ""
        vm.draftRate = "8.5"
        #expect(!vm.isDraftValid)
    }

    @Test("isDraftValid is false for non-numeric rate")
    @MainActor
    func draftInvalidNonNumericRate() {
        let vm = TaxSettingsViewModel()
        vm.draftName = "State Tax"
        vm.draftRate = "abc"
        #expect(!vm.isDraftValid)
    }

    @Test("isDraftValid is true with valid name and numeric rate")
    @MainActor
    func draftValid() {
        let vm = TaxSettingsViewModel()
        vm.draftName = "State Tax"
        vm.draftRate = "8.5"
        #expect(vm.isDraftValid)
    }

    @Test("beginAdd clears draft fields and sets editingRate to nil")
    @MainActor
    func beginAddClearsDraft() {
        let vm = TaxSettingsViewModel()
        vm.draftName = "Old"
        vm.draftRate = "9"
        vm.beginAdd()
        #expect(vm.draftName == "")
        #expect(vm.draftRate == "")
        #expect(vm.editingRate == nil)
        #expect(vm.showAddSheet)
    }

    @Test("beginEdit populates draft from existing rate")
    @MainActor
    func beginEditPopulates() {
        let vm = TaxSettingsViewModel()
        let rate = TaxRate(id: "r1", name: "County Tax", rate: 2.5, applyToAll: false)
        vm.beginEdit(rate)
        #expect(vm.draftName == "County Tax")
        #expect(vm.draftRate == "2.5")
        #expect(!vm.draftApplyToAll)
        #expect(vm.editingRate == rate)
    }

    @Test("draftRateValue parses valid double")
    @MainActor
    func draftRateValueParse() {
        let vm = TaxSettingsViewModel()
        vm.draftRate = "8.875"
        #expect(vm.draftRateValue == 8.875)
    }

    @Test("draftRateValue is nil for invalid string")
    @MainActor
    func draftRateValueNil() {
        let vm = TaxSettingsViewModel()
        vm.draftRate = "not-a-number"
        #expect(vm.draftRateValue == nil)
    }
}

// MARK: - CompanyInfoViewModel Tests

@Suite("CompanyInfoViewModel")
struct CompanyInfoViewModelTests {

    @Test("Initial state is empty")
    @MainActor
    func initialState() {
        let vm = CompanyInfoViewModel()
        #expect(vm.legalName == "")
        #expect(vm.ein == "")
        #expect(!vm.isSaving)
    }

    @Test("Load populates fields from API")
    @MainActor
    func loadPopulates() async {
        let resp = CompanyInfoResponse(
            legalName: "Acme Corp", dba: "Acme",
            address: "123 Main St", city: "Springfield",
            state: "IL", zip: "62701",
            phone: "555-0001", website: "https://acme.com",
            ein: "12-3456789"
        )
        let stub = CompanyStubClient(info: resp)
        let vm = CompanyInfoViewModel(api: stub)
        await vm.load()
        #expect(vm.legalName == "Acme Corp")
        #expect(vm.ein == "12-3456789")
        #expect(vm.website == "https://acme.com")
        #expect(vm.city == "Springfield")
    }

    @Test("Load sets errorMessage on network failure")
    @MainActor
    func loadFailure() async {
        let vm = CompanyInfoViewModel(api: FailingClient())
        await vm.load()
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - PaymentMethodsViewModel Tests

@Suite("PaymentMethodsViewModel")
struct PaymentMethodsViewModelTests {

    @Test("Default settings have cash and card enabled")
    @MainActor
    func defaultSettings() {
        let vm = PaymentMethodsViewModel()
        #expect(vm.settings.cashEnabled)
        #expect(vm.settings.cardEnabled)
        #expect(!vm.settings.giftCardEnabled)
        #expect(!vm.settings.storeCreditEnabled)
        #expect(!vm.settings.checkEnabled)
    }

    @Test("PaymentMethodSettings default is correct struct")
    func paymentDefaultStruct() {
        let s = PaymentMethodSettings.default
        #expect(s.cashEnabled)
        #expect(s.cardEnabled)
        #expect(!vm_giftEnabled(s))
    }

    private func vm_giftEnabled(_ s: PaymentMethodSettings) -> Bool { s.giftCardEnabled }
}

// MARK: - SmsProviderViewModel Tests

@Suite("SmsProviderViewModel")
struct SmsProviderViewModelTests {

    @Test("Default provider is bizarreCRMManaged")
    @MainActor
    func defaultProvider() {
        let vm = SmsProviderViewModel()
        #expect(vm.selectedProvider == .bizarreCRMManaged)
    }

    @Test("SmsProvider rawValues are stable")
    func providerRawValues() {
        #expect(SmsProvider.twilio.rawValue == "twilio")
        #expect(SmsProvider.bandwidth.rawValue == "bandwidth")
        #expect(SmsProvider.bizarreCRMManaged.rawValue == "bizarrecrm")
    }

    @Test("All SmsProvider cases have non-empty displayName")
    func providerDisplayNames() {
        for p in SmsProvider.allCases {
            #expect(!p.displayName.isEmpty)
        }
    }
}

// MARK: - AppearanceViewModel Tests

@Suite("AppearanceViewModel")
struct AppearanceViewModelTests {

    @Test("Default theme is system")
    @MainActor
    func defaultTheme() {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        let vm = AppearanceViewModel(defaults: defaults)
        #expect(vm.theme == .system)
    }

    @Test("Default accent is orange")
    @MainActor
    func defaultAccent() {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        let vm = AppearanceViewModel(defaults: defaults)
        #expect(vm.accent == .orange)
    }

    @Test("Save and load round-trips all settings")
    @MainActor
    func saveAndLoad() {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        let vm = AppearanceViewModel(defaults: defaults)
        vm.theme = .dark
        vm.accent = .teal
        vm.isCompact = true
        vm.fontScale = 1.2
        vm.reduceMotion = true
        vm.save()

        let vm2 = AppearanceViewModel(defaults: defaults)
        #expect(vm2.theme == .dark)
        #expect(vm2.accent == .teal)
        #expect(vm2.isCompact)
        #expect(vm2.fontScale == 1.2)
        #expect(vm2.reduceMotion)
    }

    @Test("AppTheme display names are non-empty")
    func themeDisplayNames() {
        for t in AppTheme.allCases {
            #expect(!t.displayName.isEmpty)
        }
    }

    @Test("AccentColor display names are non-empty")
    func accentDisplayNames() {
        for a in AccentColor.allCases {
            #expect(!a.displayName.isEmpty)
        }
    }
}

// MARK: - LanguageRegionViewModel Tests

@Suite("LanguageRegionViewModel")
struct LanguageRegionViewModelTests {

    @Test("Default locale matches system locale identifier")
    @MainActor
    func defaultLocale() {
        let vm = LanguageRegionViewModel()
        #expect(vm.locale == Locale.current.identifier)
    }

    @Test("Available locales is non-empty")
    @MainActor
    func availableLocalesNonEmpty() {
        let vm = LanguageRegionViewModel()
        #expect(!vm.availableLocales.isEmpty)
    }

    @Test("Date format options are non-empty")
    @MainActor
    func dateFormatOptionsNonEmpty() {
        let vm = LanguageRegionViewModel()
        #expect(vm.dateFormatOptions.count >= 3)
    }

    @Test("Number format options are non-empty")
    @MainActor
    func numberFormatOptionsNonEmpty() {
        let vm = LanguageRegionViewModel()
        #expect(!vm.numberFormatOptions.isEmpty)
    }

    @Test("Available currencies include USD")
    @MainActor
    func availableCurrenciesIncludeUSD() {
        let vm = LanguageRegionViewModel()
        #expect(vm.availableCurrencies.contains("USD"))
    }
}

// MARK: - DangerZoneViewModel Tests

@Suite("DangerZoneViewModel")
struct DangerZoneViewModelTests {

    @Test("Initial state has no pending actions")
    @MainActor
    func initialState() {
        let vm = DangerZoneViewModel()
        #expect(!vm.isSigning)
        #expect(!vm.isResetting)
        #expect(!vm.isDeleting)
        #expect(vm.errorMessage == nil)
    }

    @Test("deleteTenant sets error when PIN is empty")
    @MainActor
    func deleteTenantRequiresPIN() async {
        let vm = DangerZoneViewModel(api: nil)
        vm.managerPIN = ""
        await vm.deleteTenant()
        #expect(vm.errorMessage == "Enter manager PIN to confirm.")
    }

    @Test("isTrainingMode defaults to false")
    @MainActor
    func isTrainingModeDefault() {
        let vm = DangerZoneViewModel()
        #expect(!vm.isTrainingMode)
    }

    @Test("isTrainingMode set via init")
    @MainActor
    func isTrainingModeInit() {
        let vm = DangerZoneViewModel(api: nil, isTrainingMode: true)
        #expect(vm.isTrainingMode)
    }

    @Test("signOutEverywhere sets errorMessage when api fails")
    @MainActor
    func signOutEverywhereFailure() async {
        let vm = DangerZoneViewModel(api: FailingClient())
        await vm.signOutEverywhere()
        #expect(vm.errorMessage != nil)
    }
}
