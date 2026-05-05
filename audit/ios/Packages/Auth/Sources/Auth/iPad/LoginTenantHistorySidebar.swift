#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - TenantHistoryEntry
//
// Lightweight, UI-only model. The sidebar doesn't own the network
// layer — the app-shell supplies pre-loaded recents from TenantStore.

public struct TenantHistoryEntry: Identifiable, Hashable, Sendable {
    public let id: String
    /// Human-readable shop name.
    public let name: String
    /// Full server URL (shown below the name for self-hosted tenants).
    public let serverURL: URL?
    /// When this tenant was last accessed (drives sort order + relative timestamp).
    public let lastAccessedAt: Date?

    public init(
        id: String,
        name: String,
        serverURL: URL? = nil,
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.lastAccessedAt = lastAccessedAt
    }
}

// MARK: - LoginTenantHistorySidebar
//
// §22 iPad polish — recent-tenant quick-switch sidebar.
//
// Displayed as a narrow leading column in the brand panel when the host
// has recent tenants to show. Tapping a row fires `onSelect` so the
// app-shell can populate the server URL and jump straight to credentials.
//
// Pluggable — rendered only on regular size class and when `entries` is
// non-empty. The sidebar self-hides on compact width (iPhone).

public struct LoginTenantHistorySidebar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let entries: [TenantHistoryEntry]
    private let onSelect: (TenantHistoryEntry) -> Void

    public init(
        entries: [TenantHistoryEntry],
        onSelect: @escaping (TenantHistoryEntry) -> Void
    ) {
        self.entries = entries
        self.onSelect = onSelect
    }

    public var body: some View {
        if horizontalSizeClass == .regular, !entries.isEmpty {
            sidebarContent
        }
    }

    // MARK: - Sidebar body

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(Color.bizarreOutline.opacity(0.25))
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedEntries) { entry in
                        tenantRow(entry)
                    }
                }
            }
        }
        .frame(width: LoginTenantHistorySidebar.sidebarWidth)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .strokeBorder(Color.bizarreOutline.opacity(0.30), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent tenants")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "building.2")
                .foregroundStyle(Color.bizarreOrange)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Recent")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
    }

    // MARK: - Row

    private func tenantRow(_ entry: TenantHistoryEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            rowLabel(entry)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(rowAccessibilityLabel(entry))
        .accessibilityHint("Double-tap to sign in to this tenant")
    }

    private func rowLabel(_ entry: TenantHistoryEntry) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            tenantInitialBadge(entry)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.name)
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .lineLimit(1)
                if let url = entry.serverURL {
                    Text(url.host ?? url.absoluteString)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                if let date = entry.lastAccessedAt {
                    Text(date, style: .relative)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
    }

    private func tenantInitialBadge(_ entry: TenantHistoryEntry) -> some View {
        let initial = entry.name.first.map(String.init) ?? "?"
        return Text(initial)
            .font(.brandTitleSmall())
            .foregroundStyle(Color.bizarreOnOrange)
            .frame(width: 32, height: 32)
            .background(Color.bizarreOrange.opacity(0.85), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .accessibilityHidden(true)
    }

    private func rowAccessibilityLabel(_ entry: TenantHistoryEntry) -> String {
        var parts = [entry.name]
        if let url = entry.serverURL {
            parts.append(url.host ?? url.absoluteString)
        }
        if let date = entry.lastAccessedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Last used \(formatter.localizedString(for: date, relativeTo: Date()))")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private var sortedEntries: [TenantHistoryEntry] {
        entries.sorted {
            ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast)
        }
    }

    static let sidebarWidth: CGFloat = 220
}

// MARK: - Preview

#if DEBUG
#Preview("Tenant history sidebar") {
    let entries: [TenantHistoryEntry] = [
        TenantHistoryEntry(
            id: "1",
            name: "Main Street Repair",
            serverURL: URL(string: "https://mainstreet.bizarrecrm.com"),
            lastAccessedAt: Date().addingTimeInterval(-600)
        ),
        TenantHistoryEntry(
            id: "2",
            name: "Downtown Motors",
            serverURL: nil,
            lastAccessedAt: Date().addingTimeInterval(-3600 * 24)
        ),
        TenantHistoryEntry(
            id: "3",
            name: "West Side Auto",
            serverURL: URL(string: "https://192.168.0.240"),
            lastAccessedAt: Date().addingTimeInterval(-3600 * 24 * 7)
        )
    ]
    return ZStack {
        Color.bizarreSurfaceBase.ignoresSafeArea()
        LoginTenantHistorySidebar(entries: entries) { _ in }
            .padding()
    }
    .environment(\.horizontalSizeClass, .regular)
    .preferredColorScheme(.dark)
}
#endif

#endif
