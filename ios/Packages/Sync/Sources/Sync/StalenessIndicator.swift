import SwiftUI
import DesignSystem

// MARK: - StalenessLevel

/// Freshness tier for the staleness indicator chip.
public enum StalenessLevel: Sendable, Equatable {
    case fresh      // < 1 hour
    case warning    // 1–4 hours
    case stale      // > 4 hours
    case never      // nil lastSyncedAt

    public var color: Color {
        switch self {
        case .fresh:   return .bizarreSuccess
        case .warning: return .bizarreWarning
        case .stale:   return .bizarreError
        case .never:   return .bizarreError
        }
    }
}

// MARK: - StalenessLogic (pure, Sendable — no UI dependency)

/// Pure value-type staleness calculations. Fully testable without MainActor isolation.
public struct StalenessLogic: Sendable {
    public let lastSyncedAt: Date?
    public let now: Date

    public init(lastSyncedAt: Date?, now: Date = Date()) {
        self.lastSyncedAt = lastSyncedAt
        self.now = now
    }

    public var label: String {
        guard let date = lastSyncedAt else { return "Never synced" }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int(elapsed / 3_600)
        return "\(hours) hr ago"
    }

    public var stalenessLevel: StalenessLevel {
        guard let date = lastSyncedAt else { return .never }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 3_600   { return .fresh }
        if elapsed < 14_400  { return .warning }
        return .stale
    }

    public var a11yLabel: String {
        guard let date = lastSyncedAt else { return "Data was never synced" }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Data last updated just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "Data last updated \(minutes) minute\(minutes == 1 ? "" : "s") ago" }
        let hours = Int(elapsed / 3_600)
        return "Data last updated \(hours) hour\(hours == 1 ? "" : "s") ago"
    }
}

// MARK: - StalenessIndicator

/// Small chip near list titles showing "Updated <relative time> ago".
///
/// - `lastSyncedAt == nil` → "Never synced" (red)
/// - `< 1 min`            → "Just now"     (green)
/// - `< 1 hour`           → "N min ago"    (green)
/// - `< 4 hours`          → "N hr ago"     (amber)
/// - `>= 4 hours`         → "N hr ago"     (red)
///
/// Liquid Glass on capsule chrome only. Respects Reduce Motion.
public struct StalenessIndicator: View {
    public let lastSyncedAt: Date?

    // Allow external time injection for testing.
    public let now: Date

    public init(lastSyncedAt: Date?, now: Date = Date()) {
        self.lastSyncedAt = lastSyncedAt
        self.now = now
    }

    private var logic: StalenessLogic { StalenessLogic(lastSyncedAt: lastSyncedAt, now: now) }

    // MARK: - Body

    public var body: some View {
        chipContent
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(logic.a11yLabel)
    }

    // §91.9-3: All sync-state pills now use a solid filled capsule so that
    // "Synced / Just now" and "N min ago" carry equal visual weight to the
    // "Never synced" attention chip. On-pill foreground is always black for
    // contrast (same pattern as StatusPill). Glass is kept only when
    // Reduce Transparency is off AND the level is fresh/warning, because
    // those are informational — but the fill still provides clear shape.
    @ViewBuilder
    private var chipContent: some View {
        let level = logic.stalenessLevel
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: iconName(for: level))
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(logic.label)
                .font(.brandLabelSmall())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(pillForeground(for: level))
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(level.color, in: Capsule())
        .transition(chipTransition)
        .animation(chipAnimation, value: logic.label)
    }

    /// Returns contrasting foreground for the solid pill fill.
    private func pillForeground(for level: StalenessLevel) -> Color {
        // Fresh (teal) and warning (amber) have dark fills — use black text.
        // Stale/never (error rose) — also dark fill, use black text.
        // Using `.primary` here would invert in dark mode; hard-code black for
        // consistency with StatusPill treatment.
        return .black
    }

    private func iconName(for level: StalenessLevel) -> String {
        switch level {
        case .fresh:   return "checkmark.circle.fill"
        case .warning: return "clock.fill"
        case .stale:   return "exclamationmark.triangle.fill"
        case .never:   return "exclamationmark.triangle.fill"
        }
    }

    // MARK: - Motion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chipTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9))
    }

    private var chipAnimation: Animation {
        reduceMotion ? .linear(duration: 0) : BrandMotion.snappy
    }
}

// MARK: - Preview

#if DEBUG

private func stalePillStack() -> some View {
    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
        StalenessIndicator(lastSyncedAt: nil)
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-30))
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-600))
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-7_200))
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-20_000))
    }
    .padding(BrandSpacing.base)
}

#Preview("Staleness pills — dark") {
    stalePillStack()
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
}

#Preview("Staleness pills — light") {
    stalePillStack()
        .background(Color(.systemBackground))
        .preferredColorScheme(.light)
}
#endif
