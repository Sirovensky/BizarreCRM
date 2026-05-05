#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.15 — End-of-shift report ("Z-report extended"). Displays the
/// canonical `ShiftSummary`. Print / PDF deferred to Phase 5A PrintEngine.
public struct ShiftSummaryView: View {
    public let summary: ShiftSummary

    @Environment(\.dismiss) private var dismiss
    @State private var showPrintAlert = false

    public init(summary: ShiftSummary) {
        self.summary = summary
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header
                metricsGrid
                tendersSection
                varianceCard
                actionRow
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Shift Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("shiftSummary.done")
            }
        }
        .alert("Print coming soon", isPresented: $showPrintAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thermal print ships with §17.4 (MFi printer pipeline).")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("End-of-Shift Report")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(dateRange)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("shiftSummary.dateRange")
        }
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: BrandSpacing.md),
                    GridItem(.flexible(), spacing: BrandSpacing.md)]
        return LazyVGrid(columns: cols, spacing: BrandSpacing.md) {
            tile("Sales", summary.totalRevenueCents)
                .accessibilityIdentifier("shiftSummary.revenue")
            tile("Sale count", summary.saleCount, isCurrency: false)
                .accessibilityIdentifier("shiftSummary.saleCount")
            tile("Avg. ticket", summary.averageTicketCents)
                .accessibilityIdentifier("shiftSummary.avgTicket")
            tile("Refunds", summary.refundsCents, isNegative: true)
                .accessibilityIdentifier("shiftSummary.refunds")
            tile("Voids", summary.voidsCents, isNegative: true)
                .accessibilityIdentifier("shiftSummary.voids")
            tile("Opening float", summary.openingCashCents)
                .accessibilityIdentifier("shiftSummary.openingFloat")
        }
    }

    // MARK: - Tenders breakdown

    @ViewBuilder
    private var tendersSection: some View {
        if !summary.tendersBreakdown.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Tender Breakdown")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)
                ForEach(summary.tendersBreakdown.sorted(by: { $0.key < $1.key }), id: \.key) { key, cents in
                    HStack {
                        Text(key)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(CartMath.formatCents(cents))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    .padding(.vertical, BrandSpacing.xxs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(key): \(CartMath.formatCents(cents))")
                }
            }
            .padding(BrandSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(Color.bizarreSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
            .accessibilityIdentifier("shiftSummary.tenders")
        }
    }

    // MARK: - Variance card

    private var varianceCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Cash Variance")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
            let driftColor: Color = summary.driftCents == 0 ? .bizarreOrange
                                 : summary.driftCents > 0  ? .green
                                 : .red
            Text(signedCents(summary.driftCents))
                .font(.brandHeadlineLarge())
                .foregroundStyle(driftColor)
                .monospacedDigit()
                .accessibilityIdentifier("shiftSummary.drift")
            HStack(spacing: BrandSpacing.lg) {
                labeled("Expected", CartMath.formatCents(summary.calculatedCashCents))
                labeled("Counted",  CartMath.formatCents(summary.closingCashCents))
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.bizarreSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityIdentifier("shiftSummary.variance")
    }

    // MARK: - Action row

    private var actionRow: some View {
        Button {
            showPrintAlert = true
        } label: {
            Label("Print Z-Report", systemImage: "printer")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(true)
        .accessibilityIdentifier("shiftSummary.print")
    }

    // MARK: - Helpers

    private func tile(_ title: String, _ value: Int, isCurrency: Bool = true, isNegative: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if isCurrency {
                Text(CartMath.formatCents(isNegative ? -abs(value) : value))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            } else {
                Text("\(value)")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.bizarreSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
        }
    }

    private func signedCents(_ cents: Int) -> String {
        let formatted = CartMath.formatCents(abs(cents))
        return cents >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private var dateRange: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let start = f.string(from: summary.startedAt)
        guard let end = summary.endedAt else { return start }
        return "\(start) → \(f.string(from: end))"
    }
}
#endif
