import SwiftUI

// §22 (line 3702) — Overflow: when a sidebar / row label has less than ~100 pt
// of horizontal room, drop the title and keep only the icon. Sidebar already
// has a manual icon-rail toggle (⌘\); this modifier handles *automatic*
// collapse driven by container width.
//
// Usage:
//   Label("Tickets", systemImage: "wrench.and.screwdriver")
//       .adaptiveIconOnly(threshold: 100)
//
// Threshold is the parent container width below which the title hides.
//
// Implementation: `GeometryReader` reads available width and toggles a label
// style. We don't strip the title from the accessibility tree — VoiceOver still
// announces "Tickets" even when only the icon is visible.

public struct AdaptiveLabelModifier: ViewModifier {
    private let threshold: CGFloat

    public init(threshold: CGFloat = 100) {
        self.threshold = threshold
    }

    public func body(content: Content) -> some View {
        GeometryReader { proxy in
            // SwiftUI requires both branches of a ternary to share a concrete
            // type, but `.iconOnlyAdaptive` and `.titleAndIconAdaptive` differ.
            // Use a parameterised wrapper style instead.
            content
                .labelStyle(AdaptiveLabelStyle(iconOnly: proxy.size.width < threshold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public extension View {
    /// Switch a `Label` to icon-only when the container drops below `threshold`
    /// points wide. Title remains in the accessibility tree.
    func adaptiveIconOnly(threshold: CGFloat = 100) -> some View {
        modifier(AdaptiveLabelModifier(threshold: threshold))
    }
}

// MARK: - LabelStyle

/// Adaptive label style. Switches between icon-only and title+icon based on
/// the `iconOnly` flag. When icon-only, the title is preserved in the
/// accessibility tree via `.accessibilityRepresentation`.
public struct AdaptiveLabelStyle: LabelStyle {
    private let iconOnly: Bool

    public init(iconOnly: Bool) {
        self.iconOnly = iconOnly
    }

    public func makeBody(configuration: Configuration) -> some View {
        Group {
            if iconOnly {
                configuration.icon
                    .accessibilityRepresentation {
                        Label(
                            title: { configuration.title },
                            icon: { configuration.icon }
                        )
                    }
            } else {
                HStack(spacing: 8) {
                    configuration.icon
                    configuration.title
                }
            }
        }
    }
}

public extension LabelStyle where Self == AdaptiveLabelStyle {
    /// Icon-only when the surrounding container is narrow. VoiceOver still
    /// reads the title.
    static func adaptiveIconOnly(_ iconOnly: Bool) -> AdaptiveLabelStyle {
        AdaptiveLabelStyle(iconOnly: iconOnly)
    }
}
