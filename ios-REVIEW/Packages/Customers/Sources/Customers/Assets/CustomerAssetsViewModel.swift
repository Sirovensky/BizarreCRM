import Foundation
import Observation
import Core

// §5.7 — ViewModel for the customer assets list.
// Swift 6 strict concurrency: @MainActor, @Observable, no shared mutable state.

@MainActor
@Observable
public final class CustomerAssetsViewModel {

    // MARK: - Published state

    public var assets: [CustomerAsset] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String? = nil

    // MARK: - Add-sheet form state

    public var addName: String = ""
    public var addDeviceType: String = ""
    public var addSerial: String = ""
    public var addImei: String = ""
    public var addColor: String = ""
    public var addNotes: String = ""

    public var isAddFormValid: Bool {
        !addName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Detail sheet

    public var selectedAsset: CustomerAsset? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let repository: CustomerAssetsRepository
    @ObservationIgnored private let customerId: Int64

    // MARK: - Init

    public init(repository: CustomerAssetsRepository, customerId: Int64) {
        self.repository = repository
        self.customerId = customerId
    }

    // MARK: - Load

    public func load() async {
        isLoading = assets.isEmpty
        defer { isLoading = false }
        errorMessage = nil
        do {
            assets = try await repository.fetchAssets(customerId: customerId)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    // MARK: - Add

    /// Submits the current add-form fields as a new asset.
    /// Returns `true` on success so the sheet can auto-dismiss.
    @discardableResult
    public func addAsset() async -> Bool {
        guard isAddFormValid, !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let req = CreateCustomerAssetRequest(
            name: addName.trimmingCharacters(in: .whitespaces),
            deviceType: trimmed(addDeviceType),
            serial: trimmed(addSerial),
            imei: trimmed(addImei),
            color: trimmed(addColor),
            notes: trimmed(addNotes)
        )

        do {
            let created = try await repository.addAsset(customerId: customerId, request: req)
            assets = [created] + assets
            resetAddForm()
            return true
        } catch {
            errorMessage = AppError.from(error).localizedDescription
            return false
        }
    }

    // MARK: - Remove (local-only; no server DELETE endpoint used in this screen)

    public func remove(_ asset: CustomerAsset) {
        assets = assets.filter { $0.id != asset.id }
    }

    // MARK: - Form helpers

    public func prepareAddForm() {
        resetAddForm()
        errorMessage = nil
    }

    private func resetAddForm() {
        addName = ""
        addDeviceType = ""
        addSerial = ""
        addImei = ""
        addColor = ""
        addNotes = ""
    }

    private func trimmed(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
