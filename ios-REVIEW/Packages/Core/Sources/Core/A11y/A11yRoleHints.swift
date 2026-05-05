// Core/A11y/A11yRoleHints.swift
//
// Accessibility hint strings for common interaction patterns.
// Pure enum — no UI framework imports, safe for tests and SwiftUI previews.
//
// Hints tell VoiceOver *how* to interact with an element (as opposed to labels,
// which describe *what* the element is).  Keep hints short — one brief sentence.
//
// Rules (shared additive zone):
//   - Add new constants at the bottom of the relevant inner enum.
//   - Never rename or delete existing constants (key stability).
//   - All strings are NSLocalizedString-backed for i18n.
//
// §26 A11y label catalog — role hints

import Foundation

/// Reusable VoiceOver hint strings for common interaction patterns.
///
/// Usage:
/// ```swift
/// row.accessibilityHint(A11yRoleHints.doubleTapToOpen)
/// swipeableCell.accessibilityHint(A11yRoleHints.swipeForActions)
/// ```
public enum A11yRoleHints: Sendable {

    // MARK: - Tap patterns

    /// "Double-tap to open."
    public static let doubleTapToOpen = NSLocalizedString(
        "a11y.hints.doubleTapToOpen",
        value: "Double-tap to open",
        comment: "VoiceOver hint: double-tap activates an open/drill-down action"
    )

    /// "Double-tap to select."
    public static let doubleTapToSelect = NSLocalizedString(
        "a11y.hints.doubleTapToSelect",
        value: "Double-tap to select",
        comment: "VoiceOver hint: double-tap selects the item"
    )

    /// "Double-tap to toggle."
    public static let doubleTapToToggle = NSLocalizedString(
        "a11y.hints.doubleTapToToggle",
        value: "Double-tap to toggle",
        comment: "VoiceOver hint: double-tap flips a toggle/switch"
    )

    /// "Double-tap to edit."
    public static let doubleTapToEdit = NSLocalizedString(
        "a11y.hints.doubleTapToEdit",
        value: "Double-tap to edit",
        comment: "VoiceOver hint: double-tap enters edit mode"
    )

    /// "Double-tap to delete."
    public static let doubleTapToDelete = NSLocalizedString(
        "a11y.hints.doubleTapToDelete",
        value: "Double-tap to delete",
        comment: "VoiceOver hint: double-tap deletes the item"
    )

    /// "Double-tap to confirm."
    public static let doubleTapToConfirm = NSLocalizedString(
        "a11y.hints.doubleTapToConfirm",
        value: "Double-tap to confirm",
        comment: "VoiceOver hint: double-tap confirms a destructive action"
    )

    // MARK: - Swipe patterns

    /// "Swipe left for more actions."
    public static let swipeLeftForActions = NSLocalizedString(
        "a11y.hints.swipeLeftForActions",
        value: "Swipe left for more actions",
        comment: "VoiceOver hint: left swipe reveals contextual row actions"
    )

    /// "Swipe right to mark as done."
    public static let swipeRightToMarkDone = NSLocalizedString(
        "a11y.hints.swipeRightToMarkDone",
        value: "Swipe right to mark as done",
        comment: "VoiceOver hint: right swipe marks the item complete"
    )

    /// "Swipe up or down to adjust the value."
    public static let swipeToAdjustValue = NSLocalizedString(
        "a11y.hints.swipeToAdjustValue",
        value: "Swipe up or down to adjust the value",
        comment: "VoiceOver hint: vertical swipe adjusts a slider or stepper"
    )

    // MARK: - Hold / long-press patterns

    /// "Touch and hold for options."
    public static let longPressForOptions = NSLocalizedString(
        "a11y.hints.longPressForOptions",
        value: "Touch and hold for options",
        comment: "VoiceOver hint: long-press reveals a context menu"
    )

    // MARK: - Navigation patterns

    /// "Navigate using the tab bar below."
    public static let navigateWithTabBar = NSLocalizedString(
        "a11y.hints.navigateWithTabBar",
        value: "Navigate using the tab bar below",
        comment: "VoiceOver hint pointing users to the bottom tab bar"
    )

    /// "Drag to reorder."
    public static let dragToReorder = NSLocalizedString(
        "a11y.hints.dragToReorder",
        value: "Drag to reorder",
        comment: "VoiceOver hint on a reorderable list row handle"
    )

    // MARK: - Expandable / collapsible patterns

    /// "Double-tap to expand."
    public static let doubleTapToExpand = NSLocalizedString(
        "a11y.hints.doubleTapToExpand",
        value: "Double-tap to expand",
        comment: "VoiceOver hint: double-tap expands a collapsed section"
    )

    /// "Double-tap to collapse."
    public static let doubleTapToCollapse = NSLocalizedString(
        "a11y.hints.doubleTapToCollapse",
        value: "Double-tap to collapse",
        comment: "VoiceOver hint: double-tap collapses an expanded section"
    )

    // MARK: - Search / input patterns

    /// "Double-tap to activate search."
    public static let doubleTapToSearch = NSLocalizedString(
        "a11y.hints.doubleTapToSearch",
        value: "Double-tap to activate search",
        comment: "VoiceOver hint for a tappable search field"
    )

    /// "Scan a barcode by pointing the camera at it."
    public static let pointCameraToScan = NSLocalizedString(
        "a11y.hints.pointCameraToScan",
        value: "Point the camera at a barcode to scan it",
        comment: "VoiceOver hint for a barcode scanner viewfinder"
    )

    // MARK: - Loading / async patterns

    /// "Content is loading."
    public static let contentLoading = NSLocalizedString(
        "a11y.hints.contentLoading",
        value: "Content is loading",
        comment: "VoiceOver hint indicating that content is still being fetched"
    )
}
