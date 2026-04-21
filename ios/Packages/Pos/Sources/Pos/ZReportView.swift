import Foundation
import Persistence

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §39.2 — end-of-shift Z-Report summary view. PDF + print disabled
/// pending §17.4.
public struct ZReportView: View {
    public let session: CashSessionRecord
    public let aggregates: ZReportAggregates

    @Environment(\.dismiss) private var dismiss
    @State private var showingPrintAlert: Bool = false
    @State private var showingPdfAlert: Bool = false

    public init(session: CashSessionRecord, aggregates: ZReportAggregates = .empty) {
        self.session = session
        self.aggregates = aggregates
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header
                summaryGrid
                varianceCard
                lossPrevTile
                actionRow
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Z-Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .alert("Printing coming soon", isPresented: $showingPrintAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thermal print ships with §17.4 (MFi printer pipeline).")
        }
        .alert("PDF export coming soon", isPresented: $showingPdfAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("PDF archive ships with §17.4 (document renderer).")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Shift summary").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(Self.format(date: session.openedAt, to: session.closedAt))
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("pos.zReport.range")
        }
    }

    private var summaryGrid: some View {
        let columns = [GridItem(.flexible(), spacing: BrandSpacing.md),
                       GridItem(.flexible(), spacing: BrandSpacing.md)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            tile("Sales", aggregates.salesCents).accessibilityIdentifier("pos.zReport.sales")
            tile("Tax", aggregates.taxCents).accessibilityIdentifier("pos.zReport.tax")
            tile("Tips", aggregates.tipsCents).accessibilityIdentifier("pos.zReport.tips")
            tile("Refunds", aggregates.refundCents, isNegative: true).accessibilityIdentifier("pos.zReport.refunds")
            tile("Discounts", aggregates.discountCents, isNegative: true).accessibilityIdentifier("pos.zReport.discounts")
            tile("Opening float", session.openingFloat).accessibilityIdentifier("pos.zReport.opening")
        }
    }

    private var varianceCard: some View {
        let variance = session.varianceCents ?? 0
        let band = CashVariance.band(cents: variance)
        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                Circle().fill(band.color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text("Variance").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(band.shortLabel).font(.brandLabelSmall()).foregroundStyle(band.color)
            }
            Text(CloseRegisterSheet.formatSigned(cents: variance))
                .font(.brandHeadlineLarge())
                .foregroundStyle(band.color)
                .monospacedDigit()
            HStack(spacing: BrandSpacing.lg) {
                labeled("Expected", CartMath.formatCents(session.expectedCash ?? 0))
                labeled("Counted", CartMath.formatCents(session.countedCash ?? 0))
            }
            if let notes = session.notes, !notes.isEmpty {
                Text(notes).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                    .padding(.top, BrandSpacing.xs)
                    .accessibilityIdentifier("pos.zReport.notes")
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
        .accessibilityIdentifier("pos.zReport.variance")
    }

    /// §16.11 — Loss-prevention tile showing void / no-sale / discount counts.
    /// Nil values render "—" rather than "0" to distinguish "no data loaded" from
    /// "nothing happened during this shift".
    @ViewBuilder
    private var lossPrevTile: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Loss prevention")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
                lossPrevStat("Voids",        aggregates.voidCount)
                    .accessibilityIdentifier("pos.zReport.lossPrev.voids")
                lossPrevStat("No sales",     aggregates.noSaleCount)
                    .accessibilityIdentifier("pos.zReport.lossPrev.noSales")
                lossPrevStat("Disc. overrides", aggregates.discountOverrideCount)
                    .accessibilityIdentifier("pos.zReport.lossPrev.discounts")
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
        .accessibilityIdentifier("pos.zReport.lossPrev")
    }

    private func lossPrevStat(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
            Text(value.map(String.init) ?? "—")
                .font(.brandTitleLarge())
                .foregroundStyle(value.map { $0 > 0 ? Color.red : Color.bizarreOnSurface } ?? .bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.bizarreSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var actionRow: some View {
        HStack(spacing: BrandSpacing.md) {
            Button { showingPrintAlert = true } label: {
                Label("Print", systemImage: "printer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).disabled(true)
            .accessibilityIdentifier("pos.zReport.print")
            Button { showingPdfAlert = true } label: {
                Label("PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).disabled(true)
            .accessibilityIdentifier("pos.zReport.pdf")
        }
    }

    private func tile(_ title: String, _ value: Int?, isNegative: Bool = false) -> some View {
        let hasValue = value != nil
        let raw = value ?? 0
        return VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(hasValue ? CartMath.formatCents(isNegative ? -abs(raw) : raw) : "—")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
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

    private static func format(date: Date, to: Date?) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let start = f.string(from: date)
        guard let to else { return start }
        return "\(start) → \(f.string(from: to))"
    }
}

#endif // canImport(UIKit)

// ZReportAggregates is intentionally outside the UIKit guard so it can be
// constructed and tested on macOS (swift test runs on macOS).
public struct ZReportAggregates: Equatable, Sendable {
    public let salesCents: Int?
    public let taxCents: Int?
    public let tipsCents: Int?
    public let refundCents: Int?
    public let discountCents: Int?

    // MARK: §16.11 — Loss-prevention counters

    /// Number of void-line events during the shift. `nil` = not yet loaded.
    public let voidCount: Int?
    /// Number of no-sale (open-drawer) events during the shift. `nil` = not yet loaded.
    public let noSaleCount: Int?
    /// Number of manager-approved discount override events during the shift. `nil` = not yet loaded.
    public let discountOverrideCount: Int?

    public init(
        salesCents: Int? = nil,
        taxCents: Int? = nil,
        tipsCents: Int? = nil,
        refundCents: Int? = nil,
        discountCents: Int? = nil,
        voidCount: Int? = nil,
        noSaleCount: Int? = nil,
        discountOverrideCount: Int? = nil
    ) {
        self.salesCents = salesCents
        self.taxCents = taxCents
        self.tipsCents = tipsCents
        self.refundCents = refundCents
        self.discountCents = discountCents
        self.voidCount = voidCount
        self.noSaleCount = noSaleCount
        self.discountOverrideCount = discountOverrideCount
    }

    public static let empty = ZReportAggregates()

    // MARK: - §16.11 Audit aggregation

    /// Pure function that derives loss-prevention counts from a slice of audit
    /// entries (typically the entries created between shift open and close).
    ///
    /// Designed as a test hook — pass in a pre-filtered `[PosAuditEntry]` and
    /// assert on the returned aggregates without touching the DB.
    ///
    /// Existing financial fields (sales, tax, tips, refunds, discounts) are
    /// preserved from `base` — only the three LP counters are overwritten.
    public static func from(
        auditEntries: [PosAuditEntry],
        base: ZReportAggregates = .empty
    ) -> ZReportAggregates {
        let voids = auditEntries.filter {
            $0.eventType == PosAuditEntry.EventType.voidLine
        }.count
        let noSales = auditEntries.filter {
            $0.eventType == PosAuditEntry.EventType.noSale
        }.count
        let discountOverrides = auditEntries.filter {
            $0.eventType == PosAuditEntry.EventType.discountOverride
        }.count

        return ZReportAggregates(
            salesCents: base.salesCents,
            taxCents: base.taxCents,
            tipsCents: base.tipsCents,
            refundCents: base.refundCents,
            discountCents: base.discountCents,
            voidCount: voids,
            noSaleCount: noSales,
            discountOverrideCount: discountOverrides
        )
    }
}
