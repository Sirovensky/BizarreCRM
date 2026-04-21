import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43.4 Part SKU Picker

/// Inline search + select for a single inventory SKU.
/// Embedded inside `ServicePartMappingSheet` — not a standalone sheet.
@MainActor
struct PartSkuPicker: View {
    @Binding var query: String
    let results: [InventorySearchResult]
    let isSearching: Bool
    let onSelect: (InventorySearchResult) -> Void
    let onQueryChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Search SKU or name", text: $query)
                    #if canImport(UIKit)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .onChange(of: query) { _, new in onQueryChange(new) }
                    .accessibilityLabel("Search parts by SKU or name")
                    .accessibilityIdentifier("partSkuPicker.search")
                if isSearching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, BrandSpacing.base)

            // Results list (up to 30)
            if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results.prefix(30)) { item in
                            SkuResultRow(item: item) {
                                onSelect(item)
                            }
                            Divider().padding(.leading, BrandSpacing.base)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, BrandSpacing.base)
            } else if !query.isEmpty && !isSearching {
                Text("No parts found for \"\(query)\"")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.xs)
                    .accessibilityLabel("No parts found")
            }
        }
    }
}

// MARK: - Result Row

private struct SkuResultRow: View {
    let item: InventorySearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(item.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(item.sku)
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("SKU: \(item.sku)")
                }
                Spacer()
                if item.stockQty > 0 {
                    Text("×\(item.stockQty)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel("\(item.stockQty) in stock")
                } else {
                    Text("Out")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Out of stock")
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), SKU \(item.sku)")
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }
}
