import SwiftUI
import DesignSystem
import Core

// MARK: - §18.1 Search trigger — glass magnifier chip in toolbar (all screens) + ⌘F.
//
// `SearchTriggerChip` is the always-visible glass pill that shows in every screen's
// navigation bar. Tapping it pushes / presents the GlobalSearchView.
//
// Usage (from any list screen):
// ```swift
// .toolbar {
//     ToolbarItem(placement: .navigationBarTrailing) {
//         SearchTriggerChip(onTap: { isSearchPresented = true })
//     }
// }
// .sheet(isPresented: $isSearchPresented) {
//     GlobalSearchView(api: api, ftsStore: ftsStore)
// }
// ```
//
// On iPad / Mac the chip also registers ⌘F as a keyboard shortcut.

// MARK: - SearchTriggerChip

public struct SearchTriggerChip: View {

    public var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.bizarreOnSurface)

                Text("Search")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.bizarreOnSurface.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        #if canImport(UIKit)
        .keyboardShortcut("f", modifiers: .command)
        #endif
        .accessibilityLabel("Search")
        .accessibilityHint("Opens global search across all your data")
        .accessibilityIdentifier("toolbar.searchChip")
    }
}

// MARK: - SearchTriggerModifier

/// Adds a search chip to the navigation bar + a pull-down gesture on the content.
///
/// Usage:
/// ```swift
/// ContentView()
///     .globalSearchTrigger { isSearchPresented = true }
/// ```
public struct GlobalSearchTriggerModifier: ViewModifier {

    public var onTrigger: () -> Void

    public func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SearchTriggerChip(onTap: onTrigger)
                }
            }
    }
}

public extension View {
    /// Add a glass search chip to the navigation bar and a ⌘F shortcut.
    func globalSearchTrigger(onTrigger: @escaping () -> Void) -> some View {
        modifier(GlobalSearchTriggerModifier(onTrigger: onTrigger))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Search Chip") {
    NavigationStack {
        List { Text("Sample row") }
            .navigationTitle("Tickets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SearchTriggerChip { print("search tapped") }
                }
            }
    }
}
#endif
