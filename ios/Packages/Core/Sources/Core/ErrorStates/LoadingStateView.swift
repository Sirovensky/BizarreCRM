import SwiftUI

// §63 — Loading state views: skeleton rows for lists, spinner for cards.
//
// Two public entry points:
//   `SkeletonListView`  — N rows of shimmer placeholders (use in List context)
//   `LoadingSpinnerView` — centred ProgressView with optional label (cards)
//
// No glass on content per CLAUDE.md.

// MARK: — Shimmer effect

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.4), location: 0.4),
                            .init(color: Color.white.opacity(0.4), location: 0.6),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 2)
                    .offset(x: phase * width)
                    .blendMode(.plusLighter)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.4)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: — Skeleton row

/// A single placeholder row that mimics the shape of a typical list row.
///
/// Used internally by `SkeletonListView` but also available standalone for
/// custom layouts.
public struct SkeletonRowView: View {
    /// Relative width of the title bar (0–1). Defaults to 0.6.
    public let titleWidthFraction: CGFloat
    /// Relative width of the subtitle bar (0–1). Defaults to 0.4. Pass 0 to
    /// suppress the subtitle line.
    public let subtitleWidthFraction: CGFloat

    public init(
        titleWidthFraction: CGFloat = 0.6,
        subtitleWidthFraction: CGFloat = 0.4
    ) {
        self.titleWidthFraction = titleWidthFraction
        self.subtitleWidthFraction = subtitleWidthFraction
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Leading avatar placeholder
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemFill))
                .frame(width: 44, height: 44)
                .shimmer()

            VStack(alignment: .leading, spacing: 8) {
                // Title bar
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(.systemFill))
                        .frame(width: geo.size.width * titleWidthFraction, height: 14)
                        .shimmer()
                }
                .frame(height: 14)

                // Subtitle bar (optional)
                if subtitleWidthFraction > 0 {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(.systemFill))
                            .frame(width: geo.size.width * subtitleWidthFraction, height: 11)
                            .shimmer()
                    }
                    .frame(height: 11)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: — Skeleton list

/// N skeleton rows suitable for dropping in as a `List` section or inside a
/// `VStack` while real data is loading.
///
/// ```swift
/// if viewModel.isLoading {
///     SkeletonListView(rowCount: 5)
/// } else {
///     ForEach(viewModel.items) { ... }
/// }
/// ```
public struct SkeletonListView: View {
    public let rowCount: Int

    public init(rowCount: Int = 4) {
        self.rowCount = max(1, rowCount)
    }

    public var body: some View {
        ForEach(0..<rowCount, id: \.self) { index in
            SkeletonRowView(
                titleWidthFraction: titleFraction(for: index),
                subtitleWidthFraction: subtitleFraction(for: index)
            )
        }
    }

    // Vary widths slightly per row so they don't look identical.
    private func titleFraction(for index: Int) -> CGFloat {
        let fractions: [CGFloat] = [0.65, 0.55, 0.70, 0.50, 0.60]
        return fractions[index % fractions.count]
    }

    private func subtitleFraction(for index: Int) -> CGFloat {
        let fractions: [CGFloat] = [0.45, 0.35, 0.50, 0.30, 0.40]
        return fractions[index % fractions.count]
    }
}

// MARK: — Card / full-screen spinner

/// Centred `ProgressView` spinner for card-style loading placeholders.
///
/// ```swift
/// if viewModel.isLoading {
///     LoadingSpinnerView(label: "Loading details…")
/// }
/// ```
public struct LoadingSpinnerView: View {
    public let label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            if let label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityLabel(label ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Skeleton rows") {
    List {
        SkeletonListView(rowCount: 5)
    }
}

#Preview("Spinner — no label") {
    LoadingSpinnerView()
}

#Preview("Spinner — with label") {
    LoadingSpinnerView(label: "Loading invoice…")
}
#endif
