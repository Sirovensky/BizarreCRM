import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum Platform {
    public static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    /// UIDevice.current is @MainActor in Swift 6 strict concurrency. Rather
    /// than forcing every caller onto the main actor, we read the idiom via
    /// `UITraitCollection.current`, which is nonisolated, and cache the
    /// result since the device idiom can't change at runtime.
    #if canImport(UIKit)
    @MainActor
    private static let cachedIdiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom

    @MainActor
    public static var isIPad: Bool { cachedIdiom == .pad && !isMac }

    @MainActor
    public static var isIPhone: Bool { cachedIdiom == .phone }

    @MainActor
    public static var isCompact: Bool { isIPhone }

    @MainActor
    public static var supportsHaptics: Bool { isIPhone }
    #else
    public static var isIPad: Bool { false }
    public static var isIPhone: Bool { false }
    public static var isCompact: Bool { false }
    public static var supportsHaptics: Bool { false }
    #endif

    public static var supportsNativeBarcodeScan: Bool { !isMac }
    public static var supportsBluetoothClassicPrinter: Bool { !isMac }

    // MARK: - §23.1 Mac feature gates

    /// NFC reader API is unavailable on macOS ("Designed for iPad").
    public static var supportsNFC: Bool { !isMac }

    /// CoreHaptics / Taptic Engine is unavailable on macOS.
    /// Call sites no-op haptic calls when this is false.
    public static var supportsHapticEngine: Bool { !isMac }

    /// AirPrint is the Mac-compatible printer path; MFi Bluetooth printers
    /// use iOS-only CBCentralManager (unavailable on Mac).
    /// Feature owners gate `HardwarePrinting.sendRaw(_:)` on this flag.
    public static var requiresAirPrintOnMac: Bool { isMac }

    /// Continuity Camera lets users pick up an iPhone camera from a Mac.
    /// Show a hint to use this instead of native camera scan on Mac.
    public static var suggestsContinuityCamera: Bool { isMac }

    /// Minimum window width / height for the Mac scene (§23.2).
    public static var macMinWindowSize: CGSize { CGSize(width: 900, height: 600) }

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
