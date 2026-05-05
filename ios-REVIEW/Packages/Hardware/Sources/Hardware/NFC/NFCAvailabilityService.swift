#if canImport(SwiftUI)
import SwiftUI
import Core

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreNFC)
import CoreNFC
#endif

// MARK: - NFC availability service
//
// §17.5 — Graceful NFC disable.
//
// Core NFC is only available on iPhone 7 and newer running iOS 13+, plus the
// 2024 iPad Pro M4. Older iPads, the iPhone 6/SE first-gen, and Mac Catalyst
// have no NFC antenna at all. Calling into the framework on those devices
// will hard-crash the process at session-start time.
//
// `NFCAvailabilityService` is the single source of truth for "should we even
// show the NFC entry-points?" Any NFC-bearing UI (ticket intake "Scan tag",
// inventory "Tag item", customer device picker) must gate visibility through
// `isAvailable` or the `.nfcFeatureGate(...)` view modifier below.
//
// The service also surfaces the *reason* NFC is unavailable so we can tailor
// a tooltip ("This iPad doesn't have an NFC antenna" vs. "Disable Airplane
// Mode to use NFC") rather than just hiding the button silently.

public enum NFCAvailability: Sendable, Equatable {
    /// `NFCNDEFReaderSession.readingAvailable == true` and the framework is loadable.
    case available

    /// Hardware lacks an NFC radio (most iPads, iPhone 6 / SE 1st-gen, Mac Catalyst).
    case unsupportedHardware

    /// Hardware supports NFC but the runtime returned `readingAvailable == false`
    /// (Airplane mode, restricted by MDM, parental controls, low power).
    case temporarilyUnavailable

    public var isAvailable: Bool { self == .available }

    /// Short copy suitable for an inline status tag or VoiceOver hint.
    public var displayHint: String {
        switch self {
        case .available:              return "NFC ready"
        case .unsupportedHardware:    return "NFC not supported on this device"
        case .temporarilyUnavailable: return "NFC currently unavailable. Check Airplane Mode and device restrictions."
        }
    }
}

/// Observable wrapper. Call `refresh()` from `.onAppear` / `scenePhase` change
/// — the underlying `readingAvailable` value can flip when the user toggles
/// Airplane Mode without restarting the app.
@MainActor
@Observable
public final class NFCAvailabilityService {

    public static let shared = NFCAvailabilityService()

    public private(set) var availability: NFCAvailability

    public init(initialAvailability: NFCAvailability? = nil) {
        self.availability = initialAvailability ?? Self.detect()
    }

    public func refresh() {
        availability = Self.detect()
    }

    public var isAvailable: Bool { availability.isAvailable }

    /// Pure detector — used by `init` and `refresh()`. Exposed `internal` so tests
    /// can call it directly while still letting consumers go through the actor.
    static func detect() -> NFCAvailability {
        #if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
        if NFCNDEFReaderSession.readingAvailable {
            return .available
        }
        // Framework loaded but the hardware says no — most likely iPad without NFC.
        // Distinguishing "no antenna" vs "Airplane mode" requires private API; we
        // assume hardware-unsupported on iPad-class devices and temporary on phones.
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .unsupportedHardware
        }
        return .temporarilyUnavailable
        #else
        return .unsupportedHardware
        #endif
        #else
        return .unsupportedHardware
        #endif
    }
}

// MARK: - View modifier

/// Hides the wrapped content (or replaces it with a disabled placeholder) when
/// NFC is unavailable. Use on every NFC entry-point in the app.
///
/// ```swift
/// Button("Scan device tag") { showNFCSheet = true }
///     .nfcFeatureGate(service: .shared)
/// ```
public struct NFCFeatureGate: ViewModifier {
    let service: NFCAvailabilityService
    let mode: GateMode

    public enum GateMode: Sendable {
        /// Hide the view entirely when NFC is unavailable.
        case hide
        /// Render the view in a disabled state with a tooltip explaining why.
        case disable
    }

    public init(service: NFCAvailabilityService, mode: GateMode = .hide) {
        self.service = service
        self.mode = mode
    }

    public func body(content: Content) -> some View {
        Group {
            if service.isAvailable {
                content
            } else {
                switch mode {
                case .hide:
                    EmptyView()
                case .disable:
                    content
                        .disabled(true)
                        .opacity(0.4)
                        .help(service.availability.displayHint)
                        .accessibilityHint(service.availability.displayHint)
                }
            }
        }
        .onAppear { service.refresh() }
    }
}

public extension View {
    /// Convenience for `.modifier(NFCFeatureGate(...))`.
    func nfcFeatureGate(
        service: NFCAvailabilityService = .shared,
        mode: NFCFeatureGate.GateMode = .hide
    ) -> some View {
        modifier(NFCFeatureGate(service: service, mode: mode))
    }
}

#endif
