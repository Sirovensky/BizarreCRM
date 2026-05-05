import SwiftUI
import DesignSystem

/// §22.3 — Right-column inline preview pane for the iPad 3-column search layout.
///
/// Displays entity-specific detail for a selected `SearchHit` or `SearchResultMerger.MergedRow`.
/// When nothing is selected it shows a branded empty state.
///
/// The pane is deliberately kept stateless (all data comes in via `selectedItem`).
/// Deep-navigation (tapping "Open") is delegated to the `onOpen` closure so that
/// the host app controls routing without coupling the Search package to any
/// domain-specific NavigationPath.
public struct SearchResultPreviewPane: View {

    // MARK: - Inputs

    /// The item currently previewed. Nil = empty state.
    public var selectedItem: SearchPreviewItem?

    /// Called when the user wants to open the full detail view.
    public var onOpen: ((SearchPreviewItem) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    public init(
        selectedItem: SearchPreviewItem? = nil,
        onOpen: ((SearchPreviewItem) -> Void)? = nil
    ) {
        self.selectedItem = selectedItem
        self.onOpen = onOpen
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            if let item = selectedItem {
                itemPreview(item)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity
                              )
                    )
                    .id(item.id)  // force transition on item change
            } else {
                emptyState
            }
        }
        .animation(reduceMotion ? .none : BrandMotion.sheet, value: selectedItem?.id)
    }

    // MARK: - Item preview

    private func itemPreview(_ item: SearchPreviewItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                previewHeader(item)
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.top, BrandSpacing.lg)

                Divider()
                    .padding(.horizontal, BrandSpacing.base)

                previewBody(item)
                    .padding(.horizontal, BrandSpacing.lg)

                openButton(item)
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.bottom, BrandSpacing.xxl)
            }
        }
    }

    // MARK: - Preview header

    private func previewHeader(_ item: SearchPreviewItem) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.base) {
            entityIconView(item.entity)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(item.title)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)

                entityBadge(item.entity)
            }

            Spacer()
        }
    }

    // MARK: - Preview body

    @ViewBuilder
    private func previewBody(_ item: SearchPreviewItem) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            if let snippet = item.snippet, !snippet.isEmpty {
                previewSection(title: "Excerpt") {
                    Text(TermHighlighter.attributed(snippet: snippet))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }
            }

            previewSection(title: "Entity ID") {
                Text(item.entityId)
                    .font(.brandMono())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                previewSection(title: "Detail") {
                    Text(subtitle)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Section block

    private func previewSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            content()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Open button

    private func openButton(_ item: SearchPreviewItem) -> some View {
        Button {
            onOpen?(item)
        } label: {
            Label("Open \(item.entity.capitalized)", systemImage: "arrow.up.right.square")
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .brandGlass(.identity, in: RoundedRectangle(cornerRadius: 10), tint: .bizarreOrange, interactive: true)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel("Open \(item.title) in \(item.entity)")
    }

    // MARK: - Entity icon

    private func entityIconView(_ entity: String) -> some View {
        let imageName: String
        switch entity {
        case "customers":    imageName = "person.fill"
        case "tickets":      imageName = "wrench.and.screwdriver.fill"
        case "inventory":    imageName = "shippingbox.fill"
        case "invoices":     imageName = "doc.text.fill"
        case "estimates":    imageName = "doc.badge.plus"
        case "appointments": imageName = "calendar"
        case "notes":        imageName = "note.text"
        default:             imageName = "doc.fill"
        }
        return Image(systemName: imageName)
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(.bizarreOrange)
            .frame(width: 52, height: 52)
            .background(Color.bizarreOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    // MARK: - Entity badge

    private func entityBadge(_ entity: String) -> some View {
        Text(entity.capitalized)
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Color.bizarreOrange, in: Capsule())
            .accessibilityHidden(true)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.xs) {
                Text("Select a result")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)

                Text("Tap a search result to preview it here.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No result selected. Tap a search result to preview.")
    }
}

// MARK: - SearchPreviewItem

/// Value type that carries the data needed to render the preview pane.
/// Constructed from either a `SearchHit` (local FTS) or a
/// `SearchResultMerger.MergedRow` (merged local + remote).
public struct SearchPreviewItem: Identifiable, Hashable, Sendable {
    public let id: String        // "\(entity):\(entityId)"
    public let entity: String
    public let entityId: String
    public let title: String
    public let snippet: String?
    public let subtitle: String?

    public init(
        entity: String,
        entityId: String,
        title: String,
        snippet: String? = nil,
        subtitle: String? = nil
    ) {
        self.id = "\(entity):\(entityId)"
        self.entity = entity
        self.entityId = entityId
        self.title = title
        self.snippet = snippet
        self.subtitle = subtitle
    }

    // MARK: - Factories

    public static func from(hit: SearchHit) -> SearchPreviewItem {
        SearchPreviewItem(
            entity: hit.entity,
            entityId: hit.entityId,
            title: hit.title,
            snippet: hit.snippet.isEmpty ? nil : hit.snippet
        )
    }

    public static func from(row: SearchResultMerger.MergedRow) -> SearchPreviewItem {
        SearchPreviewItem(
            entity: row.entity,
            entityId: row.entityId,
            title: row.title,
            snippet: row.snippet,
            subtitle: row.subtitle
        )
    }
}
