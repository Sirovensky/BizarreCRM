#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - ScaleTareButton
//
// §17.6 — Standalone tare button for use outside the full WeighCaptureView.
//
// `WeightDisplayChip(onTare:)` already provides a compact inline tare trigger.
// `ScaleTareButton` is the full-size equivalent for contexts where a prominent
// standalone button is needed (e.g., a weigh-items toolbar, a scale quick-action
// card, or an operator-facing settings row).
//
// Behaviour:
//   - Taps trigger `scale.tare()` asynchronously.
//   - While in-flight shows an activity indicator instead of the label.
//   - On success briefly shows "Zeroed" with a checkmark and clears after 2 s.
//   - On failure shows the error message with a red cross; auto-clears after 4 s.
//   - Idempotent: re-tapping while a tare is in-flight is a no-op.
//
// Accessibility:
//   - `.accessibilityIdentifier("scale.tare.button")` for UI tests.
//   - Posts a VoiceOver announcement on completion.

// MARK: - ScaleTareButtonState

private enum TareButtonState: Equatable {
    case idle
    case taring
    case success
    case failure(String)
}

// MARK: - ScaleTareButton

/// Full-size tare button that zeroes the scale baseline.
///
/// ```swift
/// ScaleTareButton(scale: pairedScale)
/// ```
public struct ScaleTareButton: View {

    // MARK: - Inputs

    /// The scale to tare. Defaults to `NullWeightScale` for previews.
    public let scale: any WeightScale

    // MARK: - State

    @State private var state: TareButtonState = .idle
    @State private var clearTask: Task<Void, Never>?

    // MARK: - Init

    public init(scale: any WeightScale) {
        self.scale = scale
    }

    // MARK: - Body

    public var body: some View {
        Button(action: handleTap) {
            Label {
                Text(buttonLabel)
            } icon: {
                buttonIcon
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(buttonTint)
        .disabled(state == .taring)
        .accessibilityLabel("Tare scale — set current weight as zero baseline")
        .accessibilityHint(state == .taring ? "Tare in progress" : "Double-tap to zero the scale reading")
        .accessibilityIdentifier("scale.tare.button")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var buttonIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "arrow.counterclockwise")
        case .taring:
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var buttonLabel: String {
        switch state {
        case .idle:              return "Tare / Zero"
        case .taring:            return "Zeroing\u{2026}"
        case .success:           return "Zeroed"
        case .failure(let msg):  return msg
        }
    }

    private var buttonTint: Color? {
        switch state {
        case .failure: return .red
        default:       return nil
        }
    }

    // MARK: - Action

    private func handleTap() {
        guard state != .taring else { return }
        clearTask?.cancel()
        state = .taring

        Task {
            do {
                _ = try await scale.tare()
                await MainActor.run {
                    state = .success
                    UIAccessibility.post(notification: .announcement, argument: "Scale zeroed")
                    AppLog.hardware.info("ScaleTareButton: tare successful")
                }
                scheduleClear(after: 2)
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    state = .failure(msg)
                    UIAccessibility.post(notification: .announcement, argument: "Tare failed: \(msg)")
                    AppLog.hardware.error("ScaleTareButton: tare failed — \(msg, privacy: .public)")
                }
                scheduleClear(after: 4)
            }
        }
    }

    private func scheduleClear(after seconds: TimeInterval) {
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { state = .idle }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ScaleTareButton") {
    VStack(spacing: 20) {
        Text("Tare button — idle (null scale)")
            .font(.caption)
            .foregroundStyle(.secondary)
        ScaleTareButton(scale: NullWeightScale())
            .padding(.horizontal)
    }
    .padding()
}
#endif
#endif
