import SwiftUI
import DesignSystem

// MARK: - GoalProgressRingView

/// Reusable circular progress ring.
/// - Green ≥ 100%, amber 50-99%, red < 50%.
/// - Liquid Glass surround on toolbar / overlay contexts; never on content rows.
/// - Announces "73 percent of daily revenue target" to VoiceOver.
/// - Respects Reduce Motion: disables animated trim fill.
public struct GoalProgressRingView: View {
    public let fraction: Double
    public let size: CGFloat
    public let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, size: CGFloat = 56, label: String = "") {
        self.fraction = fraction
        self.size = size
        self.label = label
    }

    private var ringColor: Color {
        switch fraction {
        case 1.0...:         return .green
        case 0.50..<1.0:     return .orange
        default:             return .red
        }
    }

    private var accessibilityLabel: String {
        let pct = Int(fraction * 100)
        let base = "\(pct) percent"
        return label.isEmpty ? base : "\(base) of \(label)"
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: size * 0.10)
            Circle()
                .trim(from: 0, to: reduceMotion ? fraction : fraction)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? .none : .easeInOut(duration: DesignTokens.Motion.gentle), value: fraction)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                .foregroundStyle(ringColor)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text("\(Int(fraction * 100)) percent"))
    }
}
