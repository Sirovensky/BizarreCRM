#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

/// Collapsible Liquid Glass filter drawer for the Inventory list (§6.1).
///
/// Hosts:
///  - Manufacturer / Supplier / Category text filters
///  - Min / Max price (entered as dollars, stored as cents)
///  - Hide out-of-stock toggle
///  - Reorderable-only toggle
///  - Low-stock-only toggle
///
/// Lives in the navigation chrome area (Liquid Glass allowed here).
/// Collapses to a single glass pill when no filter is active.
public struct InventoryFilterDrawer: View {
    @Binding var filter: InventoryAdvancedFilter
    @Binding var isExpanded: Bool

    // Local editable copies — committed to binding on "Apply".
    @State private var manufacturer: String = ""
    @State private var supplier: String = ""
    @State private var category: String = ""
    @State private var minPriceDollars: String = ""
    @State private var maxPriceDollars: String = ""
    @State private var hideOutOfStock: Bool = false
    @State private var reorderableOnly: Bool = false
    @State private var lowStockOnly: Bool = false

    let onApply: () -> Void

    public init(
        filter: Binding<InventoryAdvancedFilter>,
        isExpanded: Binding<Bool>,
        onApply: @escaping () -> Void
    ) {
        self._filter = filter
        self._isExpanded = isExpanded
        self.onApply = onApply
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Collapsed pill — always visible
            collapsedBar

            if isExpanded {
                expandedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(BrandMotion.spring, value: isExpanded)
        .onAppear(perform: syncFromBinding)
        .onChange(of: filter) { _, _ in syncFromBinding() }
    }

    // MARK: - Collapsed bar (Liquid Glass chrome)

    private var collapsedBar: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle\(filter.isEmpty ? "" : ".fill")")
                .foregroundStyle(filter.isEmpty ? Color.bizarreOnSurfaceMuted : Color.bizarreOrange)
                .accessibilityHidden(true)

            Text(filter.isEmpty ? "Filters" : "Filters (active)")
                .font(.brandLabelLarge())
                .foregroundStyle(filter.isEmpty ? Color.bizarreOnSurface : Color.bizarreOrange)
                .accessibilityLabel(filter.isEmpty
                    ? "No filters active. Tap to expand filters."
                    : "Filters active. Tap to expand filters.")

            Spacer()

            if !filter.isEmpty {
                Button("Clear", action: clearAll)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Clear all inventory filters")
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Expanded content (Liquid Glass container)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.base) {
            // Text fields row
            VStack(spacing: BrandSpacing.sm) {
                FilterTextField(label: "Manufacturer", text: $manufacturer)
                FilterTextField(label: "Supplier", text: $supplier)
                FilterTextField(label: "Category", text: $category)
            }

            // Price range row
            HStack(spacing: BrandSpacing.sm) {
                FilterTextField(label: "Min price $", text: $minPriceDollars, keyboardType: .decimalPad)
                FilterTextField(label: "Max price $", text: $maxPriceDollars, keyboardType: .decimalPad)
            }

            // Toggle row
            VStack(spacing: BrandSpacing.xs) {
                FilterToggle("Hide out-of-stock", isOn: $hideOutOfStock)
                FilterToggle("Reorderable only", isOn: $reorderableOnly)
                FilterToggle("Low-stock only", isOn: $lowStockOnly)
            }

            // Action buttons
            HStack(spacing: BrandSpacing.sm) {
                Button("Reset", action: clearAll)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Reset all filters to defaults")

                Spacer()

                Button(action: applyFilters) {
                    Text("Apply")
                        .font(.brandLabelLarge())
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                        .foregroundStyle(.black)
                        .background(.bizarreOrange, in: Capsule())
                }
                .accessibilityLabel("Apply inventory filters")
            }
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 0, style: .continuous),
                    tint: .bizarreOrange.opacity(0.05))
    }

    // MARK: - Actions

    private func applyFilters() {
        filter = InventoryAdvancedFilter(
            manufacturer: manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            supplier: supplier.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            minPriceCents: parseDollarsCents(minPriceDollars),
            maxPriceCents: parseDollarsCents(maxPriceDollars),
            hideOutOfStock: hideOutOfStock,
            reorderableOnly: reorderableOnly,
            lowStockOnly: lowStockOnly
        )
        isExpanded = false
        onApply()
    }

    private func clearAll() {
        manufacturer = ""
        supplier = ""
        category = ""
        minPriceDollars = ""
        maxPriceDollars = ""
        hideOutOfStock = false
        reorderableOnly = false
        lowStockOnly = false
        filter = .init()
        onApply()
    }

    private func syncFromBinding() {
        manufacturer = filter.manufacturer ?? ""
        supplier = filter.supplier ?? ""
        category = filter.category ?? ""
        minPriceDollars = filter.minPriceCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        maxPriceDollars = filter.maxPriceCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        hideOutOfStock = filter.hideOutOfStock
        reorderableOnly = filter.reorderableOnly
        lowStockOnly = filter.lowStockOnly
    }

    private func parseDollarsCents(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let d = Double(trimmed) else { return nil }
        return Int((d * 100).rounded())
    }
}

// MARK: - Sub-components

private struct FilterTextField: View {
    let label: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(keyboardType)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(label)
    }
}

private struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .tint(.bizarreOrange)
            .accessibilityLabel(label)
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
