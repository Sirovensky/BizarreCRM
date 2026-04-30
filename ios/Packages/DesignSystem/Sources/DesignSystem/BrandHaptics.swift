import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - BrandHaptics (§30.7 / §66)

/// Brand-scoped haptic helpers. Keeps feedback consistent across screens.
///
/// **Master toggle** — respects `BrandHapticsSettings.isEnabled`. When the user
/// disables haptics in Settings, all methods become no-ops. Mac is always a no-op
/// because `UIImpactFeedbackGenerator` is unavailable there.
///
/// All methods fire-and-forget via a detached `Task`. Callers do not need to
/// `await` anything or manage generator lifecycle.
///
/// ### §30.7 catalog
/// - `.selection` — picker / chip toggle
/// - `.success` — save / payment success
/// - `.warning` — validation error
/// - `.error` — hard failure
/// - `.lightImpact` — list item open / key press
/// - `.heavyImpact` — destructive confirm (delete, void, cash-out)
/// - `.tapMedium` — action committed (swipe-to-delete, sync start)
public enum BrandHaptics {

    // MARK: - §30.7 catalog

    /// Selection-changed feedback — picker scroll, chip toggle.
    public static func selection() {
        guard BrandHapticsSettings.isEnabled else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UISelectionFeedbackGenerator()
            gen.prepare()
            gen.selectionChanged()
        }
        #endif
    }

    /// Success tick — a transaction lands, a scan matches, save completes.
    public static func success() {
        guard BrandHapticsSettings.isEnabled else { return }
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
        guard BrandHapticsSettings.isEnabled else { return }
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
        guard BrandHapticsSettings.isEnabled else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.error)
        }
        #endif
    }

    /// Light tap — list item open, key press (PIN digit, numeric keypad).
    public static func lightImpact() {
        guard BrandHapticsSettings.isEnabled else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Heavy impact — destructive confirm (delete, void, cash-out).
    public static func heavyImpact() {
        guard BrandHapticsSettings.isEnabled else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    // MARK: - Legacy (kept for source compatibility)

    /// Light tap — kept for legacy call sites. Prefer `lightImpact()`.
    public static func tap() { lightImpact() }

    /// Medium tap — action committed (row swipe-to-delete, sync start).
    public static func tapMedium() {
        guard BrandHapticsSettings.isEnabled else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }
}

// MARK: - BrandHapticsSettings

/// Persisted master toggle for haptic feedback.
///
/// Backed by `UserDefaults`. Toggle is exposed in Settings → Accessibility.
/// Mac Catalyst always returns `false` for `isEnabled` because
/// `UIImpactFeedbackGenerator` is unavailable.
///
/// Usage from a Settings ViewModel:
/// ```swift
/// BrandHapticsSettings.isEnabled = userWantsHaptics
/// ```
public enum BrandHapticsSettings {

    private static let key = "com.bizarrecrm.haptics.enabled"

    /// Whether haptic feedback is enabled. Defaults to `true` on iPhone.
    /// Always `false` on Mac (haptics unavailable).
    public static var isEnabled: Bool {
        get {
            #if targetEnvironment(macCatalyst)
            return false
            #else
            // UserDefaults returns `false` if key is unset; default to `true`.
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
