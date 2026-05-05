import SwiftUI
import DesignSystem

// MARK: - §3.1 Previous-period compare delta badge
//
// Shows green ▲ / red ▼ delta badge per KPI tile, driven by
// server diff field or client subtraction from cached prior value.
//
// Usage:
//   DashboardDeltaBadge(delta: 12.5)   // +12.5% ▲ green
//   DashboardDeltaBadge(delta: -3.2)   // -3.2% ▼ red
//   DashboardDeltaBadge(delta: nil)    // hidden

/// Direction and color semantics for a period-over-period change.
public enum DeltaDirection: Sendable {
    case up
    case down
    case flat

    public var systemImageName: String {
        switch self {
        case .up:   return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "minus"
        }
    }

    public var color: Color {
        switch self {
        case .up:   return .bizarreSuccess
        case .down: return .bizarreError
        case .flat: return .bizarreOnSurfaceMuted
        }
    }

    public static func from(_ delta: Double) -> DeltaDirection {
        if delta > 0.01  { return .up }
        if delta < -0.01 { return .down }
        return .flat
    }
}

/// Compact green/red delta chip for a KPI tile.
/// Pass `nil` to hide the badge entirely (e.g. when comparison data unavailable).
public struct DashboardDeltaBadge: View {
    public let delta: Double?

    public init(delta: Double?) {
        self.delta = delta
    }

    public var body: some View {
        if let delta {
            let direction = DeltaDirection.from(delta)
            HStack(spacing: 2) {
                Image(systemName: direction.systemImageName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(direction.color)
                    .accessibilityHidden(true)
                Text(String(format: "%.1f%%", abs(delta)))
                    .font(.brandLabelSmall())
                    .foregroundStyle(direction.color)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(direction.color.opacity(0.12), in: Capsule())
            .accessibilityLabel(accessibilityText(delta: delta, direction: direction))
        }
    }

    private func accessibilityText(delta: Double, direction: DeltaDirection) -> String {
        let abs = abs(delta)
        switch direction {
        case .up:   return String(format: "Up %.1f percent vs prior period", abs)
        case .down: return String(format: "Down %.1f percent vs prior period", abs)
        case .flat: return "Unchanged vs prior period"
        }
    }
}

// MARK: - KPI tile with delta support

/// Extended KPI tile that shows a delta badge below the value.
/// Backward-compatible with `KpiTileItem` — delta is optional.
public struct KpiTileItemWithDelta: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let value: String
    public let icon: String
    /// Percentage change vs prior period (e.g. 12.5 = +12.5%). Nil = no badge.
    public let delta: Double?

    public init(label: String, value: String, icon: String, delta: Double? = nil) {
        self.label = label
        self.value = value
        self.icon = icon
        self.delta = delta
    }
}

/// KPI tile view with optional previous-period delta badge.
public struct StatTileCardWithDelta: View {
    public let tile: KpiTileItemWithDelta
    public var onTap: (@MainActor () -> Void)?

    public init(tile: KpiTileItemWithDelta, onTap: (@MainActor () -> Void)? = nil) {
        self.tile = tile
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            Task { @MainActor in onTap?() }
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Image(systemName: tile.icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Text(tile.value)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)

            Text(tile.label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)

            if let delta = tile.delta {
                DashboardDeltaBadge(delta: delta)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .brandHover()
    }

    private var accessibilityValue: String {
        if let delta = tile.delta {
            let dir = DeltaDirection.from(delta)
            switch dir {
            case .up:   return "\(tile.value), up \(String(format: "%.1f", abs(delta))) percent"
            case .down: return "\(tile.value), down \(String(format: "%.1f", abs(delta))) percent"
            case .flat: return "\(tile.value), unchanged"
            }
        }
        return tile.value
    }
}
