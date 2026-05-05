import SwiftUI
import DesignSystem

// MARK: - PriorityBadge

/// Pill-shaped badge displaying notification priority.
/// Uses Liquid Glass for critical/timeSensitive; plain tinted capsule for normal/low.
/// Full A11y: announces level via `.accessibilityLabel`.
public struct PriorityBadge: View {

    let priority: NotificationPriority
    let compact: Bool

    public init(_ priority: NotificationPriority, compact: Bool = false) {
        self.priority = priority
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: priority.iconName)
                .imageScale(compact ? .small : .medium)
                .accessibilityHidden(true)
            if !compact {
                Text(priority.displayName)
                    .font(.brandLabelSmall())
            }
        }
        .foregroundStyle(priority.color)
        .padding(.horizontal, compact ? BrandSpacing.xs : BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(priority.color.opacity(0.15), in: Capsule())
        .overlay(
            Capsule()
                .stroke(priority.color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(priority.accessibilityLabel)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: BrandSpacing.md) {
        ForEach(NotificationPriority.allCases, id: \.rawValue) { p in
            HStack {
                PriorityBadge(p)
                PriorityBadge(p, compact: true)
            }
        }
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
}
#endif
