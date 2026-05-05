#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - WeighCaptureView
//
// §17 Scale integration — POS "Weigh" button → live reading capture:
//   - Shows a live weight stream from the paired scale.
//   - "Capture" button locks the stable reading; returned via `onCapture` callback.
//   - "Tare / Zero" button zeroes the offset.
//   - "Re-weigh" button clears the captured value and restarts streaming.
//   - Offline-safe: works on local BT / local network; no internet dependency.
//
// Usage in POS:
// ```swift
// WeighCaptureView(scale: injectedScale) { capturedWeight in
//     viewModel.applyWeight(capturedWeight)
// }
// ```

public struct WeighCaptureView: View {

    // MARK: - State

    @State private var viewModel: WeighCaptureViewModel

    // MARK: - Init

    public init(scale: any WeightScale, onCapture: @escaping (Weight) -> Void) {
        _viewModel = State(initialValue: WeighCaptureViewModel(scale: scale, onCapture: onCapture))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 20) {
            weightDisplay
            controlRow
            captureButton
        }
        .padding()
        .task { await viewModel.startStreaming() }
        .onDisappear { viewModel.stopStreaming() }
    }

    // MARK: - Subviews

    private var weightDisplay: some View {
        VStack(spacing: 4) {
            Text(viewModel.displayWeight)
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .foregroundStyle(viewModel.isStable ? .primary : .secondary)
                .contentTransition(.numericText())
                .accessibilityLabel("Current weight: \(viewModel.displayWeight). \(viewModel.isStable ? "Stable" : "Unstable")")

            Text(viewModel.isStable ? "Stable" : "Measuring…")
                .font(.caption)
                .foregroundStyle(viewModel.isStable ? .green : .orange)
                .accessibilityHidden(true)

            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Scale error: \(err)")
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.tare() }
            } label: {
                Label("Tare / Zero", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Tare scale — zero the reading")
            .accessibilityHint("Sets the current weight as the zero baseline.")

            Button {
                viewModel.reWeigh()
            } label: {
                Label("Re-weigh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.hasCapturedWeight)
            .accessibilityLabel("Re-weigh — capture a new reading")
        }
    }

    private var captureButton: some View {
        Button {
            viewModel.captureCurrentReading()
        } label: {
            Label(
                viewModel.hasCapturedWeight ? "Captured" : "Capture Weight",
                systemImage: viewModel.hasCapturedWeight ? "checkmark.circle.fill" : "scalemass"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isStable || viewModel.hasCapturedWeight)
        .accessibilityLabel(viewModel.hasCapturedWeight
            ? "Weight captured: \(viewModel.displayWeight)"
            : "Capture the current stable weight reading")
    }
}

// MARK: - WeighCaptureViewModel

@Observable
@MainActor
public final class WeighCaptureViewModel {

    // MARK: Published state

    public private(set) var displayWeight: String = "–"
    public private(set) var isStable: Bool = false
    public private(set) var hasCapturedWeight: Bool = false
    public private(set) var errorMessage: String?

    // MARK: Private

    private let scale: any WeightScale
    private let onCapture: (Weight) -> Void
    private var streamTask: Task<Void, Never>?
    private var latestWeight: Weight?
    private var unitStore = WeightUnitStore()

    // MARK: Init

    public init(scale: any WeightScale, onCapture: @escaping (Weight) -> Void) {
        self.scale = scale
        self.onCapture = onCapture
    }

    // MARK: - Streaming

    public func startStreaming() async {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await weight in self.scale.stream() {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.updateDisplay(weight: weight)
                }
            }
        }
    }

    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Tare

    public func tare() async {
        do {
            let tared = try await scale.tare()
            updateDisplay(weight: tared)
            AppLog.hardware.info("WeighCaptureViewModel: tare set")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Capture

    public func captureCurrentReading() {
        guard let weight = latestWeight, weight.isStable else { return }
        hasCapturedWeight = true
        onCapture(weight)
        AppLog.hardware.info("WeighCaptureViewModel: captured \(weight.grams)g")
    }

    // MARK: - Re-weigh

    public func reWeigh() {
        hasCapturedWeight = false
        latestWeight = nil
        displayWeight = "–"
        isStable = false
        errorMessage = nil
    }

    // MARK: - Private

    private func updateDisplay(weight: Weight) {
        latestWeight = weight
        isStable = weight.isStable
        errorMessage = nil
        let preferredUnit = unitStore.selectedUnit
        displayWeight = weight.formatted(in: preferredUnit)
    }
}

// MARK: - Weight formatting helper

private extension Weight {
    func formatted(in unit: WeightUnit) -> String {
        let value: Double
        let suffix: String
        switch unit {
        case .grams:
            value = Double(grams)
            suffix = "g"
        case .kilograms:
            value = Double(grams) / 1000.0
            suffix = "kg"
        case .ounces:
            value = Double(grams) / 28.3495
            suffix = "oz"
        case .pounds:
            value = Double(grams) / 453.592
            suffix = "lb"
        }
        return String(format: "%.2f %@", value, suffix)
    }
}


#endif
