#if canImport(UIKit)
import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - §6.8 AssetPickerProtocol
//
// Cross-package boundary: Inventory owns assets; Tickets (Agent 3) needs to
// issue a loaner from a ticket. Instead of coupling packages, Tickets declares
// its own protocol with the same shape and Inventory ships a concrete picker
// view (AssetPickerView) that Agent 3 can inject at runtime.
//
// Agent 3 usage example:
//   InventoryAssetPickerView(api: api) { asset in
//       // asset.id → POST /loaners/:id/loan
//   }

// MARK: - ViewModel

/// ViewModel that loads available assets and drives the picker UI.
@MainActor
@Observable
public final class AssetPickerViewModel {

    public private(set) var assets: [InventoryAsset] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    /// Filter text bound to the search field.
    public var searchText = ""

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Load assets that are currently available for issue.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            assets = try await api.listAvailableAssets()
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Failed to load assets."
            AppLog.ui.error("AssetPicker load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Assets filtered by the current `searchText`.
    public var filteredAssets: [InventoryAsset] {
        guard !searchText.isEmpty else { return assets }
        let q = searchText.lowercased()
        return assets.filter { asset in
            asset.name.lowercased().contains(q)
                || (asset.serial?.lowercased().contains(q) ?? false)
                || (asset.condition?.lowercased().contains(q) ?? false)
        }
    }
}

// MARK: - Picker View

/// A searchable list of available loaner assets.
/// Used by Tickets (Agent 3) to "Issue loaner" from a ticket detail.
///
/// Presents as a sheet. On selection, calls `onSelect` with the chosen asset.
/// Closing without selection calls `onCancel`.
public struct InventoryAssetPickerView: View {
    @State private var vm: AssetPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSelect: (InventoryAsset) -> Void
    let onCancel: (() -> Void)?

    public init(
        api: APIClient,
        onSelect: @escaping (InventoryAsset) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        _vm = State(wrappedValue: AssetPickerViewModel(api: api))
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading assets…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
                } else if vm.filteredAssets.isEmpty {
                    ContentUnavailableView(
                        "No available assets",
                        systemImage: "shippingbox",
                        description: Text("All loaner devices are currently checked out or retired.")
                    )
                } else {
                    List(vm.filteredAssets) { asset in
                        assetRow(asset)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
            .searchable(text: $vm.searchText, prompt: "Search by name or serial")
        }
        .task { await vm.load() }
    }

    // MARK: - Row

    private func assetRow(_ asset: InventoryAsset) -> some View {
        Button {
            onSelect(asset)
            dismiss()
        } label: {
            HStack(spacing: BrandSpacing.md) {
                // Status icon
                Image(systemName: "shippingbox")
                    .foregroundStyle(Color.bizarrePrimary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(asset.name)
                        .font(.bizarreBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.bizarreTextPrimary)

                    HStack(spacing: BrandSpacing.xs) {
                        if let serial = asset.serial {
                            Label(serial, systemImage: "number")
                                .font(.bizarreCaption)
                                .foregroundStyle(Color.bizarreTextSecondary)
                        }
                        if let condition = asset.condition {
                            Text("· \(condition)")
                                .font(.bizarreCaption)
                                .foregroundStyle(Color.bizarreTextSecondary)
                        }
                    }
                }

                Spacer()

                statusChip(asset.status)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: asset))
        .accessibilityHint("Double-tap to select this asset")
    }

    private func statusChip(_ status: AssetStatus) -> some View {
        Text(status.displayName)
            .font(.bizarreCaption)
            .fontWeight(.medium)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                Capsule()
                    .fill(status == .available ? Color.bizarreSuccess.opacity(0.15) : Color.bizarreWarning.opacity(0.15))
            )
            .foregroundStyle(status == .available ? Color.bizarreSuccess : Color.bizarreWarning)
    }

    private func accessibilityLabel(for asset: InventoryAsset) -> String {
        var parts: [String] = [asset.name, asset.status.displayName]
        if let serial = asset.serial { parts.append("Serial \(serial)") }
        if let condition = asset.condition { parts.append(condition) }
        return parts.joined(separator: ". ")
    }
}

#endif
