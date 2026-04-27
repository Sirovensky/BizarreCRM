import Foundation

// MARK: - ThermalPrinterModels
//
// §17.4 — "Models targeted — Star TSP100IV (USB / LAN / BT), Star mPOP (combo printer +
// drawer), Epson TM-m30II, Epson TM-T88VII."
//
// This file documents the four target models and provides model-specific capability
// metadata used by `PrintEngine` implementations to pick the correct ESC/POS dialect,
// paper width, and transport availability.
//
// No third-party Star or Epson SDK is imported here — the SDK wrappers land once
// MFi approval is granted (tracked as Discovered note for Agent 10 re: info.plist).
// Today the model registry drives Settings UI and capability checks via the
// `ThermalPrinterModelSpec` value type.

// MARK: - ThermalVendor

public enum ThermalVendor: String, Sendable, CaseIterable, Codable {
    case star
    case epson
}

// MARK: - ThermalPaperWidth

public enum ThermalPaperWidth: Int, Sendable, Codable {
    /// 80mm roll — Star TSP100IV, Epson TM-T88VII, Epson TM-m30II.
    case mm80 = 80
    /// 58mm roll — Star mPOP.
    case mm58 = 58

    /// Corresponding `PrintMedium` key.
    public var printMediumName: String {
        switch self {
        case .mm80: return "thermal80mm"
        case .mm58: return "thermal58mm"
        }
    }
}

// MARK: - ThermalTransport

/// Physical transports the model supports.
public struct ThermalTransport: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// USB (Lightning or USB-C via adapter).
    public static let usb       = ThermalTransport(rawValue: 1 << 0)
    /// Wired Ethernet / Wi-Fi LAN (ESC/POS over TCP port 9100 raw).
    public static let network   = ThermalTransport(rawValue: 1 << 1)
    /// Bluetooth Classic (SPP) via MFi or BLE-SPP bridge.
    public static let bluetooth = ThermalTransport(rawValue: 1 << 2)
    /// AirPrint (IPP over Wi-Fi).
    public static let airPrint  = ThermalTransport(rawValue: 1 << 3)
}

// MARK: - ThermalPrinterModelSpec

/// Capability descriptor for a supported thermal printer model.
public struct ThermalPrinterModelSpec: Sendable, Identifiable {
    /// Human-readable model name (e.g. "Star TSP100IV").
    public let modelName: String
    public let vendor: ThermalVendor
    public let paperWidth: ThermalPaperWidth
    public let transports: ThermalTransport
    /// Whether the model has an integrated cash-drawer RJ11 port.
    public let hasDrawerPort: Bool
    /// Whether the model includes a built-in barcode scanner (e.g. mPOP).
    public let hasIntegratedScanner: Bool
    /// Whether the model supports ESC/POS dialect with full cut command.
    public let supportsFullCut: Bool
    /// USB vendor ID (for future USB-C accessory detection).
    public let usbVendorID: UInt16?
    /// USB product ID.
    public let usbProductID: UInt16?
    /// Bonjour service type advertised on LAN (if known).
    public let bonjourServiceType: String?

    public var id: String { modelName }

    public init(
        modelName: String,
        vendor: ThermalVendor,
        paperWidth: ThermalPaperWidth,
        transports: ThermalTransport,
        hasDrawerPort: Bool,
        hasIntegratedScanner: Bool,
        supportsFullCut: Bool,
        usbVendorID: UInt16? = nil,
        usbProductID: UInt16? = nil,
        bonjourServiceType: String? = nil
    ) {
        self.modelName = modelName
        self.vendor = vendor
        self.paperWidth = paperWidth
        self.transports = transports
        self.hasDrawerPort = hasDrawerPort
        self.hasIntegratedScanner = hasIntegratedScanner
        self.supportsFullCut = supportsFullCut
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.bonjourServiceType = bonjourServiceType
    }
}

// MARK: - ThermalPrinterModelRegistry

/// Registry of the four supported thermal printer models.
///
/// Used by `PrinterSettingsView` for the "Known printers" picker and by the
/// discovery layer to match discovered LAN printers to their model specs.
public enum ThermalPrinterModelRegistry {

    /// All four target models in display order.
    public static let supported: [ThermalPrinterModelSpec] = [
        starTSP100IV,
        starMPOP,
        epsonTMm30II,
        epsonTMT88VII,
    ]

    // MARK: - Star TSP100IV

