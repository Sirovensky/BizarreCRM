#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - §6.1 Columns Picker (iPad/Mac)

/// Visible columns for the inventory list `Table` view on iPad/Mac.
/// Persisted to `UserDefaults` under the key `inventory.visibleColumns`.
public struct InventoryColumnSet: Sendable, Equatable {
    // All possible columns
    public enum Column: String, CaseIterable, Sendable, Identifiable {
        case sku       = "SKU"
        case name      = "Name"
        case itemType  = "Type"
        case category  = "Category"
        case stock     = "Stock"
        case cost      = "Cost"
        case retail    = "Retail"
        case supplier  = "Supplier"
        case bin       = "Bin"

        public var id: String { rawValue }
    }

    /// Columns currently visible (in display order).
    public var visible: [Column]

    public static let `default` = InventoryColumnSet(visible: [
        .name, .sku, .stock, .retail, .itemType, .supplier
    ])

    // MARK: - Persistence

    private static let defaultsKey = "inventory.visibleColumns"

    public static func load() -> InventoryColumnSet {
        guard let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [String] else {
            return .default
        }
        let cols = raw.compactMap { Column(rawValue: $0) }
        return cols.isEmpty ? .default : InventoryColumnSet(visible: cols)
    }

    public func save() {
        UserDefaults.standard.set(visible.map(\.rawValue), forKey: Self.defaultsKey)
    }

    public func isVisible(_ col: Column) -> Bool { visible.contains(col) }

    public mutating func toggle(_ col: Column) {
        if let idx = visible.firstIndex(of: col) {
            // Require at least 2 columns
            guard visible.count > 2 else { return }
            visible.remove(at: idx)
        } else {
            visible.append(col)
        }
        save()
    }
}

// MARK: - InventoryColumnsPickerSheet

/// Sheet presented from the inventory toolbar (iPad/Mac) that lets admin
/// toggle column visibility. Changes persist to UserDefaults immediately.
public struct InventoryColumnsPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var columnSet: InventoryColumnSet

    public init(columnSet: Binding<InventoryColumnSet>) {
        _columnSet = columnSet
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Visible columns") {
                    ForEach(InventoryColumnSet.Column.allCases) { col in
                        Toggle(
                            col.rawValue,
                            isOn: Binding(
                                get: { columnSet.isVisible(col) },
                                set: { _ in columnSet.toggle(col) }
                            )
                        )
                        .tint(.bizarreOrange)
                        .listRowBackground(Color.bizarreSurface1)
                        .accessibilityLabel("\(col.rawValue) column \(columnSet.isVisible(col) ? "visible" : "hidden")")
                        .accessibilityHint("Toggle to show or hide column")
                    }
                }
                Section {
                    Button("Reset to defaults") {
                        columnSet = .default
                        columnSet.save()
                    }
                    .foregroundStyle(.bizarreError)
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel("Reset column visibility to defaults")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done picking columns")
                        .accessibilityIdentifier("inventory.columns.done")
                }
            }
        }
    }
}
#endif
