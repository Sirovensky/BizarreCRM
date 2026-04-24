import Foundation
import Observation

// MARK: - §19.1 ProfileSettingsViewModel

@MainActor
@Observable
public final class ProfileSettingsViewModel: Sendable {

    // MARK: - Observed state

    public var settings: ProfileSettings = ProfileSettings()
    public var userId: Int = 0

    public var isLoading: Bool = false
    public var isSaving: Bool = false
    public var errorMessage: String?
    public var successMessage: String?

    /// Whether the in-memory settings differ from the last-loaded server state.
    public var isDirty: Bool { settings != lastSaved }

    // MARK: - Private

    private let repository: (any ProfileSettingsRepository)?
    private var lastSaved: ProfileSettings = ProfileSettings()

    // MARK: - Init

    public init(repository: (any ProfileSettingsRepository)? = nil) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        guard let repository else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let result = try await repository.fetchProfile()
            userId = result.id
            settings = result.settings
            lastSaved = result.settings
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save

    public func save() async {
        guard let repository else { return }
        if let validationErr = settings.validationError() {
            errorMessage = validationErr.localizedDescription
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let saved = try await repository.saveProfile(id: userId, settings: settings)
            settings = saved
            lastSaved = saved
            successMessage = "Profile saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Field setters (immutable update pattern)

    public func setFirstName(_ value: String) {
        settings = ProfileSettings(
            firstName: value,
            lastName:  settings.lastName,
            email:     settings.email,
            phone:     settings.phone,
            avatarUrl: settings.avatarUrl,
            timezone:  settings.timezone,
            locale:    settings.locale
        )
    }

    public func setLastName(_ value: String) {
        settings = ProfileSettings(
            firstName: settings.firstName,
            lastName:  value,
            email:     settings.email,
            phone:     settings.phone,
            avatarUrl: settings.avatarUrl,
            timezone:  settings.timezone,
            locale:    settings.locale
        )
    }

    public func setEmail(_ value: String) {
        settings = ProfileSettings(
            firstName: settings.firstName,
            lastName:  settings.lastName,
            email:     value,
            phone:     settings.phone,
            avatarUrl: settings.avatarUrl,
            timezone:  settings.timezone,
            locale:    settings.locale
        )
    }

    public func setPhone(_ value: String) {
        settings = ProfileSettings(
            firstName: settings.firstName,
            lastName:  settings.lastName,
            email:     settings.email,
            phone:     value,
            avatarUrl: settings.avatarUrl,
            timezone:  settings.timezone,
            locale:    settings.locale
        )
    }

    public func dismissSuccess() {
        successMessage = nil
    }

    public func dismissError() {
        errorMessage = nil
    }
}
