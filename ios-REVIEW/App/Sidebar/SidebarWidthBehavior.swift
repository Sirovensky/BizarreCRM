import CoreGraphics

// MARK: - SidebarWidth

/// Semantic width category for the iPad sidebar.
///
/// Computed from the container's total width via `SidebarWidthCalculator`.
/// Used by `iPadSplit` in `RootView.swift` to feed
/// `navigationSplitViewColumnWidth(min:ideal:max:)`.
public enum SidebarWidth: Equatable, Sendable {
    /// Container narrower than 600 pt (Slide Over, Stage Manager compressed).
    case compact
    /// Container 600–1000 pt (11" iPad, split-half 13" iPad).
    case regular
    /// Container wider than 1000 pt (13" iPad full screen).
    case expanded
}

// MARK: - SidebarWidthCalculator

/// Pure, stateless helper that maps container widths to sidebar column
/// width constraints per §22.2 of `ios/ActionPlan.md`.
///
/// All values are design-token-aligned:
/// - compact  → (240, 260, 280) pt
/// - regular  → (260, 300, 340) pt
/// - expanded → (320, 360, 400) pt
public enum SidebarWidthCalculator {

    // MARK: Category mapping

    /// Classify a container width into a `SidebarWidth` category.
    ///
    /// - Parameter viewWidth: The horizontal extent of the split-view container.
    /// - Returns: The appropriate `SidebarWidth` category.
    public static func width(for viewWidth: CGFloat) -> SidebarWidth {
        switch viewWidth {
        case ..<600:
            return .compact
        case 600..<1000:
            return .regular
        default:
            return .expanded
        }
    }

    // MARK: Column width recommendation

    /// Return the recommended `(min, ideal, max)` column widths for a
    /// given `SidebarWidth` category.
    ///
    /// These values are passed directly to
    /// `.navigationSplitViewColumnWidth(min:ideal:max:)`.
    ///
    /// - Parameter category: The resolved sidebar category.
    /// - Returns: A tuple of `(min, ideal, max)` in points.
    public static func recommendedSidebarWidth(
        for category: SidebarWidth
    ) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch category {
        case .compact:  return (min: 240, ideal: 260, max: 280)
        case .regular:  return (min: 260, ideal: 300, max: 340)
        case .expanded: return (min: 320, ideal: 360, max: 400)
        }
    }
}
