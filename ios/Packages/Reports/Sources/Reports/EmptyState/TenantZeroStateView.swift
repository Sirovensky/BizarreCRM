import SwiftUI
import DesignSystem

// MARK: - TenantZeroStateView  (§91.16 item 1)
//
// Shown instead of the full reports surface when the tenant has fewer than
// `ReportsViewModel.tenantZeroTransactionThreshold` completed transactions
// in the selected period.
//
// This panel does NOT render any charts or cards — it replaces the entire
// card grid so new operators are never confronted with all-empty skeleton grids.

public struct TenantZeroStateView: View {

    /// Callback invoked when the user taps "Go to POS".
    public let onGoToPOS: (() -> Void)?

    public init(onGoToPOS: (() -> Void)? = nil) {
        self.onGoToPOS = onGoToPOS
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            illustrationArea
            copyArea
            actionArea
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: 440)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "No sales yet. Run your first sale to unlock these reports."
        )
    }

    // MARK: - Illustration

    private var illustrationArea: some View {
        ZStack {
            Circle()
                .fill(Color.bizarreOrange.opacity(0.08))
                .frame(width: 120, height: 120)
            Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.bizarreOrange)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Copy

    private var copyArea: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Run your first sale to unlock these reports")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)

            Text("Once you record a transaction, your revenue charts, ticket stats, and performance dashboards will appear here automatically.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: BrandSpacing.md) {
            if let onGoToPOS {
                Button(action: onGoToPOS) {
                    Label("Go to Point of Sale", systemImage: "creditcard")
                        .font(.brandLabelLarge())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Go to Point of Sale to record a sale")
            }

            Text("Reports update within a few minutes of each completed sale.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }
}
