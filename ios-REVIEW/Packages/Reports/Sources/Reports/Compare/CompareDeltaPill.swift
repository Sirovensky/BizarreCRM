import SwiftUI
import DesignSystem

// MARK: - CompareDeltaPill
//
// Compact up/down-arrow pill showing a period-over-period % change.
// Uses Liquid Glass chrome (brandGlass) on iOS 26, falls back to
// tinted capsule on earlier OS versions — consistent with the rest of
// the DesignSystem glass vocabulary.
//
// Usage:
//   CompareDeltaPill(pct: 12.3)      // +12.3 % ▲ green
//   CompareDeltaPill(pct: -4.5)      // -4.5 %  ▼ red
//   CompareDeltaPill(pct: nil)        // "—" neutral (no prior data)
//
// Size: compact — designed to sit inline with a chart card header or
// alongside a KPI value.  Never use in a stacked glass group without
// wrapping in BrandGlassContainer.

public struct CompareDeltaPill: View {
    /// Percentage change value. `nil` means no prior data available.
    public let pct: Double?
    /// Optional explicit label override (e.g. "WoW", "MoM", "YoY").
    public let periodLabel: String?

    public init(pct: Double?, periodLabel: String? = nil) {
        self.pct = pct
        self.periodLabel = periodLabel
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            if let periodLabel {
                Text(periodLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            arrowImage
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(formattedPct)
                .font(.brandLabelLarge())
                .monospacedDigit()
        }
        .foregroundStyle(pillColor)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .brandGlass(.regular, in: Capsule(), tint: pillColor.opacity(0.5))
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Private helpers

    // §91.2-1: 0.0 % is flat — show dash glyph instead of up-arrow + green.
    private var isFlat: Bool {
        guard let pct else { return false }
        return pct == 0.0
    }

    private var arrowImage: Image {
        guard let pct, !isFlat else {
            return Image(systemName: "minus")
        }
        if pct > 0 { return Image(systemName: "arrow.up.right") }
        return Image(systemName: "arrow.down.right")
    }

    private var formattedPct: String {
        guard let pct else { return "—" }
        // Zero change: show just a dash, not "+0.0%"
        if isFlat { return "–" }
        let abs = Swift.abs(pct)
        let sign = pct > 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs))%"
    }

    private var pillColor: Color {
        guard let pct else { return .bizarreOnSurfaceMuted }
        if pct > 0 { return .bizarreSuccess }
        if pct < 0 { return .bizarreError }
        // Flat (0.0): neutral
        return .bizarreOnSurfaceMuted
    }

    private var accessibilityDescription: String {
        guard let pct else {
            return periodLabel.map { "\($0): no comparison data" } ?? "No comparison data"
        }
        let direction: String
        if isFlat        { direction = "unchanged" }
        else if pct > 0  { direction = "up" }
        else             { direction = "down" }
        let absStr = String(format: "%.1f", Swift.abs(pct))
        let base = "\(direction) \(absStr) percent vs prior period"
        return periodLabel.map { "\($0): \(base)" } ?? base
    }
}
