import Foundation
import Observation
import Networking

// MARK: - §43.3 Price Override Editor ViewModel

/// Backing ViewModel for `PriceOverrideEditorSheet`.
@MainActor
@Observable
public final class PriceOverrideEditorViewModel {

    // MARK: - Form state
    public var scope: OverrideScope = .tenant
    public var customerId: String = ""
    public var rawPrice: String = ""
    public var reason: String = ""

    // MARK: - UI state
    public private(set) var isSaving: Bool = false
    public private(set) var saveError: String?
    public private(set) var savedOverride: PriceOverride?

    /// Inline validation message shown under the price field.
    public var priceValidationMessage: String? {
        guard !rawPrice.isEmpty else { return nil }
        if case .failure(let err) = PriceOverrideValidator.validate(rawPrice: rawPrice, scope: scope, customerId: nil) {
            switch err {
            case .priceInvalid, .priceNotPositive: return err.errorDescription
            default: return nil
            }
        }
        return nil
    }

    // MARK: - Private
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let serviceId: String

    public init(api: APIClient, serviceId: String) {
        self.api = api
        self.serviceId = serviceId
    }

    // MARK: - Public API

    /// Validate + POST. On success `savedOverride` is populated.
    public func save() async {
        saveError = nil
        let result = PriceOverrideValidator.validate(rawPrice: rawPrice, scope: scope, customerId: customerId)
        switch result {
        case .failure(let err):
            saveError = err.errorDescription
            return
        case .success(let cents):
            isSaving = true
            defer { isSaving = false }
            do {
                let req = CreatePriceOverrideRequest(
                    serviceId: serviceId,
                    scope: scope,
                    customerId: scope == .customer ? customerId.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    priceCents: cents,
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason
                )
                savedOverride = try await api.createPriceOverride(req)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    /// Reset form to defaults (e.g. on sheet re-use).
    public func reset() {
        scope = .tenant
        customerId = ""
        rawPrice = ""
        reason = ""
        saveError = nil
        savedOverride = nil
    }
}
