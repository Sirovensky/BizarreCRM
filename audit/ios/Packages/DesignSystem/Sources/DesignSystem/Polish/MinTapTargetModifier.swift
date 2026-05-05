import SwiftUI

// MARK: - MinTapTargetModifier

/// Ensures an interactive element has a hit-testing region of at least 44×44 pt,
/// which is the HIG-recommended minimum tap target.
///
/// The visual frame of the content is unchanged; only the tappable region grows.
///
/// **Usage:**
/// ```swift
/// Button { ... } label: {
///     Image(systemName: "xmark")
///         .font(.caption)
/// }
/// .minTapTarget()
/// ```
public struct MinTapTargetModifier: ViewModifier {

    /// Minimum side length in points (HIG: 44 pt).
    public static let minimumSide: CGFloat = 44

    public func body(content: Content) -> some View {
        content
            .frame(
                minWidth: MinTapTargetModifier.minimumSide,
                minHeight: MinTapTargetModifier.minimumSide
            )
            .contentShape(
                Rectangle().size(
                    width: MinTapTargetModifier.minimumSide,
                    height: MinTapTargetModifier.minimumSide
                )
            )
    }
}

// MARK: - View extension

public extension View {
    /// Ensures the interactive tap target is at least 44×44 pt.
    /// Visual size is unchanged; only the hit area is padded.
    func minTapTarget() -> some View {
        modifier(MinTapTargetModifier())
    }
}
