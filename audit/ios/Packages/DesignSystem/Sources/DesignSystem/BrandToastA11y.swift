import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §30.13 — Toast accessibility + haptics
// Implements:
//   line 4621: A11y: `accessibilityPriority(.high)` for VoiceOver;
//              `announcement` on show
//   line 4622: Haptics: success=`.success`; warning=`.warning`;
//              danger=`.error`
//
// SwiftUI uses `accessibilitySortPriority(_:)` — we expose a single source
// constant so all toasts read in the same VO order regardless of where they
// surface. The announcement is posted with `UIAccessibility.post` so it
// works for the BrandToast view AND for tenant-side custom toasts that
// reuse `BrandToastA11y.announce(_:)` directly.
//
// APPEND-ONLY — do not rename or remove this file's public surface.

// MARK: - BrandToastA11y

public enum BrandToastA11y {

    /// Sort priority used on every BrandToast so VoiceOver focuses the toast
    /// before any sibling accessibility element. Higher = sooner.
    /// 100 sits well above default (0) but leaves room above for explicit
    /// "alert" overlays (e.g. fatal-error sheets) that can use 200.
    public static let priority: Double = 100

    /// Posts a high-priority VoiceOver announcement for `message`. No-ops on
    /// platforms without UIKit (Mac Catalyst falls through; SPM/Linux too).
    public static func announce(_ message: String) {
        #if canImport(UIKit)
        Task { @MainActor in
            // iOS 17+ supports the announcement priority via attributed string.
            // Fall back to plain post otherwise.
            if #available(iOS 17.0, *) {
                var attr = AttributedString(message)
                attr.accessibilitySpeechAnnouncementPriority = .high
                UIAccessibility.post(notification: .announcement, argument: attr)
            } else {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        #endif
    }
}

// MARK: - BrandToast.Haptics

public extension BrandToast {

    /// Maps toast kind → BrandHaptics call per §30.13 line 4622.
    enum Haptics {
        public static func fire(for kind: BrandToast.Kind) {
            switch kind {
            case .info:    break                    // no haptic — info is silent
            case .success: BrandHaptics.success()
            case .warning: BrandHaptics.warning()
            case .error:   BrandHaptics.error()
            }
        }
    }
}
