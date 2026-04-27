#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosCatalogFilterSheet
//
// §16.2 Search filters — bottom sheet for extended catalog filtering.
// Presented from the filter button (funnel icon) in PosSearchPanel.
//
// Filter dimensions:
//   - Category: All / Services / Parts / Accessories / Custom (maps to PosCatalogCategory)
//   - In-stock only: Bool
//   - Taxable only:  Bool (client-side only — InventoryListItem.taxRate not yet in API)
//   - Price floor:   Int? (cents)
//   - Price ceiling: Int? (cents)
//
// Changes are applied immediately to the live `@Bindable var filter` so the
// parent sees updates as the user scrolls through options. A "Reset" button
// in the toolbar clears all non-category filters.

public struct PosCatalogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var filter: PosCatalogFilter

    // Local draft — applies on "Done" so the user can cancel without losing the
    // previous filter state. `@State` is initialised from the binding on appear.
    @State private var draft: PosCatalogFilter

    // Price range text buffers — Int? ↔ String conversion.
    @State private var minPriceText: String = ""
    @State private var maxPriceText: String = ""

    public init(filter: Binding<PosCatalogFilter>) {
        _filter = filter
        _draft = State(initialValue: filter.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                filterForm
            }
            .navigationTitle("Filter catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear { syncTextBuffers() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Form

    private var filterForm: some View {
        Form {
            // ── Category ──────────────────────────────────────────────
            Section("Category") {
                ForEach(PosCatalogCategory.allCases) { cat in
                    Button {
                        draft.category = cat
                    } label: {
                        HStack(spacing: BrandSpacing.md) {
                            Image(systemName: cat.systemImage)
                                .foregroundStyle(draft.category == cat ? .bizarreOrange : .bizarreOnSurfaceMuted)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(cat.rawValue)
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            if draft.category == cat {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.bizarreOrange)
                                    .font(.footnote.weight(.semibold))
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("posFilter.category.\(cat.rawValue)")
                    .accessibilityAddTraits(draft.category == cat ? .isSelected : [])
                }
            }

            // ── Stock & tax toggles ───────────────────────────────────
            Section("Availability") {
                Toggle(isOn: $draft.inStockOnly) {
                    Label("In stock only", systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreOnSurface)
                }
                .tint(.bizarreOrange)
                .accessibilityIdentifier("posFilter.inStockOnly")
            }

            // ── Price range ───────────────────────────────────────────
            Section("Price range") {
                HStack(spacing: BrandSpacing.md) {
                    Text("Min")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 36, alignment: .leading)
                    TextField("No minimum", text: $minPriceText)
                        .keyboardType(.numberPad)
                        .foregroundStyle(.bizarreOnSurface)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: minPriceText) { _, new in
                            let digits = new.filter(\.isNumber)
                            minPriceText = digits
                            draft.minPriceCents = digits.isEmpty ? nil : (Int(digits).map { $0 * 100 })
                        }
                    Text("$")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .accessibilityIdentifier("posFilter.minPrice")

                HStack(spacing: BrandSpacing.md) {
                    Text("Max")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 36, alignment: .leading)
                    TextField("No maximum", text: $maxPriceText)
                        .keyboardType(.numberPad)
                        .foregroundStyle(.bizarreOnSurface)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxPriceText) { _, new in
                            let digits = new.filter(\.isNumber)
                            maxPriceText = digits
                            draft.maxPriceCents = digits.isEmpty ? nil : (Int(digits).map { $0 * 100 })
                        }
                    Text("$")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .accessibilityIdentifier("posFilter.maxPrice")
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("posFilter.cancel")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    filter = draft
                    dismiss()
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("posFilter.done")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Reset filters") {
                    draft = .empty
                    syncTextBuffers()
                    BrandHaptics.tap()
                }
                .foregroundStyle(draft.isFiltered ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .disabled(!draft.isFiltered)
                .accessibilityIdentifier("posFilter.reset")
            }
        }
    }

    // MARK: - Helpers

    private func syncTextBuffers() {
        if let min = draft.minPriceCents {
            minPriceText = "\(min / 100)"
        } else {
            minPriceText = ""
        }
        if let max = draft.maxPriceCents {
            maxPriceText = "\(max / 100)"
        } else {
            maxPriceText = ""
        }
    }
}

#endif
