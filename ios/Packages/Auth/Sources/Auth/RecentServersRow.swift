#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - RecentServersRow
//
// §79.1 — Horizontal chip row shown above the server-URL / shop-slug field.
// Tapping a chip pre-fills the server URL and triggers navigation forward.
//
// Rendered only when there are ≥1 recent servers. Hides itself on first launch.

public struct RecentServersRow: View {
    let servers: [RecentServer]
    let onSelect: (RecentServer) -> Void

    public init(servers: [RecentServer], onSelect: @escaping (RecentServer) -> Void) {
        self.servers = servers
        self.onSelect = onSelect
    }

    public var body: some View {
        if !servers.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Recent shops")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.xs) {
                        ForEach(servers) { server in
                            RecentServerChip(server: server) {
                                onSelect(server)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .accessibilityLabel("Recently used shops. \(servers.count) available.")
        }
    }
}

// MARK: - Single chip

private struct RecentServerChip: View {
    let server: RecentServer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "storefront")
                    .imageScale(.small)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(server.chipLabel)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .frame(minHeight: 36)
        }
        .brandGlass(.regular, in: Capsule(), interactive: true)
        .accessibilityLabel("Open \(server.chipLabel)")
        .accessibilityHint("Switches to this shop")
    }
}

#endif
