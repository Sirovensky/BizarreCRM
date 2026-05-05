#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - PosCatalogBundleBadge
//
// Small link-badge icon shown on catalog tiles when a service item has
// required bundle children.  A long-press popover lists the child names.
//
// Spec: docs/pos-redesign-plan.md §4.7
//       docs/pos-implementation-wave.md §Agent F

// MARK: - PosCatalogBundleBadge

/// A badge that appears on a catalog tile when the service has paired parts.
///
/// - Shows a link SF Symbol tinted with the brand primary colour.
/// - Long-press (or hover on iPad) presents a popover listing child names.
/// - Renders nothing when `children` is empty — safe to embed unconditionally.
public struct PosCatalogBundleBadge: View {

    // MARK: - Properties

    /// Names of the required children.  Badge hides itself when empty.
    public let children: [String]

    // MARK: - State

    @State private var showingPreview = false

    // MARK: - Init

    public init(children: [String]) {
        self.children = children
    }

    // MARK: - Body

    public var body: some View {
        if children.isEmpty {
            // Nothing rendered — callers can embed unconditionally.
            EmptyView()
        } else {
            badgeButton
        }
    }

    // MARK: - Private views

    private var badgeButton: some View {
        Button {
            showingPreview.toggle()
        } label: {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.bizarreOrange)
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.bizarreOrange.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bundle: \(children.count) paired \(children.count == 1 ? "part" : "parts")")
        .accessibilityHint("Double-tap to preview paired parts")
        .onLongPressGesture(minimumDuration: 0.4) {
            showingPreview = true
        }
        .hoverEffect(.highlight)
        .popover(isPresented: $showingPreview) {
            childPreviewPopover
        }
    }

    private var childPreviewPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paired parts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Divider()

            ForEach(children, id: \.self) { name in
                Label(name, systemImage: "wrench.and.screwdriver")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(name)
            }
        }
        .padding()
        .frame(minWidth: 220)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Catalog tile modifier

/// Convenience modifier that overlays a `PosCatalogBundleBadge` in the
/// top-trailing corner of a catalog tile.
///
/// Usage:
/// ```swift
/// CatalogTileView(item: item)
///     .catalogBundleBadge(children: item.bundleChildNames)
/// ```
public struct CatalogBundleBadgeModifier: ViewModifier {
    let children: [String]

    public func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            PosCatalogBundleBadge(children: children)
                .padding(6)
        }
    }
}

public extension View {
    /// Overlays a bundle badge in the top-trailing corner.
    /// Renders nothing when `children` is empty.
    func catalogBundleBadge(children: [String]) -> some View {
        modifier(CatalogBundleBadgeModifier(children: children))
    }
}
#endif
