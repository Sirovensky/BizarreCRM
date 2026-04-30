import Foundation
import Core

// MARK: - PeripheralStationProfile
//
// §17: "Binding profiles: tenant saves 'Station 1 = Printer A + Drawer + Terminal X + Scale';
//       multi-station per location."
//      "Station assignment on launch: staff picks station, or auto-detect via
//       Wi-Fi/Bluetooth proximity; profile drives settings."
//      "Fallback: graceful degrade (PDF receipt, manual drawer open) if any peripheral
//       in profile fails."

// MARK: - Peripheral slot bindings

/// The hardware configuration for a single POS station.
///
/// Serialised to JSON in UserDefaults keyed by `StationProfileStore.udKey`.
public struct PeripheralStationProfile: Identifiable, Codable, Sendable, Hashable {

    // MARK: - Identity

    public var id: UUID
    /// Human-readable name (e.g. "Front Counter", "Station 2").
    public var name: String

    // MARK: - Printer

    /// Identifier of the receipt printer assigned to this station.
    /// `nil` = no printer configured; activates PDF-share fallback.
    public var receiptPrinterSerial: String?
    /// Identifier of the label printer (may be the same printer).
    public var labelPrinterSerial: String?

    // MARK: - Cash drawer

    /// Whether a cash drawer is connected via the printer RJ-11 port on this station.
    public var cashDrawerEnabled: Bool

    // MARK: - Card reader

    /// BlockChyp terminal name paired to this station.
    public var terminalName: String?

    // MARK: - Scale

    /// Bluetooth peripheral UUID of the weight scale on this station.
    public var scalePeripheralId: UUID?

    // MARK: - Auto-detect

    /// Wi-Fi SSID or Bluetooth peripheral UUID used to auto-detect this station
    /// when the app launches. Set to the local SSID or a paired peripheral UUID.
    public var autoDetectHint: String?

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        name: String,
        receiptPrinterSerial: String? = nil,
        labelPrinterSerial: String? = nil,
        cashDrawerEnabled: Bool = false,
        terminalName: String? = nil,
        scalePeripheralId: UUID? = nil,
        autoDetectHint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.receiptPrinterSerial = receiptPrinterSerial
        self.labelPrinterSerial = labelPrinterSerial
        self.cashDrawerEnabled = cashDrawerEnabled
        self.terminalName = terminalName
        self.scalePeripheralId = scalePeripheralId
        self.autoDetectHint = autoDetectHint
    }

    // MARK: - Fallback helpers

    /// Returns `true` if no receipt printer is configured → PDF-share path should activate.
    public var usesPdfFallback: Bool { receiptPrinterSerial == nil }

    /// Returns `true` if no card terminal is configured → card tender unavailable.
    public var noTerminalConfigured: Bool { terminalName == nil }

    /// Returns `true` if drawer requires manual operation (no printer to kick it via ESC).
    public var manualDrawerRequired: Bool { cashDrawerEnabled && receiptPrinterSerial == nil }
}

// MARK: - StationProfileStore

/// Persists an array of `PeripheralStationProfile`s in UserDefaults.
///
/// Thread-safe: read/write only on main actor (profiles are UI-facing admin data).
@Observable
@MainActor
public final class StationProfileStore {

    private static let udKey = "com.bizarrecrm.hw.stationProfiles"
    private static let activeKey = "com.bizarrecrm.hw.activeStationId"

    // MARK: - Published

    public private(set) var profiles: [PeripheralStationProfile] = []
    public private(set) var activeProfileId: UUID?

    // MARK: - Derived

    public var activeProfile: PeripheralStationProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    // MARK: - Init

    public init() {
        load()
    }

    // MARK: - CRUD

    public func add(_ profile: PeripheralStationProfile) {
        profiles.append(profile)
        save()
    }

    public func update(_ profile: PeripheralStationProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    public func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id { activeProfileId = nil }
        save()
    }

    public func activate(id: UUID) {
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeKey)
        AppLog.hardware.info("StationProfileStore: activated profile \(id)")
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.udKey),
           let decoded = try? JSONDecoder().decode([PeripheralStationProfile].self, from: data) {
            profiles = decoded
        }
        if let activeStr = UserDefaults.standard.string(forKey: Self.activeKey),
           let activeId = UUID(uuidString: activeStr) {
            activeProfileId = activeId
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }
}

// MARK: - StationFallbackHandler

/// Evaluates the active station profile and returns degraded-mode actions
/// when a peripheral is unavailable.
///
/// §17: "Fallback: graceful degrade (PDF receipt, manual drawer open) if any
///       peripheral in profile fails."
public struct StationFallbackHandler: Sendable {

    public enum ReceiptFallback: Sendable {
        case printDirect
        case pdfShareSheet
        case emailPdf
    }

    public enum DrawerFallback: Sendable {
        case kickViaPrinter
        case manualOpenWithAudit
    }

    public enum CardFallback: Sendable {
        case useTerminal
        case cashOnly
        case parkCart
    }

    public let profile: PeripheralStationProfile?

    public init(profile: PeripheralStationProfile?) {
        self.profile = profile
    }

    /// Determine receipt path given whether the configured printer is reachable.
    public func receiptFallback(printerReachable: Bool) -> ReceiptFallback {
        guard let profile, !profile.usesPdfFallback else { return .pdfShareSheet }
        return printerReachable ? .printDirect : .pdfShareSheet
    }

    /// Determine drawer path given printer reachability.
    public func drawerFallback(printerReachable: Bool) -> DrawerFallback {
        guard let profile, profile.cashDrawerEnabled else { return .manualOpenWithAudit }
        if profile.manualDrawerRequired { return .manualOpenWithAudit }
        return printerReachable ? .kickViaPrinter : .manualOpenWithAudit
    }

    /// Determine card path given terminal reachability.
    public func cardFallback(terminalOnline: Bool) -> CardFallback {
        guard let profile, !profile.noTerminalConfigured else { return .cashOnly }
        return terminalOnline ? .useTerminal : .cashOnly
    }
}