    /// Star TSP100IV — 80mm roll; USB/LAN/BT/AirPrint.
    ///
    /// The TSP100IV is Star's flagship receipt printer. It supports all four
    /// transports without needing adapter kits. The Bluetooth variant is
    /// "TSP100IV-BT" (BLE-SPP; StarIO10 SDK wraps it). USB-C iPads need
    /// a USB-A → USB-C adapter to connect via USB.
    ///
    /// ESC/POS dialect: Star Line Mode (`STMP` commands disabled; plain ESC/POS
    /// for maximum cross-vendor compatibility).
    public static let starTSP100IV = ThermalPrinterModelSpec(
        modelName: "Star TSP100IV",
        vendor: .star,
        paperWidth: .mm80,
        transports: [.usb, .network, .bluetooth, .airPrint],
        hasDrawerPort: true,
        hasIntegratedScanner: false,
        supportsFullCut: true,
        usbVendorID: 0x0519,   // Star Micronics USB VID
        usbProductID: 0x0003,  // TSP100IV series
        bonjourServiceType: "_printer._tcp"
    )

    // MARK: - Star mPOP

    /// Star mPOP — 58mm roll; USB/Bluetooth; integrated cash drawer + barcode scanner.
    ///
    /// The mPOP is a combo device: it integrates a 58mm thermal printer, cash drawer,
    /// and a barcode scanner into one unit. The scanner is exposed as a separate USB HID
    /// device — `ExternalScannerHIDListener` already handles HID scanners, so no extra
    /// driver is needed. Cash drawer is triggered via the printer's ESC/POS drawer-kick
    /// command (standard RJ11 not present — the drawer is mechanical, integrated).
    ///
    /// Note: mPOP Bluetooth uses the Star BLE-SPP path (`StarPrinterBridge`), not
    /// Classic BT. AirPrint is not supported — the mPOP has no Ethernet port.
    public static let starMPOP = ThermalPrinterModelSpec(
        modelName: "Star mPOP",
        vendor: .star,
        paperWidth: .mm58,
        transports: [.usb, .bluetooth],
        hasDrawerPort: true,  // Integrated drawer; no external RJ11 needed.
        hasIntegratedScanner: true,
        supportsFullCut: true,
        usbVendorID: 0x0519,   // Star Micronics USB VID
        usbProductID: 0x0003,  // mPOP shares VID; distinguished by model string
        bonjourServiceType: nil
    )

    // MARK: - Epson TM-m30II

    /// Epson TM-m30II — 80mm roll; USB/LAN/BT/AirPrint.
    ///
    /// The TM-m30II uses the Epson ePOS-Print SDK for native printing and exposes
    /// an HTTP endpoint on LAN (TCP 8008) for status queries. It supports both the
    /// classic Epson ESC/POS dialect and ePOS-XML. Our integration uses the ESC/POS
    /// path via `EscPosNetworkEngine` (TCP 9100 raw), which avoids the SDK dependency.
    ///
    /// Bluetooth: Epson BT models pair via iOS Bluetooth settings; Epson SDK required
    /// for the BT transport. Deferred until MFi/SDK approval — AirPrint + LAN work today.
    public static let epsonTMm30II = ThermalPrinterModelSpec(
        modelName: "Epson TM-m30II",
        vendor: .epson,
        paperWidth: .mm80,
        transports: [.usb, .network, .bluetooth, .airPrint],
        hasDrawerPort: true,
        hasIntegratedScanner: false,
        supportsFullCut: true,
        usbVendorID: 0x04B8,   // Seiko Epson USB VID
        usbProductID: 0x0E1E,  // TM-m30II
        bonjourServiceType: "_printer._tcp"
    )

    // MARK: - Epson TM-T88VII

    /// Epson TM-T88VII — 80mm roll; USB/LAN/BT/AirPrint.
    ///
    /// The TM-T88VII is Epson's workhorse retail receipt printer. It supports
    /// all four transports and has the highest print speed in our target set
    /// (500 mm/s). ESC/POS dialect is identical to TM-m30II. Full cut + partial
    /// cut both supported.
    public static let epsonTMT88VII = ThermalPrinterModelSpec(
        modelName: "Epson TM-T88VII",
        vendor: .epson,
        paperWidth: .mm80,
        transports: [.usb, .network, .bluetooth, .airPrint],
        hasDrawerPort: true,
        hasIntegratedScanner: false,
        supportsFullCut: true,
        usbVendorID: 0x04B8,   // Seiko Epson USB VID
        usbProductID: 0x0E2C,  // TM-T88VII
        bonjourServiceType: "_printer._tcp"
    )

    // MARK: - Lookup helpers

    /// Returns the spec matching a Bonjour-discovered printer by matching the
    /// vendor-reported model name string (partial, case-insensitive).
    public static func spec(forDiscoveredName name: String) -> ThermalPrinterModelSpec? {
        let lower = name.lowercased()
        return supported.first { lower.contains($0.modelName.lowercased()) }
    }
}
