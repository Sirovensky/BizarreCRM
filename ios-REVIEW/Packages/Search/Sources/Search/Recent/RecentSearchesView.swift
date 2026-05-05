import SwiftUI
import DesignSystem

/// §18.6 — Chip row shown below the search field when it is empty.
public struct RecentSearchesView: View {

    let queries: [String]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        queries: [String],
        onSelect: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        self.queries = queries
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        if queries.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Recent")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.xs) {
                        ForEach(queries, id: \.self) { query in
                            RecentChip(query: query, onSelect: onSelect, onDelete: onDelete)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                }
            }
        }
    }
}

// MARK: - Chip

private struct RecentChip: View {
    let query: String
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Button {
                onSelect(query)
            } label: {
                Text(query)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .accessibilityLabel("Search for \(query)")

            Button {
                onDelete(query)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Remove \(query) from recent searches")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .brandGlass(.regular, interactive: true)
    }
}
