import Foundation
import Observation
import Core

// MARK: - PosDevicePickerViewModel
//
// Drives `PosDevicePickerSheet`. Loads the customer's saved assets via the
// repository and exposes the full option list (assets + sentinels).

@MainActor
@Observable
public final class PosDevicePickerViewModel {

    // MARK: - Published state

    /// All options to show in the sheet, including sentinels.
    public private(set) var options: [PosDeviceOption] = []

    /// The currently highlighted row, or `nil` when nothing is selected yet.
    public private(set) var selected: PosDeviceOption?

    /// `true` while an async load is in flight.
    public private(set) var isLoading: Bool = false

    /// Non-`nil` when the last load attempt failed.
    public private(set) var errorMessage: String?

    // MARK: - Private

    private let repository: any PosDevicePickerRepository

    // MARK: - Init

    public init(repository: any PosDevicePickerRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Fetches assets for `customerId` and rebuilds `options`.
    /// Safe to call again to retry after an error.
    public func load(customerId: Int64) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            options = try await repository.fetchAssets(customerId: customerId)
        } catch {
            AppLog.ui.error(
                "PosDevicePickerVM load failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
            // Fall back to the two sentinel rows so the sheet is still usable.
            options = [.noSpecificDevice, .addNew]
        }
    }

    /// Marks `option` as selected. Calling with the already-selected value
    /// keeps it selected (no toggle — the sheet is dismissed on confirm).
    public func select(_ option: PosDeviceOption) {
        selected = option
    }

    /// Clears the selection (e.g. when the sheet is dismissed without confirming).
    public func clearSelection() {
        selected = nil
    }

    // MARK: - Derived

    /// The asset id to attach to a cart line item, or `nil` when
    /// `.noSpecificDevice` or `.addNew` is selected.
    public var selectedAssetId: Int64? {
        selected?.assetId
    }
}
