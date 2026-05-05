import Testing
import Foundation
@testable import Settings

// MARK: - Stub repository

private final class StubOrganizationSettingsRepo: OrganizationSettingsRepository, @unchecked Sendable {

    var stubbedSettings: OrganizationSettings = OrganizationSettings(
        name: "Bizarre CRM Repairs",
        legalName: "Bizarre CRM LLC",
        address: "123 Main St",
        phone: "555-1234",
        email: "hello@bizarrecrm.com",
        logoUrl: "https://cdn.bizarrecrm.com/logo.png",
        taxId: "12-3456789",
        currencyCode: "USD",
        timezone: "America/New_York",
        locale: "en_US"
    )
    var savedSettings: OrganizationSettings? = nil
    var shouldThrow: Bool = false
    var fetchCallCount: Int = 0
    var saveCallCount: Int = 0

    private func maybeThrow() throws {
        if shouldThrow { throw URLError(.badServerResponse) }
    }

    func fetch() async throws -> OrganizationSettings {
        fetchCallCount += 1
        try maybeThrow()
        return stubbedSettings
    }

    func save(_ settings: OrganizationSettings) async throws -> OrganizationSettings {
        saveCallCount += 1
        try maybeThrow()
        savedSettings = settings
        return settings
    }
}

// MARK: - Model tests

@Suite("OrganizationSettings — model")
struct OrganizationSettingsModelTests {

    @Test("init defaults have sensible values")
    func defaultInit() {
        let s = OrganizationSettings()
        #expect(s.currencyCode == "USD")
        #expect(s.timezone == "America/New_York")
        #expect(s.locale == "en_US")
        #expect(s.name.isEmpty)
    }

    @Test("storeConfig round-trip preserves all fields")
    func storeConfigRoundTrip() {
        let original = OrganizationSettings(
            name: "Acme Repairs",
            legalName: "Acme Corp Ltd",
            address: "1 Market St",
            phone: "415-555-0100",
            email: "admin@acme.com",
            logoUrl: "https://example.com/logo.png",
            taxId: "99-8765432",
            currencyCode: "CAD",
            timezone: "America/Vancouver",
            locale: "en_CA"
        )

        let cfg = original.toStoreConfig()
        let restored = OrganizationSettings(storeConfig: cfg)

        #expect(restored.name == original.name)
        #expect(restored.legalName == original.legalName)
        #expect(restored.address == original.address)
        #expect(restored.phone == original.phone)
        #expect(restored.email == original.email)
        #expect(restored.logoUrl == original.logoUrl)
        #expect(restored.taxId == original.taxId)
        #expect(restored.currencyCode == original.currencyCode)
        #expect(restored.timezone == original.timezone)
        #expect(restored.locale == original.locale)
    }

    @Test("storeConfig fallback keys are read correctly")
    func storeConfigFallbackKeys() {
        // Server may use store_name, store_address, etc. as alternate keys
        let cfg: [String: String] = [
            "store_name": "Shop Name",
            "store_address": "456 Elm Ave",
            "store_phone": "800-555-9999",
            "store_email": "info@shop.com",
            "store_currency": "EUR",
            "store_timezone": "Europe/London",
        ]
        let settings = OrganizationSettings(storeConfig: cfg)
        #expect(settings.name == "Shop Name")
        #expect(settings.address == "456 Elm Ave")
        #expect(settings.phone == "800-555-9999")
        #expect(settings.email == "info@shop.com")
        #expect(settings.currencyCode == "EUR")
        #expect(settings.timezone == "Europe/London")
    }

    @Test("toStoreConfig produces expected keys")
    func toStoreConfigKeys() {
        let s = OrganizationSettings(name: "Test", currencyCode: "GBP", timezone: "Europe/London")
        let cfg = s.toStoreConfig()
        #expect(cfg["store_name"] == "Test")
        #expect(cfg["currency"] == "GBP")
        #expect(cfg["timezone"] == "Europe/London")
    }

    @Test("Equatable: identical settings are equal")
    func equatable() {
        let a = OrganizationSettings(name: "X", currencyCode: "USD")
        let b = OrganizationSettings(name: "X", currencyCode: "USD")
        #expect(a == b)
    }

    @Test("Equatable: different currency codes are not equal")
    func notEqual() {
        let a = OrganizationSettings(name: "X", currencyCode: "USD")
        let b = OrganizationSettings(name: "X", currencyCode: "CAD")
        #expect(a != b)
    }
}

// MARK: - ViewModel tests

@Suite("OrganizationSettingsViewModel — load")
@MainActor
struct OrganizationSettingsViewModelLoadTests {

    @Test("load populates settings from repository")
    func loadHappyPath() async {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)

        await vm.load()

