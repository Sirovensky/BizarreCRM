import SwiftUI

// MARK: - AdaptiveContentWidthBreakpoint

/// The resolved breakpoint produced by ``AdaptiveContentWidthModifier``.
///
/// Values are intentionally `Sendable` and `Equatable` so they can be
/// compared in tests without instantiating SwiftUI views.
public enum AdaptiveContentWidthBreakpoint: Sendable, Equatable {
    /// Compact horizontal size class (iPhone portrait / slide-over): 560 pt.
    case compact
    /// Regular size class on a device narrower than 900 pt (iPad portrait,
    /// 11" landscape): 680 pt.
    case regular
    /// Regular size class on a device ≥900 pt wide (13" landscape): 720 pt.
    case wide

    /// The concrete max-width in points for this breakpoint.
    public var maxWidth: CGFloat {
        switch self {
        case .compact: return 560
        case .regular: return 680
        case .wide:    return 720
        }
    }
}

// MARK: - AdaptiveContentWidth logic (pure, testable)

/// Pure function that maps a horizontal size class and a container width to
/// an ``AdaptiveContentWidthBreakpoint``.
///
/// Exposed as a top-level function so tests can cover the decision table
/// without touching SwiftUI's environment.
///
/// - Parameters:
///   - sizeClass: The `horizontalSizeClass` value from the SwiftUI environment.
///   - containerWidth: The available width in points, typically from a
///     `GeometryReader`.
/// - Returns: The appropriate ``AdaptiveContentWidthBreakpoint``.
public func resolveAdaptiveBreakpoint(
    sizeClass: UserInterfaceSizeClass?,
    containerWidth: CGFloat
) -> AdaptiveContentWidthBreakpoint {
    guard sizeClass == .regular else { return .compact }
    return containerWidth >= 900 ? .wide : .regular
}

// MARK: - AdaptiveContentWidthModifier

/// An environment-driven variant of ``MaxContentWidthModifier`` that picks
/// the content-width cap automatically based on the horizontal size class
/// and the container width measured via `GeometryReader`.
///
/// | Size class | Container width | Cap   |
/// |-----------|-----------------|-------|
/// | compact   | any             | 560 pt |
/// | regular   | < 900 pt        | 680 pt |
/// | regular   | ≥ 900 pt        | 720 pt |
///
/// ```swift
/// ScrollView {
///     DetailContent()
///         .adaptiveContentWidth()
///         .adaptiveContentWidth(padding: 24)
/// }
/// ```
public struct AdaptiveContentWidthModifier: ViewModifier {

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Stored properties

    /// Horizontal padding applied inside the resolved cap.
    public let horizontalPadding: CGFloat

    // MARK: - Init

    /// - Parameter horizontalPadding: Symmetric horizontal padding inside the
    ///   capped frame. Default `BrandSpacing.base` (16 pt).
    public init(horizontalPadding: CGFloat = BrandSpacing.base) {
        self.horizontalPadding = horizontalPadding
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        GeometryReader { proxy in
            let breakpoint = resolveAdaptiveBreakpoint(
                sizeClass: horizontalSizeClass,
                containerWidth: proxy.size.width
            )
            content
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: breakpoint.maxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(width: proxy.size.width, alignment: .center)
        }
    }
}

// MARK: - View extension

public extension View {

    /// Applies ``AdaptiveContentWidthModifier``, automatically picking
    /// 560 / 680 / 720 pt based on the horizontal size class and device width.
    ///
    /// - Parameter padding: Horizontal padding inside the cap.
    ///   Default `BrandSpacing.base`.
    /// - Returns: A view with an environment-driven max content width.
    func adaptiveContentWidth(padding: CGFloat = BrandSpacing.base) -> some View {
        modifier(AdaptiveContentWidthModifier(horizontalPadding: padding))
    }
}
