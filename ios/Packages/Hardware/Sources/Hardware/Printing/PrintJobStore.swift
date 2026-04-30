import Foundation
import Core
#if canImport(UIKit)
import UIKit
#endif

// §17.3 / §17.4 — PrintJobQueue GRDB persistence.
//
// Previously, PrintJobQueue held jobs only in memory (lost on app kill).
// This store persists pending + dead-letter jobs to disk so they survive
// app restarts. GRDB integration uses the shared `AppDatabase` from
// the Persistence package (Core imports it).
//
// Schema: a flat JSON-encoded row per job entry. SQLite migrations for
// this table live in `Persistence/Migrations/`.
//
// Until the full Persistence package migration runs, we fall back to
// a JSON file in Application Support (upgrade-safe; reads → migrates → purge).

// MARK: - PersistedJobEntry

public struct PersistedJobEntry: Codable, Sendable {
    public let id: UUID
    public let jobId: UUID
    public let jobKind: String
    public let payloadData: Data     // JSON-encoded JobPayload sub-type
    public let payloadKind: String   // "receipt" | "label" | "ticketTag" | "barcode"
    public let printerData: Data     // JSON-encoded Printer
    public var attempts: Int
    public var lastError: String?
    public let createdAt: Date
    public var deadLettered: Bool

    public init(
        id: UUID = UUID(),
        jobId: UUID,
        jobKind: String,
        payloadData: Data,
        payloadKind: String,
        printerData: Data,
        attempts: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        deadLettered: Bool = false
    ) {
        self.id = id
        self.jobId = jobId
        self.jobKind = jobKind
        self.payloadData = payloadData
        self.payloadKind = payloadKind
        self.printerData = printerData
        self.attempts = attempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.deadLettered = deadLettered
    }
}

// MARK: - PrintJobStore

