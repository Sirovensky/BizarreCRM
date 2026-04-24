import SwiftUI

// MARK: - SkeletonShapeKind

/// The geometric primitive used by a skeleton placeholder.
public enum SkeletonShapeKind: Sendable, Equatable {
    case rectangle(cornerRadius: CGFloat = DesignTokens.Radius.xs)
    case circle
    case capsule

    /// Corner radius for accessibility/shape computations.
    /// Returns 0 for shapes that handle rounding internally.
    public var cornerRadius: CGFloat {
        switch self {
        case .rectangle(let r): return r
        case .circle:           return 0   // handled by ClipShape
        case .capsule:          return 0   // handled by ClipShape
        }
    }
}

// MARK: - SkeletonShape

/// A single skeleton primitive — rectangle, circle, or capsule — with a
/// shimmer overlay that respects `accessibilityReduceMotion`.
///
/// Build compound skeletons by composing `SkeletonShape` instances inside
/// an `HStack`/`VStack`. For higher-level compositions use `SkeletonTextLine`,
/// `SkeletonListRow`, `SkeletonCard`, or `SkeletonGrid`.
///
/// ```swift
/// SkeletonShape(.circle, size: CGSize(width: 40, height: 40))
/// SkeletonShape(.rectangle(), size: CGSize(width: 200, height: 16))
/// SkeletonShape(.capsule, size: CGSize(width: 60, height: 20))
/// ```
public struct SkeletonShape: View {

    // MARK: - Constants

    /// Base fill opacity for the skeleton tone.
    public static let baseFillOpacity: Double = 0.12
    /// Shimmer highlight opacity at peak.
    public static let shimmerHighlightOpacity: Double = 0.30
    /// Duration of one shimmer sweep cycle (seconds).
    public static let shimmerDuration: Double = 1.4

    // MARK: - Stored properties

    public let kind: SkeletonShapeKind
    public let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    /// - Parameters:
    ///   - kind: The geometric primitive.
    ///   - size: Explicit width × height. Defaults to a typical 200 × 14 bar.
    public init(_ kind: SkeletonShapeKind = .rectangle(), size: CGSize = CGSize(width: 200, height: 14)) {
        self.kind = kind
        self.size = size
    }

    // MARK: - Body

    public var body: some View {
        baseShape
            .fill(Color.primary.opacity(Self.baseFillOpacity))
            .frame(width: size.width, height: size.height)
            .overlay {
                if !reduceMotion {
                    SkeletonShimmerOverlay(highlightOpacity: Self.shimmerHighlightOpacity,
                                          duration: Self.shimmerDuration)
                        .clipShape(clippingShape)
                }
            }
            .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private var baseShape: AnyShape {
        switch kind {
        case .rectangle(let r): return AnyShape(RoundedRectangle(cornerRadius: r))
        case .circle:            return AnyShape(Circle())
        case .capsule:           return AnyShape(Capsule())
        }
    }

    private var clippingShape: some Shape {
        _ClipShapeBox(kind: kind)
    }
}

// MARK: - Private helpers

/// Type-erased Shape backed by SkeletonShapeKind — keeps the overlay aligned.
private struct _ClipShapeBox: Shape {
    let kind: SkeletonShapeKind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .rectangle(let r): RoundedRectangle(cornerRadius: r).path(in: rect)
        case .circle:            Circle().path(in: rect)
        case .capsule:           Capsule().path(in: rect)
        }
    }
}

// MARK: - SkeletonShimmerOverlay

/// Standalone horizontal-sweep shimmer used by all skeleton primitives.
/// Exposed `internal` so sibling Skeleton views can reuse it without
/// duplicating animation logic.
struct SkeletonShimmerOverlay: View {

    let highlightOpacity: Double
    let duration: Double

    @State private var phase: CGFloat = -1.0

    private var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .white.opacity(highlightOpacity), location: 0.45),
                .init(color: .white.opacity(highlightOpacity), location: 0.55),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            gradient
                .frame(width: w * 2)
                .offset(x: phase * w)
                .onAppear {
                    withAnimation(
                        .linear(duration: duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1.0
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
