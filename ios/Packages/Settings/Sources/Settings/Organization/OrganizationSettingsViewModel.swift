import Foundation
import Observation

// MARK: - §19.5 OrganizationSettingsViewModel

/// Drives `OrganizationSettingsView`.
/// Manages loading, editing, and persisting organisation-level settings.
@MainActor
@Observable
public final class OrganizationSettingsViewModel: Sendable {

    // MARK: - State

    /// The current settings object (editing copy while `isSaving`).
    public var settings: OrganizationSettings = OrganizationSettings()

    public var isLoading: Bool = false
    public var isSaving: Bool = false

    /// Non-nil when an operation fails; cleared before each new operation.
    public var errorMessage: String?

    /// Set to `true` once settings have been successfully saved.
    public var saveConfirmed: Bool = false

    // MARK: - Dependencies

    private let repository: any OrganizationSettingsRepository

    // MARK: - Init

    public init(repository: any OrganizationSettingsRepository) {
        self.repository = repository
    }

    // MARK: - Load

    /// Fetch organisation settings from the server and populate `settings`.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            settings = try await repository.fetch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save

    /// Persist the current `settings` to the server.
    /// Only callable when `canEdit` is `true` (enforced in the view, not here).
    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        saveConfirmed = false
        defer { isSaving = false }
        do {
            settings = try await repository.save(settings)
            saveConfirmed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Field updates (immutable style)

    public func updateName(_ value: String) {
        settings = OrganizationSettings(
            name: value,
            legalName: settings.legalName,
            address: settings.address,
            phone: settings.phone,
            email: settings.email,
            logoUrl: settings.logoUrl,
            taxId: settings.taxId,
            currencyCode: settings.currencyCode,
            timezone: settings.timezone,
            locale: settings.locale,
            receiptFooter: settings.receiptFooter,
            invoiceFooter: settings.invoiceFooter,
            warrantyPolicy: settings.warrantyPolicy,
            returnPolicy: settings.returnPolicy,
            privacyPolicy: settings.privacyPolicy
        )
    }

    public func updateLegalName(_ value: String) {
        settings = OrganizationSettings(
            name: settings.name,
            legalName: value,
            address: settings.address,
            phone: settings.phone,
            email: settings.email,
            logoUrl: settings.logoUrl,
            taxId: settings.taxId,
            currencyCode: settings.currencyCode,
            timezone: settings.timezone,
            locale: settings.locale,
            receiptFooter: settings.receiptFooter,
            invoiceFooter: settings.invoiceFooter,
            warrantyPolicy: settings.warrantyPolicy,
            returnPolicy: settings.returnPolicy,
            privacyPolicy: settings.privacyPolicy
        )
    }

    public func updateField(
        address: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        logoUrl: String? = nil,
        taxId: String? = nil,
        currencyCode: String? = nil,
        timezone: String? = nil,
        locale: String? = nil,
        receiptFooter: String? = nil,
        invoiceFooter: String? = nil,
        warrantyPolicy: String? = nil,
        returnPolicy: String? = nil,
        privacyPolicy: String? = nil
    ) {
        settings = OrganizationSettings(
            name: settings.name,
            legalName: settings.legalName,
            address: address           ?? settings.address,
            phone: phone               ?? settings.phone,
            email: email               ?? settings.email,
            logoUrl: logoUrl           ?? settings.logoUrl,
            taxId: taxId               ?? settings.taxId,
            currencyCode: currencyCode ?? settings.currencyCode,
            timezone: timezone         ?? settings.timezone,
            locale: locale             ?? settings.locale,
            receiptFooter: receiptFooter ?? settings.receiptFooter,
            invoiceFooter: invoiceFooter ?? settings.invoiceFooter,
            warrantyPolicy: warrantyPolicy ?? settings.warrantyPolicy,
            returnPolicy: returnPolicy ?? settings.returnPolicy,
            privacyPolicy: privacyPolicy ?? settings.privacyPolicy
        )
    }
}
