#if canImport(SwiftUI)
import SwiftUI

// MARK: - WeightDisplayChip

/// Compact SwiftUI chip that shows a live weight reading.
///
/// A pulsing green dot indicates a stable reading; an amber dot indicates
/// the scale is still settling. Uses Liquid Glass material on the chip
/// background (chrome element — not content).
///
/// §17.6: When `onTare` is supplied the chip shows a "Tare" button that
/// calls the callback so POS can zero the scale before adding items.
///
/// Usage:
/// ```swift
/// WeightDisplayChip(weight: viewModel.currentWeight, onTare: {
///     await viewModel.tare()
/// })
/// ```
public struct WeightDisplayChip: View {

    public let weight: Weight?
    /// Called when the user taps "Tare". `nil` = no tare button shown.
    public let onTare: (() async -> Void)?
    @State private var isTaring: Bool = false

    public init(weight: Weight?, onTare: (() async -> Void)? = nil) {
        self.weight = weight
        self.onTare = onTare
    }

    public var body: some View {
        HStack(spacing: 6) {
            stabilityDot
            weightLabel
            if let tare = onTare {
                Divider()
                    .frame(height: 14)
                    .opacity(0.4)
                tareButton(action: tare)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Tare button

    @ViewBuilder
    private func tareButton(action: @escaping () async -> Void) -> some View {
        Button {
            guard !isTaring else { return }
            isTaring = true
            Task {
                await action()
                isTaring = false
            }
        } label: {
            Group {
                if isTaring {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text("Tare")
                        .font(.system(.caption2, design: .rounded))
                }
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isTaring)
        .accessibilityLabel("Tare scale — zero the current weight")
        .accessibilityIdentifier("scale.tare")
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
        WeightDisplayChip(weight: Weight(grams: 500, isStable: true), onTare: {
            try? await Task.sleep(nanoseconds: 500_000_000)
        })
    }
    .padding()
}
#endif
#endif
