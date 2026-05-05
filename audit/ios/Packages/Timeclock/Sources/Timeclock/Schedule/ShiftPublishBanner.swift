import SwiftUI
import DesignSystem

/// Sticky banner shown after a schedule is published.
///
/// Employees will receive a push notification (server-triggered).
/// This banner confirms the publish action in the manager UI.
///
/// Liquid Glass per visual language — shown as a floating inset footer.
public struct ShiftPublishBanner: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule Published")
                    .font(.subheadline.weight(.semibold))
                Text("Team members will be notified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schedule published. Team members will be notified.")
    }
}
