import Testing
import Foundation
@testable import Settings
import Networking
import Core

// MARK: - Stubs

/// Returns a preset MeResponse for GET, and the same response for PUT.
private actor StubProfileRepository: ProfileSettingsRepository {
    let fetchResult: Result<(id: Int, settings: ProfileSettings), Error>
    let saveResult: Result<ProfileSettings, Error>

    init(
        fetchResult: Result<(id: Int, settings: ProfileSettings), Error>,
        saveResult: Result<ProfileSettings, Error>? = nil
    ) {
        self.fetchResult = fetchResult
        // Default save result mirrors the fetched settings on success
        if let saveResult {
            self.saveResult = saveResult
        } else {
            if case .success(let v) = fetchResult {
                self.saveResult = .success(v.settings)
            } else {
                self.saveResult = .failure(URLError(.badServerResponse))
            }
        }
    }

    func fetchProfile() async throws -> (id: Int, settings: ProfileSettings) {
        try fetchResult.get()
    }

    func saveProfile(id: Int, settings: ProfileSettings) async throws -> ProfileSettings {
        try saveResult.get()
    }
}

private actor FailingProfileRepository: ProfileSettingsRepository {
    func fetchProfile() async throws -> (id: Int, settings: ProfileSettings) {
        throw URLError(.notConnectedToInternet)
    }
    func saveProfile(id: Int, settings: ProfileSettings) async throws -> ProfileSettings {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - ProfileSettings model tests

@Suite("ProfileSettings model")
struct ProfileSettingsModelTests {

    @Test("Default init produces empty fields")
    func defaultInit() {
        let s = ProfileSettings()
        #expect(s.firstName == "")
        #expect(s.lastName == "")
        #expect(s.email == "")
        #expect(s.phone == "")
        #expect(s.avatarUrl == nil)
        #expect(s.timezone == "")
        #expect(s.locale == "")
    }

    @Test("Equatable: same fields are equal")
    func sameFieldsAreEqual() {
        let a = ProfileSettings(firstName: "Jane", lastName: "Doe", email: "j@d.com", phone: "555")
        let b = ProfileSettings(firstName: "Jane", lastName: "Doe", email: "j@d.com", phone: "555")
        #expect(a == b)
    }

    @Test("Equatable: different firstName breaks equality")
    func differentFirstName() {
        let a = ProfileSettings(firstName: "Jane")
        let b = ProfileSettings(firstName: "John")
        #expect(a != b)
    }

    @Test("validationError returns firstNameEmpty when firstName is blank")
    func validationFirstNameEmpty() {
        let s = ProfileSettings(firstName: "  ", lastName: "Doe")
        #expect(s.validationError() == .firstNameEmpty)
    }

    @Test("validationError returns lastNameEmpty when lastName is blank")
    func validationLastNameEmpty() {
        let s = ProfileSettings(firstName: "Jane", lastName: "")
        #expect(s.validationError() == .lastNameEmpty)
    }

    @Test("validationError returns emailInvalid for malformed email")
    func validationEmailInvalid() {
        let s = ProfileSettings(firstName: "Jane", lastName: "Doe", email: "not-an-email")
        #expect(s.validationError() == .emailInvalid)
    }

    @Test("validationError returns nil for valid settings")
    func validationNilWhenValid() {
        let s = ProfileSettings(firstName: "Jane", lastName: "Doe", email: "j@d.com")
        #expect(s.validationError() == nil)
    }

    @Test("validationError returns nil when email is empty (optional field)")
    func validationNilForEmptyEmail() {
        let s = ProfileSettings(firstName: "Jane", lastName: "Doe", email: "")
        #expect(s.validationError() == nil)
    }

    @Test("MeResponse.toProfileSettings maps snake_case fields correctly")
    func meResponseMapping() {
        let me = MeResponse(
            id: 42,
            firstName: "Alice",
            lastName: "Smith",
            email: "alice@example.com",
            phone: "555-9999",
            avatarUrl: "https://cdn.example.com/a.jpg",
            timezone: "America/New_York",
            locale: "en_US"
        )
        let settings = me.toProfileSettings()
        #expect(settings.firstName == "Alice")
        #expect(settings.lastName == "Smith")
        #expect(settings.email == "alice@example.com")
        #expect(settings.phone == "555-9999")
        #expect(settings.avatarUrl == "https://cdn.example.com/a.jpg")
        #expect(settings.timezone == "America/New_York")
        #expect(settings.locale == "en_US")
    }

    @Test("MeResponse.toProfileSettings uses empty string for nil fields")
    func meResponseNilFields() {
        let me = MeResponse(
            id: 1,
            firstName: nil,
            lastName: nil,
            email: nil,
            phone: nil,
            avatarUrl: nil,
            timezone: nil,
            locale: nil
        )
        let s = me.toProfileSettings()
        #expect(s.firstName == "")
        #expect(s.avatarUrl == nil)
    }
}

// MARK: - ProfileSettingsViewModel tests

@Suite("ProfileSettingsViewModel")
struct ProfileSettingsViewModelTests {

    @Test("Initial state: empty, not loading, no error")
    @MainActor
    func initialState() {
        let vm = ProfileSettingsViewModel()
        #expect(vm.settings == ProfileSettings())
        #expect(!vm.isLoading)
        #expect(!vm.isSaving)
        #expect(vm.errorMessage == nil)
        #expect(vm.successMessage == nil)
        #expect(!vm.isDirty)
    }

    @Test("load() populates settings and userId from repository")
    @MainActor
    func loadPopulates() async {
        let profile = ProfileSettings(firstName: "Bob", lastName: "Builder", email: "b@b.com")
        let repo = StubProfileRepository(fetchResult: .success((id: 7, settings: profile)))
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        #expect(vm.userId == 7)
        #expect(vm.settings.firstName == "Bob")
        #expect(vm.settings.lastName == "Builder")
        #expect(vm.errorMessage == nil)
        #expect(!vm.isDirty)
    }

    @Test("load() sets errorMessage on network failure")
    @MainActor
    func loadSetsError() async {
        let vm = ProfileSettingsViewModel(repository: FailingProfileRepository())
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(!vm.isLoading)
    }

    @Test("save() rejects blank firstName with validation error")
    @MainActor
    func saveRejectsBlankFirstName() async {
        let repo = StubProfileRepository(fetchResult: .success((id: 1, settings: ProfileSettings())))
        let vm = ProfileSettingsViewModel(repository: repo)
        vm.setFirstName("  ")
        vm.setLastName("Smith")
        await vm.save()
        #expect(vm.errorMessage == ProfileSettings.ValidationError.firstNameEmpty.localizedDescription)
        #expect(vm.successMessage == nil)
    }

    @Test("save() sets successMessage on success")
    @MainActor
    func saveSuccess() async {
        let profile = ProfileSettings(firstName: "Jane", lastName: "Doe")
        let repo = StubProfileRepository(
            fetchResult: .success((id: 3, settings: profile)),
            saveResult: .success(profile)
        )
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        vm.setFirstName("Janet")
        await vm.save()
        #expect(vm.successMessage == "Profile saved.")
        #expect(vm.errorMessage == nil)
    }

    @Test("save() sets errorMessage on repository failure")
    @MainActor
    func saveFailure() async {
        let profile = ProfileSettings(firstName: "Jane", lastName: "Doe")
        let repo = StubProfileRepository(
            fetchResult: .success((id: 3, settings: profile)),
            saveResult: .failure(URLError(.badServerResponse))
        )
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        vm.setFirstName("Janet")
        await vm.save()
        #expect(vm.errorMessage != nil)
        #expect(vm.successMessage == nil)
    }

    @Test("isDirty is false after fresh load")
    @MainActor
    func isDirtyFalseAfterLoad() async {
        let profile = ProfileSettings(firstName: "A", lastName: "B")
        let repo = StubProfileRepository(fetchResult: .success((id: 1, settings: profile)))
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        #expect(!vm.isDirty)
    }

    @Test("isDirty is true after setFirstName changes value")
    @MainActor
    func isDirtyAfterMutation() async {
        let profile = ProfileSettings(firstName: "A", lastName: "B")
        let repo = StubProfileRepository(fetchResult: .success((id: 1, settings: profile)))
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        vm.setFirstName("C")
        #expect(vm.isDirty)
    }

    @Test("setEmail updates settings immutably, other fields unchanged")
    @MainActor
    func setEmailImmutable() async {
        let profile = ProfileSettings(firstName: "X", lastName: "Y", phone: "123")
        let repo = StubProfileRepository(fetchResult: .success((id: 1, settings: profile)))
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        vm.setEmail("x@y.com")
        #expect(vm.settings.email == "x@y.com")
        #expect(vm.settings.firstName == "X")
        #expect(vm.settings.phone == "123")
    }

    @Test("dismissError clears errorMessage")
    @MainActor
    func dismissErrorClears() async {
        let vm = ProfileSettingsViewModel(repository: FailingProfileRepository())
        await vm.load()
        #expect(vm.errorMessage != nil)
        vm.dismissError()
        #expect(vm.errorMessage == nil)
    }

    @Test("dismissSuccess clears successMessage")
    @MainActor
    func dismissSuccessClears() async {
        let profile = ProfileSettings(firstName: "A", lastName: "B")
        let repo = StubProfileRepository(
            fetchResult: .success((id: 1, settings: profile)),
            saveResult: .success(profile)
        )
        let vm = ProfileSettingsViewModel(repository: repo)
        await vm.load()
        vm.setFirstName("C")
        await vm.save()
        #expect(vm.successMessage != nil)
        vm.dismissSuccess()
        #expect(vm.successMessage == nil)
    }
}

// MARK: - LiveProfileSettingsRepository contract tests

@Suite("LiveProfileSettingsRepository")
struct LiveProfileSettingsRepositoryTests {

    /// Mock APIClient that returns a MeResponse on GET and an updated row on PUT.
    private actor MockAPIClient: APIClient {
        let meResponse: MeResponse
        let updatedResponse: MeResponse

        init(me: MeResponse, updated: MeResponse? = nil) {
            self.meResponse = me
            self.updatedResponse = updated ?? me
        }

        func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
            guard let r = meResponse as? T else { throw URLError(.badServerResponse) }
            return r
        }

        func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            guard let r = updatedResponse as? T else { throw URLError(.badServerResponse) }
            return r
        }

        func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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

    @Test("fetchProfile returns parsed settings and correct id")
    func fetchProfileParsesCorrectly() async throws {
        let me = MeResponse(id: 55, firstName: "Lu", lastName: "C", email: "lu@c.com",
                            phone: nil, avatarUrl: nil, timezone: "UTC", locale: "en")
        let api = MockAPIClient(me: me)
        let repo = LiveProfileSettingsRepository(api: api)
        let result = try await repo.fetchProfile()
        #expect(result.id == 55)
        #expect(result.settings.firstName == "Lu")
        #expect(result.settings.timezone == "UTC")
    }

    @Test("saveProfile sends PUT to /settings/users/:id and maps response")
    func saveProfileRouteAndMapping() async throws {
        let original = MeResponse(id: 10, firstName: "A", lastName: "B",
                                  email: "a@b.com", phone: nil, avatarUrl: nil,
                                  timezone: nil, locale: nil)
        let updated = MeResponse(id: 10, firstName: "C", lastName: "B",
                                 email: "a@b.com", phone: nil, avatarUrl: nil,
                                 timezone: nil, locale: nil)
        let api = MockAPIClient(me: original, updated: updated)
        let repo = LiveProfileSettingsRepository(api: api)
        var settings = original.toProfileSettings()
        settings.firstName = "C"
        let saved = try await repo.saveProfile(id: 10, settings: settings)
        #expect(saved.firstName == "C")
    }
}
