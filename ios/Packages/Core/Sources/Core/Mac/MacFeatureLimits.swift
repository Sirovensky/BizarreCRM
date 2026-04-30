// Core/Mac/MacFeatureLimits.swift
//
// `MacFeatureLimits` — runtime catalog of features that are limited or
// missing on macOS ("Designed for iPad").  Settings / About screens read
// from this catalog to render a "Not on Mac" badge so users discover the
// gap before they hit a dead-end.
//
// §23.6 Mac polish — Missing on Mac (document):
//   - Widgets (limited)
//   - Live Activities (unavailable)
//   - NFC (unavailable)
//   - BlockChyp terminal — works (IP-based, no Bluetooth involved)
//
// Usage:
// ```swift
// ForEach(MacFeatureLimits.all) { limit in
//     HStack {
//         Image(systemName: limit.symbolName)
//         VStack(alignment: .leading) {
//             Text(limit.title).font(.body)
//             Text(limit.detail).font(.caption).foregroundStyle(.secondary)
//         }
//         Spacer()
//         Text(limit.availability.label)
//             .font(.caption2)
//             .padding(.horizontal, 6).padding(.vertical, 2)
//             .background(limit.availability.tint.opacity(0.15),
//                         in: Capsule())
//     }
// }
// ```

import Foundation
import SwiftUI

// MARK: - MacFeatureAvailability

/// Availability tag describing how a feature behaves on macOS.
public enum MacFeatureAvailability: Sendable, Equatable {
    /// Feature works the same as on iPhone / iPad.
    case available
    /// Feature works but with reduced functionality.
    case limited
    /// Feature is not available at all on macOS.
    case unavailable

    public var label: String {
        switch self {
        case .available:   return "Available"
        case .limited:     return "Limited"
        case .unavailable: return "Not on Mac"
        }
    }

    /// Tint colour suitable for badges in Settings / About screens.
    public var tint: Color {
        switch self {
        case .available:   return .green
        case .limited:     return .orange
        case .unavailable: return .red
        }
    }
}

// MARK: - MacFeatureLimit

/// A single Mac-availability descriptor.
public struct MacFeatureLimit: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbolName: String
    public let availability: MacFeatureAvailability

    public init(
        id: String,
        title: String,
        detail: String,
        symbolName: String,
        availability: MacFeatureAvailability
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.availability = availability
    }
}

// MARK: - MacFeatureLimits catalog

/// Public catalog of Mac feature-availability descriptors per §23.6.
public enum MacFeatureLimits {

    /// Widgets — supported but Smart Stack / interactive widgets behave
    /// differently on macOS.
    public static let widgets = MacFeatureLimit(
        id: "mac.limit.widgets",
        title: "Widgets",
        detail: "Home Screen widgets render in the macOS Notification Center; Smart Stack relevance hints are ignored.",
        symbolName: "rectangle.3.group",
        availability: .limited
    )

    /// Live Activities — `ActivityKit` is iOS-only, no Dynamic Island on Mac.
    public static let liveActivities = MacFeatureLimit(
        id: "mac.limit.liveActivities",
        title: "Live Activities",
        detail: "ActivityKit is unavailable on macOS. Ticket / Sale / Clock-in activities show on iPhone & iPad only.",
        symbolName: "bolt.horizontal.circle",
        availability: .unavailable
    )

    /// NFC — `CoreNFC` is iOS-only; mirrors `Platform.supportsNFC == false`.
    public static let nfc = MacFeatureLimit(
        id: "mac.limit.nfc",
        title: "NFC tag scanning",
        detail: "macOS has no NFC reader. Use a paired iPhone for Continuity-camera barcode scans instead.",
        symbolName: "wave.3.right",
        availability: .unavailable
    )

    /// Native barcode scanning — `AVCaptureSession` cameras differ; we offer
    /// Continuity Camera as the suggested workaround.
    public static let nativeBarcodeScan = MacFeatureLimit(
        id: "mac.limit.nativeBarcodeScan",
        title: "Built-in barcode scanner",
        detail: "Mac webcams cannot reliably read 1D barcodes. Use Continuity Camera with an iPhone, or enter SKUs manually.",
        symbolName: "barcode.viewfinder",
        availability: .limited
    )

    /// MFi Bluetooth printers — iOS-only `CBCentralManager`; AirPrint works.
    public static let bluetoothPrinters = MacFeatureLimit(
        id: "mac.limit.bluetoothPrinters",
        title: "Bluetooth thermal printers",
        detail: "MFi Bluetooth receipt printers are iOS-only. Use AirPrint or a network-attached thermal printer on Mac.",
        symbolName: "printer.dotmatrix",
        availability: .unavailable
    )

    /// Haptics — Taptic Engine / CoreHaptics absent on Mac hardware.
    public static let haptics = MacFeatureLimit(
        id: "mac.limit.haptics",
        title: "Haptic feedback",
        detail: "Mac hardware has no Taptic Engine. Haptic cues silently no-op.",
        symbolName: "iphone.radiowaves.left.and.right",
        availability: .unavailable
    )

    /// BlockChyp payment terminals — IP-based protocol, works the same on Mac.
    public static let blockChypTerminal = MacFeatureLimit(
        id: "mac.limit.blockChypTerminal",
        title: "BlockChyp payment terminal",
        detail: "IP-based transport (LAN or cloud relay). Works identically on Mac. No Bluetooth dependency.",
        symbolName: "creditcard",
        availability: .available
    )

    /// Ordered list of all descriptors.  Settings screens render in this order.
    public static let all: [MacFeatureLimit] = [
        widgets,
        liveActivities,
        nfc,
        nativeBarcodeScan,
        bluetoothPrinters,
        haptics,
        blockChypTerminal,
    ]

    /// Returns only the entries the current platform should display in the
    /// Settings ▸ About panel.  On non-Mac runtimes the list is empty.
    public static var visibleOnCurrentPlatform: [MacFeatureLimit] {
        Platform.isMac ? all : []
    }
}
