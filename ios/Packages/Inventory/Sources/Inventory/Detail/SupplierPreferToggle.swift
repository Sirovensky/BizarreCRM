#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - SupplierPreferToggle

/// §6.2 / §6.9 — Toggle that marks a supplier as the preferred source for an
/// inventory item.
///
/// The preference is persisted locally via `UserDefaults` using a composite key
/// `preferredSupplier.<itemId>` so it survives app restarts without requiring a
/// dedicated server endpoint.  When the server adds a `preferred_supplier_id`
/// field to the inventory row this component can be upgraded to call
/// `PATCH /api/v1/inventory/:id` transparently.
///
/// Visual: a compact `Toggle` row styled to match `SupplierPanelCard`.
/// When preferred, a filled star badge animates in next to the label.
///
/// Usage:
/// ```swift
/// SupplierPreferToggle(itemId: item.id, supplierName: "Acme Parts")
/// ```
public struct SupplierPreferToggle: View {

    // MARK: Input

    public let itemId: Int64
    public let supplierName: String

    // MARK: State

    @State private var isPreferred: Bool

    // MARK: UserDefaults key

    private var udKey: String { "preferredSupplier.\(itemId)" }

    // MARK: Init

    public init(itemId: Int64, supplierName: String) {
        self.itemId = itemId
        self.supplierName = supplierName
        _isPreferred = State(
            wrappedValue: UserDefaults.standard.bool(forKey: "preferredSupplier.\(itemId)")
        )
    }

    // MARK: Body

    public var body: some View {
        Toggle(isOn: $isPreferred.animation()) {
            HStack(spacing: BrandSpacing.xs) {
                if isPreferred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.bizarreOrange)
                        .imageScale(.small)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preferred supplier")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(supplierName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
        }
        .tint(.bizarreOrange)
        .onChange(of: isPreferred) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: udKey)
        }
        .accessibilityLabel(
            isPreferred
                ? "\(supplierName) is the preferred supplier. Toggle to remove preference."
                : "Set \(supplierName) as the preferred supplier."
        )
    }
}
#endif
