import SwiftUI
import DesignSystem

// MARK: - LeadScoreBadge

/// Compact coloured badge displaying a 0–100 lead score.
/// Red < 30  |  Amber 30–60  |  Green > 60.
public struct LeadScoreBadge: View {
    public let score: Int

    public init(score: Int) {
        self.score = max(0, min(100, score))
    }

    private var badgeColor: Color {
        if score < 30 { return .bizarreError }
        if score <= 60 { return .bizarreWarning }
        return .bizarreSuccess
    }

    private var label: String {
        if score < 30 { return "Low" }
        if score <= 60 { return "Med" }
        return "High"
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Text("\(score)")
                .font(.brandTitleSmall())
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(badgeColor, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lead score \(score) of 100, \(label) quality")
    }
}
