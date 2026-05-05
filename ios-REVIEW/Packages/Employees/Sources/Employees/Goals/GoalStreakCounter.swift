import SwiftUI
import DesignSystem

// MARK: - GoalStreakCounter

/// Subtle streak display. Playful, not manipulative (§46.8 guardrails).
/// No loss-aversion copy — simply shows the positive streak count.
public struct GoalStreakCounter: View {
    public let streakDays: Int

    public init(streakDays: Int) {
        self.streakDays = streakDays
    }

    public var body: some View {
        if streakDays > 0 {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("\(streakDays) day\(streakDays == 1 ? "" : "s") in a row")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(streakDays) day streak")
        }
    }
}
