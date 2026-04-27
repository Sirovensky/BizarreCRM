import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §18.1 Type-ahead preview — top 3 hits in dropdown with "See all" footer

/// Lightweight popover that shows while the user types in a search field.
/// Displays top 3 merged results + a "See all results for 'X'" footer.
/// Dismisses when the user taps "See all" (triggers full search screen) or ⎋.
public struct TypeAheadPreviewView: View {
    let query: String
    let hits: [TypeAheadHit]
    let onSelectHit: (TypeAheadHit) -> Void
    let onSeeAll: () -> Void

    public init(
        query: String,
        hits: [TypeAheadHit],
        onSelectHit: @escaping (TypeAheadHit) -> Void,
        onSeeAll: @escaping () -> Void
    ) {
        self.query = query
        self.hits = hits
        self.onSelectHit = onSelectHit
        self.onSeeAll = onSeeAll
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(hits.prefix(3)) { hit in
                Button { onSelectHit(hit) } label: {
                    TypeAheadRow(hit: hit)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                Divider().padding(.leading, 44)
            }
            if !hits.isEmpty {
                Button(action: onSeeAll) {
                    HStack {
                        Text("See all results for ")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        + Text("\"\(query)\"")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOrange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type-ahead preview: \(hits.prefix(3).count) results")
    }
}

// MARK: - TypeAheadHit model

public struct TypeAheadHit: Identifiable, Sendable {
    public let id: String
    public let type: String        // "ticket", "customer", "inventory", etc.
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let entityId: Int64?

    public init(id: String, type: String, title: String, subtitle: String? = nil, badge: String? = nil, entityId: Int64? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.entityId = entityId
    }

    var icon: String {
        switch type {
        case "ticket":      return "wrench.and.screwdriver"
        case "customer":    return "person.circle"
        case "inventory":   return "shippingbox"
        case "invoice":     return "doc.text"
        case "estimate":    return "doc.badge.plus"
        case "appointment": return "calendar"
        case "sms":         return "message"
        default:            return "magnifyingglass"
        }
    }
}

// MARK: - TypeAheadRow

private struct TypeAheadRow: View {
    let hit: TypeAheadHit

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: hit.icon)
                .font(.system(size: 16))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let subtitle = hit.subtitle {
                    Text(subtitle)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let badge = hit.badge {
                Text(badge)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.bizarreSurface2, in: Capsule())
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.type): \(hit.title)\(hit.subtitle.map { ", \($0)" } ?? "")")
    }
}

// MARK: - §18.2 Scoped per-list search bar

/// Sticky glass search bar for use at the top of every list view.
/// Wraps SwiftUI's `.searchable` pattern with glass styling + filter chip row.
public struct ScopedSearchBar: View {
    @Binding var query: String
    let placeholder: String

    public var onSearch: ((String) -> Void)?
    public var onClear: (() -> Void)?

    public init(
        query: Binding<String>,
        placeholder: String = "Search…",
        onSearch: ((String) -> Void)? = nil,
        onClear: (() -> Void)? = nil
    ) {
        _query = query
        self.placeholder = placeholder
        self.onSearch = onSearch
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField(placeholder, text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityIdentifier("search.scopedBar")
                .onChange(of: query) { _, new in
                    onSearch?(new)
                }
                .onSubmit {
                    onSearch?(query)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("search.clearButton")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.xs)
    }
}
