import SwiftUI

// §22.7 — Stage Manager min content area: 700×500 pt.
//
// Attach `.splitViewMinSize()` to the root view of any scene that participates
// in Stage Manager or Split View on iPad.  The modifier writes the scene's
// preferred minimum dimensions into `UIScene.SizeRestrictions` via a
// `UIWindowScene` lookup so the OS prevents shrinking below the threshold.
//
// Usage:
//   WindowGroup { RootView() }
//       .splitViewMinSize()

// MARK: - Constants

/// Minimum Scene / Stage-Manager dimensions required by §22.7.
public enum SplitViewSizeConstants {
    /// Minimum width in points before the compact layout kicks in.
    public static let minWidth: CGFloat = 700
    /// Minimum height in points.
    public static let minHeight: CGFloat = 500
}

// MARK: - ViewModifier

/// Applies `UIScene.SizeRestrictions` so Stage Manager / Split View cannot
/// shrink this scene below 700 × 500 pt.
///
/// On iPhone or platforms without `UIWindowScene` this modifier is a no-op.
///
/// - Note: Must be applied to a view that is a direct descendant of a
///   `WindowGroup` root so that the hosting `UIWindowScene` is reachable
///   via `UIApplication.shared.connectedScenes`.
public struct SplitViewMinSizeModifier: ViewModifier {

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .background(SplitViewSizeApplicator())
    }
}

// MARK: - UIViewRepresentable applicator

/// A zero-size UIView whose `didMoveToWindow` applies size restrictions to
/// the enclosing `UIWindowScene`.
private struct SplitViewSizeApplicator: UIViewRepresentable {
    func makeUIView(context: Context) -> _SizeRestrictionView {
        _SizeRestrictionView()
    }

    func updateUIView(_ uiView: _SizeRestrictionView, context: Context) {}
}

private final class _SizeRestrictionView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySizeRestrictions()
    }

    private func applySizeRestrictions() {
        guard
            let windowScene = window?.windowScene,
            let restrictions = windowScene.sizeRestrictions
        else { return }

        let minSize = CGSize(
            width: SplitViewSizeConstants.minWidth,
            height: SplitViewSizeConstants.minHeight
        )
        // Only tighten — never relax a restriction set by another layer.
        if restrictions.minimumSize.width < minSize.width ||
           restrictions.minimumSize.height < minSize.height {
            restrictions.minimumSize = minSize
        }
    }
}

// MARK: - View extension

public extension View {
    /// Constrains this scene to at least 700 × 500 pt in Stage Manager /
    /// Split View on iPad (§22.7).
    ///
    /// - Returns: A view that enforces the scene minimum size via
    ///   `UIScene.SizeRestrictions`.
    func splitViewMinSize() -> some View {
        modifier(SplitViewMinSizeModifier())
    }
}
