#if canImport(SwiftUI)
import SwiftUI

// MARK: - WeightDisplayChip

/// Compact SwiftUI chip that shows a live weight reading.
///
/// A pulsing green dot indicates a stable reading; an amber dot indicates
/// the scale is still settling. Uses Liquid Glass material on the chip
/// background (chrome element — not content).
///
/// Usage:
/// ```swift
/// WeightDisplayChip(weight: viewModel.currentWeight)
/// ```
public struct WeightDisplayChip: View {

    public let weight: Weight?

    public init(weight: Weight?) {
        self.weight = weight
    }

    public var body: some View {
        HStack(spacing: 6) {
            stabilityDot
            weightLabel
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Sub-views

    private var stabilityDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var weightLabel: some View {
        Group {
            if let w = weight {
                Text(formattedWeight(w))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text("—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var dotColor: Color {
        guard let w = weight else { return .gray }
        return w.isStable ? .green : .orange
    }

    private func formattedWeight(_ w: Weight) -> String {
        if w.grams >= 1000 {
            return String(format: "%.2f kg", Double(w.grams) / 1000.0)
        } else {
            return "\(w.grams) g"
        }
    }

    private var accessibilityText: String {
        guard let w = weight else { return "No weight reading" }
        let stability = w.isStable ? "stable" : "settling"
        return "\(formattedWeight(w)), \(stability)"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("WeightDisplayChip") {
    VStack(spacing: 16) {
        WeightDisplayChip(weight: Weight(grams: 350, isStable: true))
        WeightDisplayChip(weight: Weight(grams: 1250, isStable: false))
        WeightDisplayChip(weight: nil)
    }
    .padding()
}
#endif
#endif
