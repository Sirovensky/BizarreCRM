import SwiftUI
import DesignSystem
import Core

// MARK: - DashboardNewTenantEmptyState
//
// §3.1 / §3.14 — Empty state shown on the dashboard for brand-new tenants
// whose shop has never had any tickets, revenue, or appointments.
//
// Shown inside the dashboard's `LoadedBody` when:
//   • openTickets == 0
//   • closedToday == 0
//   • revenueToday == 0
//   • appointmentsToday == 0
//   • kpis is nil (no financial data yet)
//
// Two CTAs match the web dashboard empty state:
//   1. "Create your first ticket" → onCreateTicket
//   2. "Import data"             → onImportData
//
// Both callbacks are optional; if nil the corresponding button is hidden.
// Calling sites in App/ wire these to the appropriate navigation routes.
//
// Design:
//   - Wrench + sparkle SF Symbol (no custom assets needed).
//   - Plain surface — no glass on content (CLAUDE.md §glass-rules).
//   - Centered, padded card with surface1 background.

/// Full-panel new-tenant empty state for the Dashboard.
public struct DashboardNewTenantEmptyState: View {

    /// Fired when the user taps "Create your first ticket".
    public var onCreateTicket: (() -> Void)?

    /// Fired when the user taps "Import data".
    public var onImportData: (() -> Void)?

    public init(
        onCreateTicket: (() -> Void)? = nil,
        onImportData: (() -> Void)? = nil
    ) {
        self.onCreateTicket = onCreateTicket
        self.onImportData = onImportData
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            // Illustration — wrench + sparkle composition
            ZStack {
                Circle()
                    .fill(Color.bizarreSurface2)
                    .frame(width: 96, height: 96)
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(.bizarreOrange)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.bizarreOrange.opacity(0.7))
                    .offset(x: 26, y: -26)
            }
            .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.xs) {
                Text("Your shop is all set up!")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text("Create your first ticket to get started, or import your existing data.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: BrandSpacing.sm) {
                if let onCreateTicket {
                    Button(action: onCreateTicket) {
                        Label("Create your first ticket", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Create your first ticket")
                }

                if let onImportData {
                    Button(action: onImportData) {
                        Label("Import data", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Import data from another system")
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - New-tenant detection helper

/// Returns `true` when the snapshot represents a brand-new tenant with no data.
///
/// Callers use this to decide whether to show `DashboardNewTenantEmptyState`
/// instead of (or above) the KPI grid.
public func isNewTenantSnapshot(_ snapshot: DashboardSnapshot) -> Bool {
    let s = snapshot.summary
    return s.openTickets == 0
        && s.closedToday == 0
        && s.revenueToday == 0
        && s.appointmentsToday == 0
        && snapshot.kpis == nil
}
