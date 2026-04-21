import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

/// Reports home surface. Today it lists the read-only snapshots that are
/// already wired up elsewhere (Dashboard totals, Needs-attention) and
/// cross-links to the domain lists where richer views live. Dedicated
/// report builders (pie charts, date-range pickers, CSV export) arrive in
/// a later phase — we ship a functional index now rather than a stub.
///
/// Staleness note: Reports is a static shortcut index — no dedicated
/// `ReportsRepository` or cached repo exists yet (see §15). A
/// `StalenessIndicator` is shown in the header to signal that the underlying
/// domain data (Dashboard, Inventory, Invoices) may be stale. Each of those
/// domains shows its own freshness chip in their list views.
public struct ReportsView: View {
    /// Injected from parent when available (e.g. DashboardViewModel.lastSyncedAt).
    /// Nil = no connected data source yet; chip shows "Never synced".
    public let referenceSyncedAt: Date?

    public init(referenceSyncedAt: Date? = nil) {
        self.referenceSyncedAt = referenceSyncedAt
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        header
                        shortcutsGrid
                        backlogNotice
                    }
                    .padding(BrandSpacing.base)
                    .frame(maxWidth: 1000, alignment: .leading)
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: referenceSyncedAt)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Read-only snapshots")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text("Quick links to the live numbers already on your dashboard + domain lists. Full report builders with date ranges and CSV export land in a later release.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            // Offline hint — report data requires a live connection to refresh.
            if !Reachability.shared.isOnline {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                    Text("Offline — connect to refresh report data.")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreWarning)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Offline. Connect to refresh report data.")
            }
        }
    }

    private var shortcutsGrid: some View {
        let tiles: [ReportShortcut] = [
            .init(title: "Today's KPIs",        subtitle: "Open tickets, revenue, closes", icon: "chart.bar",        target: "Dashboard"),
            .init(title: "Needs attention",     subtitle: "Stale tickets + overdue invoices", icon: "exclamationmark.circle", target: "Dashboard"),
            .init(title: "Inventory valuation", subtitle: "Unit cost × on-hand quantity", icon: "shippingbox",       target: "Inventory"),
            .init(title: "Low stock",           subtitle: "Below reorder threshold",       icon: "tray.and.arrow.down", target: "Inventory"),
            .init(title: "Open invoices",       subtitle: "Unpaid + partially paid",       icon: "doc.text",          target: "Invoices"),
            .init(title: "Employees",           subtitle: "Active roster + roles",         icon: "person.3",          target: "Employees"),
        ]

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: BrandSpacing.md)],
            spacing: BrandSpacing.md
        ) {
            ForEach(tiles) { tile in
                ReportTile(shortcut: tile)
            }
        }
    }

    private var backlogNotice: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Coming next")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Date-range revenue chart, category pie for expenses, per-tech repair hours, CSV export. See ActionPlan §15 for the full list.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }
}

private struct ReportShortcut: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let target: String
}

private struct ReportTile: View {
    let shortcut: ReportShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: shortcut.icon)
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Spacer()
                Text(shortcut.target.uppercased())
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
            }
            Text(shortcut.title)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(shortcut.subtitle)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shortcut.title). \(shortcut.subtitle). Find it in \(shortcut.target).")
    }
}

#Preview {
    ReportsView()
        .preferredColorScheme(.dark)
}
