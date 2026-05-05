#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// iPad sortable `Table` for the inventory item list.
///
/// Columns: SKU | Name | Type | Qty | Price
/// Each column header is tappable to sort ascending/descending.
/// Supports single-selection (navigates detail) and multi-selection
/// (batch-edit mode forwarded from `InventoryThreeColumnView`).
///
/// Ownership: §22 iPad polish (Inventory).
public struct InventoryTableView: View {

    // MARK: - Inputs

    let items: [InventoryListItem]
    @Binding var selectedItemId: Int64?
    @Binding var multiSelection: Set<Int64>
    let isBatchSelectMode: Bool
    let api: APIClient?
    let onAdjustStock: (InventoryListItem) -> Void

    // MARK: - Sort state

    @State private var sortOrder: [KeyPathComparator<InventoryListItem>] = [
        KeyPathComparator(\.displayName, order: .forward)
    ]

    // MARK: - Derived

    private var sortedItems: [InventoryListItem] {
        items.sorted(using: sortOrder)
    }

    // MARK: - Body

    public var body: some View {
        Table(sortedItems, selection: tableSelection, sortOrder: $sortOrder) {
            // SKU column — fixed narrow width
            TableColumn("SKU", value: \.sortableSku) { item in
                Text(item.sku ?? "—")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .accessibilityLabel("SKU: \(item.sku ?? "none")")
            }
            .width(min: 80, ideal: 100, max: 140)

            // Name column — flexible, widest
            TableColumn("Name", value: \.displayName) { item in
                InventoryContextMenu(
                    item: item,
                    api: api,
                    onOpen: { selectedItemId = item.id },
                    onAdjustStock: { onAdjustStock(item) },
                    onArchive: { /* §22 stub — Phase 4 */ }
                ) {
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(item.displayName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(2)
                        if let device = item.deviceName, !device.isEmpty {
                            Text(device)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .lineLimit(1)
                        }
                    }
                    .hoverEffect(.highlight)
                }
            }
            .width(min: 160, ideal: 240)

            // Type column
            TableColumn("Type", value: \.sortableType) { item in
                if let type = item.itemType, !type.isEmpty {
                    Text(type.capitalized)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            .width(min: 70, ideal: 90, max: 120)

            // Qty column — right aligned
            TableColumn("Qty", value: \.sortableStock) { item in
                stockCell(for: item)
            }
            .width(min: 60, ideal: 80, max: 100)

            // Price column — right aligned
            TableColumn("Price", value: \.sortablePrice) { item in
                if let cents = item.priceCents {
                    Text(formatMoney(cents))
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .width(min: 80, ideal: 100, max: 130)
        }
        .tableStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase)
    }

    // MARK: - Selection binding

    /// Routes either single or multi selection depending on batch mode.
    private var tableSelection: Binding<Set<Int64>> {
        if isBatchSelectMode {
            return $multiSelection
        }
        return Binding<Set<Int64>>(
            get: { selectedItemId.map { [$0] } ?? [] },
            set: { newSet in
                if let id = newSet.first { selectedItemId = id }
            }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private func stockCell(for item: InventoryListItem) -> some View {
        let stock = item.inStock ?? 0
        if item.isLowStock {
            HStack(spacing: BrandSpacing.xxs) {
                Text("\(stock)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Qty: \(stock), low stock")
        } else {
            Text("\(stock)")
                .font(.brandMono(size: 13))
                .foregroundStyle(stock == 0 ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .monospacedDigit()
                .accessibilityLabel("Qty: \(stock)")
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}

// MARK: - Sortable computed properties on InventoryListItem

extension InventoryListItem {
    /// Used by `TableColumn` `value:` key path for sort; SKU nil sorts last.
    var sortableSku: String { sku ?? "\u{FFFF}" }
    /// Item type nil sorts last.
    var sortableType: String { itemType ?? "\u{FFFF}" }
    /// In-stock quantity as comparable integer.
    var sortableStock: Int { inStock ?? 0 }
    /// Retail price as comparable double; nil sorts last.
    var sortablePrice: Double { retailPrice ?? Double.greatestFiniteMagnitude }
}
#endif
