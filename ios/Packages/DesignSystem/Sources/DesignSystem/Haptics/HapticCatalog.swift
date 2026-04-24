import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §66 — Haptics Catalog
// Single source of truth for all app haptic events.
// Callers must not use UIImpactFeedbackGenerator / CHHapticEngine directly.

// MARK: - HapticEvent

public enum HapticEvent: String, Sendable, CaseIterable {
    case saleComplete
    case addToCart
    case scanSuccess
    case scanFail
    case saveForm
    case validationError
    case destructiveConfirm
    case pullToRefresh
    case longPressMenu
    case toggle
    case tabSwitch
    case ticketStatusChange
    case cardDeclined
    case drawerKick
    case clockIn
    case clockOut
    case signatureCommit
    // §30 — UI-interaction semantic events
    /// Fired on primary button press (replaces raw `.addToCart` light tap at CTA sites).
    case buttonTap
    /// Fired when a sheet or modal finishes its present animation.
    case sheetPresented
    /// Fired as each list item appears during a staggered reveal.
    case listItemAppear
    /// Fired on card hover-lift (iPad pointer enter, strong enough to be felt on M-series).
    case cardHoverActivate
}

// MARK: - HapticCatalog

/// Plays haptic (and optional sound) feedback for a typed event.
///
/// Usage:
/// ```swift
/// await HapticCatalog.play(.saleComplete)
/// await HapticCatalog.play(.drawerKick, withSound: true)
/// ```
///
/// - The method is a no-op on platforms without a Taptic Engine
///   (iPad without Taptic, macOS, Simulator) unless UIKit is available.
/// - Quiet hours are respected via `HapticsSettings`.
/// - Settings master toggle respected; critical events (card decline,
///   backup failure) still fire at minimum intensity during quiet hours.
public enum HapticCatalog: Sendable {

    public static func play(_ event: HapticEvent, withSound: Bool = false) async {
        let settings = HapticsSettings.shared
        guard settings.hapticsEnabled else { return }

        let shouldSuppress = QuietHoursCalculator.shouldSuppress(
            at: Date(),
            quietStart: settings.quietHoursStart,
            quietEnd: settings.quietHoursEnd,
            exceptCritical: true
        )

        let isCritical = (event == .cardDeclined)

        if shouldSuppress && !isCritical {
            return
        }

        // Attempt CoreHaptics custom pattern first; fall back to UIKit feedback.
        let didPlayCustom = await CoreHapticsEngine.shared.play(event: event)

        if !didPlayCustom {
            await playUIKitFallback(event)
        }

        if withSound && settings.soundsEnabled && !(shouldSuppress && !isCritical) {
            SoundPlayer.play(event)
        }
    }

    // MARK: - UIKit fallback

    @MainActor
    private static func playUIKitFallback(_ event: HapticEvent) {
        #if canImport(UIKit)
        switch event {
        case .saleComplete, .saveForm, .clockIn, .clockOut:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)

        case .scanFail, .validationError, .cardDeclined:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.error)

        case .destructiveConfirm, .drawerKick:
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.prepare()
            g.impactOccurred()

        case .addToCart, .scanSuccess, .longPressMenu:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            g.impactOccurred()

        case .pullToRefresh, .toggle, .tabSwitch, .ticketStatusChange, .signatureCommit,
             .listItemAppear, .cardHoverActivate:
            let g = UISelectionFeedbackGenerator()
            g.prepare()
            g.selectionChanged()

        case .buttonTap:
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            g.impactOccurred()

        case .sheetPresented:
            // Sheets are large view transitions — use medium to acknowledge.
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            g.impactOccurred()
        }
        #endif
    }
}

// MARK: - BrandHaptics compat shim (§66 migration)

/// Legacy API kept for source compatibility. Routes calls to new `HapticCatalog`.
/// TODO: migrate all `BrandHaptics.*` call sites to `HapticCatalog.play(...)`.
public extension BrandHaptics {
    /// Routes `.tap()` → `.addToCart` (light impact).
    @discardableResult
    static func tapCompat() -> Task<Void, Never> {
        Task { await HapticCatalog.play(.addToCart) }
    }

    /// Routes `.success()` → `.saveForm`.
    @discardableResult
    static func successCompat() -> Task<Void, Never> {
        Task { await HapticCatalog.play(.saveForm) }
    }

    /// Routes `.error()` → `.validationError`.
    @discardableResult
    static func errorCompat() -> Task<Void, Never> {
        Task { await HapticCatalog.play(.validationError) }
    }
}