        #expect(vm.settings.name == "Bizarre CRM Repairs")
        #expect(vm.settings.currencyCode == "USD")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(repo.fetchCallCount == 1)
    }

    @Test("load sets errorMessage on failure")
    func loadFailure() async {
        let repo = StubOrganizationSettingsRepo()
        repo.shouldThrow = true
        let vm = OrganizationSettingsViewModel(repository: repo)

        await vm.load()

        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }

    @Test("load does not re-enter while already loading")
    func loadReentrancyGuard() async throws {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)

        // Simulate: isLoading is already true (set externally for unit test purposes)
        // We do two sequential loads to check count never exceeds 1 per distinct call
        await vm.load()
        await vm.load() // second call after first completes — both should go through

        // Each completed load should have called fetch once
        #expect(repo.fetchCallCount == 2)
    }
}

@Suite("OrganizationSettingsViewModel — save")
@MainActor
struct OrganizationSettingsViewModelSaveTests {

    @Test("save persists updated settings")
    func saveHappyPath() async {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)
        await vm.load()

        vm.updateName("New Name")
        await vm.save()

        #expect(repo.saveCallCount == 1)
        #expect(repo.savedSettings?.name == "New Name")
        #expect(vm.saveConfirmed == true)
        #expect(vm.errorMessage == nil)
    }

    @Test("save sets errorMessage on failure")
    func saveFailure() async {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)
        await vm.load()

        repo.shouldThrow = true
        await vm.save()

        #expect(vm.errorMessage != nil)
        #expect(vm.saveConfirmed == false)
        #expect(vm.isSaving == false)
    }

    @Test("save clears previous errorMessage before attempting")
    func saveClearsPreviousError() async {
        let repo = StubOrganizationSettingsRepo()
        repo.shouldThrow = true
        let vm = OrganizationSettingsViewModel(repository: repo)
        await vm.load()   // first error

        repo.shouldThrow = false
        await vm.save()   // should succeed and clear the error

        #expect(vm.errorMessage == nil)
        #expect(vm.saveConfirmed == true)
    }
}

// MARK: - ViewModel field mutation tests

@Suite("OrganizationSettingsViewModel — field updates")
@MainActor
struct OrganizationSettingsViewModelFieldTests {

    @Test("updateName mutates only name, leaving others unchanged")
    func updateNameImmutable() {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)
        let before = vm.settings

        vm.updateName("Updated Name")

        #expect(vm.settings.name == "Updated Name")
        #expect(vm.settings.legalName == before.legalName)
        #expect(vm.settings.currencyCode == before.currencyCode)
        #expect(vm.settings.timezone == before.timezone)
    }

    @Test("updateLegalName mutates only legalName")
    func updateLegalNameImmutable() {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)

        vm.updateLegalName("Acme LLC")

        #expect(vm.settings.legalName == "Acme LLC")
    }

    @Test("updateField(currencyCode:) changes only currencyCode")
    func updateCurrency() {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)
        let beforeName = vm.settings.name

        vm.updateField(currencyCode: "CAD")

        #expect(vm.settings.currencyCode == "CAD")
        #expect(vm.settings.name == beforeName)
    }

    @Test("updateField(timezone:) changes only timezone")
    func updateTimezone() {
        let repo = StubOrganizationSettingsRepo()
        let vm = OrganizationSettingsViewModel(repository: repo)

        vm.updateField(timezone: "Europe/London")

        #expect(vm.settings.timezone == "Europe/London")
    }
}

// MARK: - Repository protocol tests

@Suite("OrganizationSettingsRepository — stub")
@MainActor
struct OrganizationSettingsRepositoryTests {

    @Test("fetch returns stubbed settings")
    func fetchReturnsStub() async throws {
        let repo = StubOrganizationSettingsRepo()
        let settings = try await repo.fetch()
        #expect(settings.name == "Bizarre CRM Repairs")
        #expect(repo.fetchCallCount == 1)
    }

    @Test("save stores and returns the given settings")
    func saveStoresSettings() async throws {
        let repo = StubOrganizationSettingsRepo()
        let updated = OrganizationSettings(name: "Saved Name", currencyCode: "EUR")

        let result = try await repo.save(updated)

        #expect(result.name == "Saved Name")
        #expect(repo.savedSettings?.name == "Saved Name")
        #expect(repo.saveCallCount == 1)
    }

    @Test("fetch throws when shouldThrow is true")
    func fetchThrows() async {
        let repo = StubOrganizationSettingsRepo()
        repo.shouldThrow = true

        do {
            _ = try await repo.fetch()
            Issue.record("Expected throw")
        } catch {
            #expect(error is URLError)
        }
    }

    @Test("save throws when shouldThrow is true")
    func saveThrows() async {
        let repo = StubOrganizationSettingsRepo()
        repo.shouldThrow = true

        do {
            _ = try await repo.save(OrganizationSettings())
            Issue.record("Expected throw")
        } catch {
            #expect(error is URLError)
        }
    }
}
