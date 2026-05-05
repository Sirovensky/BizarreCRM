#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - MidShiftSnapshot model (§14)

/// A point-in-time snapshot of register activity taken during an active
/// shift. Does not close the session — use the X-report or Z-report for
/// server-side totals.
///
/// All monetary values are in cents.
public struct MidShiftSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let saleCount: Int
    public let grossCents: Int
    public let tipsCents: Int
    public let cashDropsCents: Int  // total cash removed to safe this session
    public let voidsCents: Int
    public let cashExpectedCents: Int
    public let openingFloatCents: Int

    public init(
        capturedAt: Date = Date(),
        saleCount: Int,
        grossCents: Int,
        tipsCents: Int,
        cashDropsCents: Int = 0,
        voidsCents: Int = 0,
        cashExpectedCents: Int,
        openingFloatCents: Int
    ) {
        self.capturedAt        = capturedAt
        self.saleCount         = saleCount
        self.grossCents        = grossCents
        self.tipsCents         = tipsCents
        self.cashDropsCents    = cashDropsCents
        self.voidsCents        = voidsCents
        self.cashExpectedCents = cashExpectedCents
        self.openingFloatCents = openingFloatCents
    }

    // MARK: - Helpers

    /// Estimated cash currently in drawer = opening float + cash sales − cash drops.
    public var estimatedDrawerCents: Int {
        openingFloatCents + cashExpectedCents - cashDropsCents
    }
}

// MARK: - MidShiftSnapshotView (§14)

/// A sheet that shows a real-time mid-shift snapshot of register activity.
/// Tapping "Copy snapshot" puts a plain-text version on the clipboard for
/// managers who need to paste it into a report or message.
///
/// This is distinct from the server-side X-report (`XReportView`) which
/// requires `GET /cash-register/x-report` (POS-XREPORT-001 pending).
/// This view reads purely from the local `CashRegisterStore` and cached
/// cart state supplied by the caller.
@MainActor
public struct MidShiftSnapshotView: View {

    public let snapshot: MidShiftSnapshot
    /// Optional label for the cashier — shown as subtitle if provided.
    public let cashierName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var didCopy: Bool = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    public init(snapshot: MidShiftSnapshot, cashierName: String? = nil) {
        self.snapshot = snapshot
        self.cashierName = cashierName
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    headerCard
                    metricsGrid
                    drawerRow
                }
                .padding(BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Mid-shift snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("midShiftSnapshot.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = plainTextSummary
                        BrandHaptics.success()
                        didCopy = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            didCopy = false
                        }
                    } label: {
                        Label(
                            didCopy ? "Copied" : "Copy snapshot",
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .accessibilityLabel(didCopy ? "Snapshot copied to clipboard" : "Copy mid-shift snapshot to clipboard")
                    .accessibilityIdentifier("midShiftSnapshot.copy")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Snapshot at \(Self.timeFormatter.string(from: snapshot.capturedAt))")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                if let name = cashierName {
                    Text(name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mid-shift snapshot taken at \(Self.timeFormatter.string(from: snapshot.capturedAt))")
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: BrandSpacing.md),
                       GridItem(.flexible(), spacing: BrandSpacing.md)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            snapshotTile(
                label: "Gross sales",
                value: CartMath.formatCents(snapshot.grossCents),
                icon: "dollarsign.circle.fill",
                color: .bizarreSuccess,
                id: "midShiftSnapshot.gross"
            )
            snapshotTile(
                label: "Sales",
                value: "\(snapshot.saleCount)",
                icon: "cart.fill",
                color: .bizarreOrange,
                id: "midShiftSnapshot.saleCount"
            )
            snapshotTile(
                label: "Tips",
                value: CartMath.formatCents(snapshot.tipsCents),
                icon: "heart.fill",
                color: .bizarreTeal,
                id: "midShiftSnapshot.tips"
            )
            snapshotTile(
                label: "Cash drops",
                value: CartMath.formatCents(snapshot.cashDropsCents),
                icon: "arrow.down.circle.fill",
                color: snapshot.cashDropsCents > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted,
                id: "midShiftSnapshot.drops"
            )
            snapshotTile(
                label: "Voids",
                value: CartMath.formatCents(snapshot.voidsCents),
                icon: "xmark.circle.fill",
                color: snapshot.voidsCents > 0 ? .bizarreError : .bizarreOnSurfaceMuted,
                id: "midShiftSnapshot.voids"
            )
            snapshotTile(
                label: "Cash expected",
                value: CartMath.formatCents(snapshot.cashExpectedCents),
                icon: "banknote.fill",
                color: .bizarreOnSurface,
                id: "midShiftSnapshot.cashExpected"
            )
        }
    }

    private func snapshotTile(
        label: String,
        value: String,
        icon: String,
        color: Color,
        id: String
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityIdentifier(id)
    }

    // MARK: - Estimated drawer row

    private var drawerRow: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 22))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Estimated in drawer")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(CartMath.formatCents(snapshot.estimatedDrawerCents))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                Text("Opening float \(CartMath.formatCents(snapshot.openingFloatCents)) + cash sales − drops")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Estimated cash in drawer: \(CartMath.formatCents(snapshot.estimatedDrawerCents)). Based on opening float plus cash sales minus drops."
        )
        .accessibilityIdentifier("midShiftSnapshot.drawerEstimate")
    }

    // MARK: - Plain-text for clipboard

    private var plainTextSummary: String {
        let time = Self.timeFormatter.string(from: snapshot.capturedAt)
        var lines: [String] = ["Mid-Shift Snapshot — \(time)"]
        if let name = cashierName { lines.append("Cashier: \(name)") }
        lines += [
            "─────────────────────",
            "Gross sales:      \(CartMath.formatCents(snapshot.grossCents))",
            "Sales:            \(snapshot.saleCount)",
            "Tips:             \(CartMath.formatCents(snapshot.tipsCents))",
            "Cash drops:       \(CartMath.formatCents(snapshot.cashDropsCents))",
            "Voids:            \(CartMath.formatCents(snapshot.voidsCents))",
            "Cash expected:    \(CartMath.formatCents(snapshot.cashExpectedCents))",
            "Est. in drawer:   \(CartMath.formatCents(snapshot.estimatedDrawerCents))",
        ]
        return lines.joined(separator: "\n")
    }
}

// MARK: - Preview

#Preview("Mid-shift snapshot") {
    MidShiftSnapshotView(
        snapshot: MidShiftSnapshot(
            saleCount: 23,
            grossCents: 145_78,
            tipsCents: 8_50,
            cashDropsCents: 50_00,
            voidsCents: 4_99,
            cashExpectedCents: 42_00,
            openingFloatCents: 100_00
        ),
        cashierName: "Alex M."
    )
    .preferredColorScheme(.dark)
}
#endif
