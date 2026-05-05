#if canImport(UIKit)
import Foundation
import Network
import Core

// MARK: - ThirdPartyPrinterDiscovery
//
// §17.4 — "Discovery — StarIO10 + ePOS-Print SDKs: LAN scan + BT scan + USB-C
//           (iPad); list paired."
//
//          "Pair — pick printer → save identifier (serial number) in Settings
//           → per-station profile."
//
// This module provides the LAN discovery layer for Star and Epson thermal printers
// before the vendor SDKs (StarIO10 / ePOS-Print) are added to the Package.swift.
//
// Architecture:
//  - `ThirdPartyPrinterDiscovery` scans the LAN via `BonjourPrinterBrowser` (already
//    browses `_ipp._tcp`, `_printer._tcp`, `_bizarre._tcp`).
//  - Results are matched against `ThermalPrinterModelRegistry` by name fragment
//    to annotate with model capability metadata.
//  - `pair(_:)` saves the chosen printer's ID into the current station's
//    `PrinterProfile.defaultReceiptPrinterId` via `PrinterProfileStore`.
//
// SDK gap note: StarIO10 Swift Package (`StarMicronics/stario10-package-swift`)
// and Epson ePOS-Print (`epson/ePOS-SDK-iOS`) are NOT yet in the Package.swift.
// When they land, add SDK-based discovery calls below the Bonjour scan and merge
// the results. MFi entitlement also required for BT-classic transport.
//
// Static readiness flags (`starIO10SDKAvailable`, `epsonEPOSSDKAvailable`) gate
// SDK-specific code paths so they compile cleanly today with a `false` guard.

// MARK: - DiscoveredThirdPartyPrinter

/// A printer discovered via LAN mDNS (or future SDK discovery).
public struct DiscoveredThirdPartyPrinter: Identifiable, Sendable, Hashable {
    /// Stable ID: Bonjour service key ("_ipp._tcp::Star TSP100IV") or host:port.
    public let id: String
    public let name: String
    public let host: String?
    public let port: Int
    public let transport: ThermalTransport
    /// Matched model spec from `ThermalPrinterModelRegistry`, if recognised.
    public let modelSpec: ThermalPrinterModelSpec?
    /// Whether this printer is the current station's default receipt printer.
    public var isPaired: Bool

    public init(
        id: String,
        name: String,
        host: String?,
        port: Int = 9100,
        transport: ThermalTransport,
        modelSpec: ThermalPrinterModelSpec? = nil,
        isPaired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.transport = transport
        self.modelSpec = modelSpec
        self.isPaired = isPaired
    }
}

// MARK: - ThirdPartyPrinterDiscovery

/// Discovers and pairs Star / Epson thermal printers via LAN Bonjour.
///
/// Drives the "Pair a Printer" sheet in Settings → Hardware → Printers.
/// The view model subscribes to `discovered` and calls `pair(_:)` when the
/// user selects a printer.
@Observable
@MainActor
public final class ThirdPartyPrinterDiscovery {

    // MARK: - Published state

    /// Printers found during the last scan.
    public private(set) var discovered: [DiscoveredThirdPartyPrinter] = []
    public private(set) var isScanning: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let profileStore: PrinterProfileStore
    private let browser: BonjourPrinterBrowser

    // MARK: - Init

    public init(
        profileStore: PrinterProfileStore = PrinterProfileStore(),
        browser: BonjourPrinterBrowser = BonjourPrinterBrowser()
    ) {
        self.profileStore = profileStore
        self.browser = browser
    }

    // MARK: - LAN scan

    /// Performs a ~3 s LAN scan for Star/Epson printers via mDNS / Bonjour.
    ///
    /// After the scan completes each result is annotated with:
    ///  - `modelSpec` — matched from `ThermalPrinterModelRegistry` by name fragment.
    ///  - `isPaired`  — `true` when the printer ID matches the current station's
    ///    `defaultReceiptPrinterId`.
    public func scanLAN() async {
        isScanning = true
        errorMessage = nil

        // Subscribe to the Bonjour stream, let it collect for 3 s, then stop.
        var bonjourResults: [DiscoveredPrinter] = []
        let stream = await browser.discoveryStream()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        for await batch in stream {
            bonjourResults = batch
            if ContinuousClock.now >= deadline { break }
        }
        await browser.stop()

        // Map to our richer type, deduplicate by ID.
        let currentId = profileStore.currentProfile.defaultReceiptPrinterId
        var seen = Set<String>()
        discovered = bonjourResults.compactMap { dp -> DiscoveredThirdPartyPrinter? in
            guard seen.insert(dp.id).inserted else { return nil }
            let spec = ThermalPrinterModelRegistry.spec(forDiscoveredName: dp.name)
            return DiscoveredThirdPartyPrinter(
                id: dp.id,
                name: dp.name,
                host: dp.host,
                port: dp.port ?? 9100,
                transport: .network,
                modelSpec: spec,
                isPaired: dp.id == currentId
            )
        }
        isScanning = false
        AppLog.hardware.info("ThirdPartyPrinterDiscovery: scan complete — \(self.discovered.count) printers found")
    }

    // MARK: - Pair

    /// Saves `printer` as the active receipt printer for the current station.
    ///
    /// §17.4 — "Pair — pick printer → save identifier in Settings →
    ///           per-station profile."
    public func pair(_ printer: DiscoveredThirdPartyPrinter) {
        var profile = profileStore.currentProfile
        profile.defaultReceiptPrinterId = printer.id
        profileStore.save(profile)

        // Reflect locally so the list updates without re-scan.
        for idx in discovered.indices {
            discovered[idx].isPaired = discovered[idx].id == printer.id
        }
        AppLog.hardware.info("ThirdPartyPrinterDiscovery: paired '\(printer.name)' (id=\(printer.id))")
    }

    /// Removes the current station's receipt printer pairing.
    public func unpair(_ printer: DiscoveredThirdPartyPrinter) {
        var profile = profileStore.currentProfile
        if profile.defaultReceiptPrinterId == printer.id {
            profile.defaultReceiptPrinterId = nil
            profileStore.save(profile)
        }
        for idx in discovered.indices where discovered[idx].id == printer.id {
            discovered[idx].isPaired = false
        }
        AppLog.hardware.info("ThirdPartyPrinterDiscovery: unpaired '\(printer.name)'")
    }

    // MARK: - SDK readiness flags

    /// Flip to `true` when `StarMicronics/stario10-package-swift` is added to
    /// `Hardware/Package.swift`. Gates SDK-specific LAN + BT discovery calls.
    public static let starIO10SDKAvailable: Bool = false

    /// Flip to `true` when `epson/ePOS-SDK-iOS` is added to `Hardware/Package.swift`.
    public static let epsonEPOSSDKAvailable: Bool = false
}
#endif