/// File-backed store for persisting `PrintJobQueue.QueueEntry` values
/// across app restarts. Backed by a JSON file in Application Support.
/// Upgraded to GRDB when Persistence migration lands.
public actor PrintJobStore {

    // MARK: - Constants

    private static let fileName = "print_job_queue.json"

    // MARK: - File URL

    private var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BizarreCRM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.fileName)
    }

    // MARK: - Load

    public func load() throws -> [PersistedJobEntry] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        let data = try Data(contentsOf: storeURL)
        return try JSONDecoder().decode([PersistedJobEntry].self, from: data)
    }

    // MARK: - Save

    public func save(_ entries: [PersistedJobEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Upsert

    public func upsert(_ entry: PersistedJobEntry) throws {
        var all = (try? load()) ?? []
        if let idx = all.firstIndex(where: { $0.id == entry.id }) {
            all[idx] = entry
        } else {
            all.append(entry)
        }
        try save(all)
    }

    // MARK: - Delete

    public func delete(id: UUID) throws {
        var all = (try? load()) ?? []
        all.removeAll { $0.id == id }
        try save(all)
    }

    public func deleteAll() throws {
        try save([])
    }
}

// MARK: - PrinterProfile (§17.4 per-location + per-station)

/// Per-location / per-station printer configuration.
/// Stored per-station (identified by `stationId = UIDevice.current.identifierForVendor`).
/// Each station can override the location-level defaults.
public struct PrinterProfile: Codable, Sendable, Identifiable {
    public var id: String { stationId }

    /// `UIDevice.current.identifierForVendor.uuidString` — unique per install.
    public let stationId: String
    /// Human-readable name for this station (e.g. "Front Counter").
    public var stationName: String
    /// Location ID (tenant can have multiple locations).
    public var locationId: String?
    /// Default receipt printer for this station.
    public var defaultReceiptPrinterId: String?
    /// Default label printer for this station.
    public var defaultLabelPrinterId: String?
    /// Paper size preference (overrides tenant default).
    public var paperSize: PrintMediumPreference

    public init(
        stationId: String,
        stationName: String,
        locationId: String? = nil,
        defaultReceiptPrinterId: String? = nil,
        defaultLabelPrinterId: String? = nil,
        paperSize: PrintMediumPreference = .thermal80mm
    ) {
        self.stationId = stationId
        self.stationName = stationName
        self.locationId = locationId
        self.defaultReceiptPrinterId = defaultReceiptPrinterId
        self.defaultLabelPrinterId = defaultLabelPrinterId
        self.paperSize = paperSize
    }
}

public enum PrintMediumPreference: String, Codable, Sendable, CaseIterable {
    case thermal80mm = "80mm Thermal"
    case thermal58mm = "58mm Thermal"
    case letter = "Letter (US)"
    case legal = "Legal (US)"
    case a4 = "A4"
    case label2x4 = "Label 2×4\""
}

#if canImport(SwiftUI)
import SwiftUI

public extension PrintMediumPreference {
    var printMedium: PrintMedium {
        switch self {
        case .thermal80mm: return .thermal80mm
        case .thermal58mm: return .thermal58mm
        case .letter:      return .letter
        case .legal:       return .legal
        case .a4:          return .a4
        case .label2x4:    return .label2x4
        }
    }
}
#endif

// MARK: - PrinterProfileStore

#if canImport(UIKit)
/// Persists per-station `PrinterProfile` values in UserDefaults.
@MainActor
public final class PrinterProfileStore {

    private static let key = "com.bizarrecrm.hardware.printerProfiles"

    public init() {}

    public var currentStationId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    public func loadAll() -> [PrinterProfile] {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([PrinterProfile].self, from: data) else {
            return []
        }
        return decoded
    }

    public func profile(for stationId: String) -> PrinterProfile? {
        loadAll().first { $0.stationId == stationId }
    }

    public var currentProfile: PrinterProfile {
        profile(for: currentStationId) ?? PrinterProfile(
            stationId: currentStationId,
            stationName: "This Station"
        )
    }

    public func save(_ profile: PrinterProfile) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.stationId == profile.stationId }) {
            all[idx] = profile
        } else {
            all.append(profile)
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    // MARK: - Active printer helpers (for PrintService)

    /// The active receipt printer for this station, if one has been selected and persisted.
    /// Returns nil when no printer is configured → callers should fall back to PDF share sheet.
    public var activeReceiptPrinter: Printer? {
        guard let printerId = currentProfile.defaultReceiptPrinterId else { return nil }
        return loadPrinter(id: printerId)
    }

    /// The active label printer for this station, if one has been selected and persisted.
    /// Returns nil when no label printer is configured.
    public var activeLabelPrinter: Printer? {
        guard let printerId = currentProfile.defaultLabelPrinterId else { return nil }
        return loadPrinter(id: printerId)
    }

    // MARK: - Printer catalogue (lightweight UserDefaults store)

    private static let printerCatalogueKey = "com.bizarrecrm.hardware.printerCatalogue"

    /// Persist a `Printer` so it can be retrieved by ID later.
    public func persist(printer: Printer) {
        var catalogue = loadCatalogue()
        catalogue[printer.id] = printer
        let data = catalogue.values.map { p -> [String: String] in
            var dict = ["id": p.id, "name": p.name, "kind": p.kind.rawValue]
            switch p.connection {
            case .airPrint(let url):        dict["conn"] = "airprint:\(url.absoluteString)"
            case .network(let h, let p_):   dict["conn"] = "net:\(h):\(p_)"
            case .bluetoothMFi(let id_):    dict["conn"] = "mfi:\(id_)"
            }
            return dict
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: data) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.printerCatalogueKey)
    }

    private func loadPrinter(id: String) -> Printer? {
        loadCatalogue()[id]
    }

    private func loadCatalogue() -> [String: Printer] {
        guard let data = UserDefaults.standard.data(forKey: Self.printerCatalogueKey),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [:] }
        var result: [String: Printer] = [:]
        for dict in array {
            guard let id = dict["id"],
                  let name = dict["name"],
                  let kindRaw = dict["kind"],
                  let kind = PrinterKind(rawValue: kindRaw),
                  let connStr = dict["conn"] else { continue }
            let conn: PrinterConnection
            if connStr.hasPrefix("airprint:"), let url = URL(string: String(connStr.dropFirst("airprint:".count))) {
                conn = .airPrint(url: url)
            } else if connStr.hasPrefix("net:") {
                let parts = connStr.dropFirst("net:".count).split(separator: ":", maxSplits: 1)
                if parts.count == 2, let port = Int(parts[1]) {
                    conn = .network(host: String(parts[0]), port: port)
                } else { continue }
            } else if connStr.hasPrefix("mfi:") {
                conn = .bluetoothMFi(id: String(connStr.dropFirst("mfi:".count)))
            } else { continue }
            result[id] = Printer(id: id, name: name, kind: kind, connection: conn)
        }
        return result
    }
}
#endif
