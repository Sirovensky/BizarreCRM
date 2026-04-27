#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - §79 Recent servers chip row

/// A horizontally scrolling row of chips for recently-used server URLs.
/// Shown on the login screen server-picker step below the URL field.
///
/// Tapping a chip sets the URL and fires `onSelect`. If there are no
/// recent servers the view collapses to zero height.
///
/// ```swift
/// RecentServersChipRow { server in
///     flow.shopSlug = ""
///     flow.serverUrlRaw = server.url.absoluteString
///     flow.useSelfHosted = true
/// }
/// ```
public struct RecentServersChipRow: View {

    @State private var servers: [RecentServer] = []
    private let onSelect: (RecentServer) -> Void

    public init(onSelect: @escaping (RecentServer) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            if !servers.isEmpty {
                scrollRow
            }
        }
        .task {
            servers = await RecentServersStore.shared.all
        }
    }

    // MARK: - Scroll row

    private var scrollRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Recent")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.xxs)
                .accessibilityHidden(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(servers) { server in
                        chip(for: server)
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
                .padding(.vertical, BrandSpacing.xxs)
            }
        }
        .accessibilityLabel("Recently used servers")
        .accessibilityHint("Swipe horizontally to see all. Tap to select.")
    }

    // MARK: - Chip

    private func chip(for server: RecentServer) -> some View {
        Button {
            onSelect(server)
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                Text(server.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .lineLimit(1)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .brandGlass(.regular, in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select server \(server.displayName)")
        .accessibilityHint("Tap to fill server URL")
    }
}

#endif
