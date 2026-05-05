import SwiftUI
import Core
import DesignSystem

// MARK: - §60.6 LocationMetricsCard

/// Per-location revenue and ticket-count summary card.
///
/// NOTE — Coming soon: The server does not yet expose a per-location stats
/// endpoint (SCAN-462 scope: "location registry + user assignment only,
/// no scoping of tickets/invoices by location_id — separate follow-up epic").
/// This component renders a "Coming soon" placeholder so the surrounding
/// location-detail screen remains layout-complete.  Wiring will be trivial
/// once the server ships `GET /api/v1/locations/:id/stats`.
///
/// iPad: displayed as a horizontal HStack of metric tiles.
/// iPhone: displayed as a VStack of metric rows.

public struct LocationMetricsCard: View {
    let location: Location

    public init(location: Location) {
        self.location = location
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Metrics for \(location.name)")
    }

    // MARK: iPhone

    private var iPhoneLayout: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            sectionHeader
            comingSoonBanner
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: iPad

    private var iPadLayout: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader
            HStack(spacing: DesignTokens.Spacing.md) {
                metricPlaceholderTile(
                    icon: "dollarsign.circle",
                    label: "Revenue (MTD)",
                    color: .bizarreTeal
                )
                metricPlaceholderTile(
                    icon: "ticket",
                    label: "Open Tickets",
                    color: .bizarreOrange
                )
                metricPlaceholderTile(
                    icon: "checkmark.circle",
                    label: "Closed (MTD)",
                    color: Color.green
                )
                metricPlaceholderTile(
                    icon: "person.2",
                    label: "Staff Assigned",
                    color: Color.purple
                )
            }
            comingSoonBanner
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: Shared sub-views

    private var sectionHeader: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            Text("Location Metrics")
                .font(.headline)
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
    }

    private var comingSoonBanner: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "clock.badge")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Coming soon")
                    .font(.subheadline.bold())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Per-location revenue and ticket counts will be available once the server exposes location-scoped stats.")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Metrics coming soon. Per-location stats are not yet available.")
    }

    @ViewBuilder
    private func metricPlaceholderTile(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text("—")
                .font(.title.bold())
                .foregroundStyle(.bizarreOnSurface)
            Text(label)
                .font(.caption)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): not yet available")
    }
}

// MARK: - LocationMetricsSection
// Convenience wrapper embedding the card inside a detail view Section.

public struct LocationMetricsSection: View {
    let location: Location

    public init(location: Location) {
        self.location = location
    }

    public var body: some View {
        LocationMetricsCard(location: location)
            .listRowInsets(EdgeInsets(
                top: DesignTokens.Spacing.xs,
                leading: DesignTokens.Spacing.md,
                bottom: DesignTokens.Spacing.xs,
                trailing: DesignTokens.Spacing.md
            ))
            .listRowBackground(Color.clear)
    }
}
