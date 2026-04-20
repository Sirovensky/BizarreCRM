import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Brand-scoped haptic helpers. Keeps feedback consistent across screens so
/// a "tap" feels the same in PIN keypad, barcode scan, and POS line-item
/// add. All methods are no-ops on Mac + iPad (where `Platform.supportsHaptics`
/// is false) — no feature gate needed at callsites.
public enum BrandHaptics {

    /// Light tap — used for key entry (PIN digit, keypad numeric input).
    public static func tap() {
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Medium tap — action committed (e.g. row swipe-to-delete, sync start).
    public static func tapMedium() {
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Success tick — a transaction lands, a scan matches, save completes.
    public static func success() {
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.success)
        }
        #endif
    }

    /// Warning — soft-fail state that needs attention but isn't fatal.
    public static func warning() {
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.warning)
        }
        #endif
    }

    /// Hard error — invalid PIN, scan failure, payment decline.
    public static func error() {
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.error)
        }
        #endif
    }
}
