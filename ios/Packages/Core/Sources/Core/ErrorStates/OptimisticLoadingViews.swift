import SwiftUI

// §63.3 — Supplementary loading-state primitives.
//
//  • `InlineSavingSpinner`   — sub-second save spinner (§63.3 spinner rule).
//  • `BrandProgressBar`      — determinate progress for uploads / imports / jobs.
//  • `OptimisticRowModifier` — "Sending…" glow overlay for optimistic UI items.
//  • `TimedSkeletonView`     — skeleton with 5s cap → "Still loading…" fallback.

// MARK: — §63.3 Spinner (sub-second only)

/// Inline `ProgressView` spinner for operations expected to complete in < 1s
/// (e.g., form save, quick mutation). For longer operations use
/// `BrandProgressBar` with a determinate value.
///
/// ```swift
/// if viewModel.isSaving {
///     InlineSavingSpinner()
/// }
/// ```
public struct InlineSavingSpinner: View {
    /// Optional label shown beside the spinner (e.g. "Saving…").
    public let label: String?
    /// Controls the size of the spinner.
    public let controlSize: ControlSize

    public init(label: String? = "Saving…", controlSize: ControlSize = .small) {
        self.label = label
        self.controlSize = controlSize
    }

    public var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(controlSize)
                .tint(.secondary)

            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(label ?? "Saving")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: — §63.3 Progress bar (determinate)

/// Branded determinate progress bar for uploads, imports, and long-running
/// print jobs. Shows percentage text alongside the bar.
///
/// ```swift
/// BrandProgressBar(value: uploadProgress, label: "Uploading photo…")
/// ```
public struct BrandProgressBar: View {

    /// Progress in range `0.0 … 1.0`.
    public let value: Double
    /// Descriptive label shown above the bar.
    public let label: String?
    /// When `true`, shows the percentage value to the trailing of the bar.
    public let showsPercentage: Bool

    public init(value: Double, label: String? = nil, showsPercentage: Bool = true) {
        self.value = min(max(value, 0), 1)
        self.label = label
        self.showsPercentage = showsPercentage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ProgressView(value: value)
                    .progressViewStyle(BrandLinearProgressViewStyle())

                if showsPercentage {
                    Text(percentageText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(percentageText)
    }

    private var percentageText: String {
        String(format: "%d%%", Int(value * 100))
    }

    private var accessibilityDescription: String {
        label ?? "Progress"
    }
}

// MARK: — Linear progress style

/// Brand-styled linear `ProgressViewStyle` using the primary accent color.
public struct BrandLinearProgressViewStyle: ProgressViewStyle {
    public func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(height: 6)

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tint)
                    .frame(
                        width: proxy.size.width * CGFloat(configuration.fractionCompleted ?? 0),
                        height: 6
                    )
                    .animation(.easeInOut(duration: 0.2), value: configuration.fractionCompleted)
            }
        }
        .frame(height: 6)
    }
}

// MARK: — §63.3 Optimistic UI

/// Modifier that adds an "in-flight" glow to a row while an optimistic write
/// is still pending server confirmation.
///
/// Pair with an `isSending` binding from the ViewModel:
///
/// ```swift
/// TicketRow(ticket: draft)
///     .optimisticPending(isSending: viewModel.isDraftPending(draft.id))
/// ```
public struct OptimisticPendingModifier: ViewModifier {
    public let isSending: Bool

    @State private var glowPhase: Bool = false

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if isSending {
                    sendingChip
                }
            }
            .opacity(isSending ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSending)
    }

    private var sendingChip: some View {
        Text("Sending…")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.background.secondary)
            )
            .opacity(glowPhase ? 1.0 : 0.5)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: glowPhase
            )
            .onAppear { glowPhase = true }
            .onDisappear { glowPhase = false }
            .padding(.trailing, 12)
            .accessibilityLabel("Sending")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

public extension View {
    /// Overlays a pulsing "Sending…" chip while an optimistic write is in flight.
    func optimisticPending(isSending: Bool) -> some View {
        modifier(OptimisticPendingModifier(isSending: isSending))
    }
}

// MARK: — §63.3 Shimmer duration cap

/// Skeleton wrapper that automatically swaps to a "Still loading…" retry
/// banner if loading takes longer than `timeout` seconds (default: 5s).
///
/// ```swift
/// TimedSkeletonView(isLoading: viewModel.isLoading, onRetry: viewModel.reload) {
///     SkeletonList(rowCount: 5)
/// }
/// ```
public struct TimedSkeletonView<Skeleton: View>: View {

    public let isLoading: Bool
    public let timeout: TimeInterval
    public var onRetry: (() -> Void)?
    public let skeleton: () -> Skeleton

    public init(
        isLoading: Bool,
        timeout: TimeInterval = 5,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder skeleton: @escaping () -> Skeleton
    ) {
        self.isLoading = isLoading
        self.timeout = timeout
        self.onRetry = onRetry
        self.skeleton = skeleton
    }

    @State private var hasTimedOut = false
    @State private var timeoutTask: Task<Void, Never>? = nil

    public var body: some View {
        Group {
            if !isLoading {
                EmptyView()
            } else if hasTimedOut {
                slowLoadBanner
            } else {
                skeleton()
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                startTimeout()
            } else {
                cancelTimeout()
                hasTimedOut = false
            }
        }
        .onAppear {
            if isLoading { startTimeout() }
        }
        .onDisappear {
            cancelTimeout()
        }
    }

    private var slowLoadBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Still loading… slower than usual")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let onRetry {
                Button("Tap to retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Still loading, slower than usual. Tap to retry.")
    }

    private func startTimeout() {
        cancelTimeout()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await MainActor.run { hasTimedOut = true }
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

#if DEBUG
#Preview("InlineSavingSpinner") {
    InlineSavingSpinner()
}

#Preview("BrandProgressBar — 40%") {
    BrandProgressBar(value: 0.4, label: "Uploading photo 1 of 3…")
        .padding()
}

#Preview("BrandProgressBar — 100%") {
    BrandProgressBar(value: 1.0, label: "Upload complete")
        .padding()
}

#Preview("OptimisticPending") {
    VStack {
        HStack {
            Text("Ticket #4521 — iPhone 13 screen")
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .optimisticPending(isSending: true)
    }
    .padding()
}

#Preview("TimedSkeleton — timed out") {
    // Force immediate timeout for preview
    TimedSkeletonView(isLoading: true, timeout: 0) {
        Text("Skeleton")
    }
}
#endif
