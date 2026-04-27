import Foundation

// MARK: - Printer Model

/// Unique identifier strategy:
///   - AirPrint: URL string of the printer (stable per host)
///   - Network ESC/POS: "host:port"
///   - MFi BT: peripheral UUID string
public struct Printer: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let kind: PrinterKind
    public let connection: PrinterConnection
    public let status: PrinterStatus

    public init(
        id: String,
        name: String,
        kind: PrinterKind,
        connection: PrinterConnection,
        status: PrinterStatus = .idle
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.connection = connection
        self.status = status
    }

    /// Returns a new `Printer` with the given status (immutable update).
    public func withStatus(_ newStatus: PrinterStatus) -> Printer {
        Printer(id: id, name: name, kind: kind, connection: connection, status: newStatus)
    }
}

// MARK: - Printer Kind

public enum PrinterKind: String, Sendable, Codable, CaseIterable {
    case thermalReceipt     // Star TSP143, Epson TM-T88 etc.
    case label              // Zebra ZSB-DP12, Brother QL-820 etc.
    case documentAirPrint   // Generic AirPrint document printer
}

// MARK: - Printer Connection

public enum PrinterConnection: Sendable, Hashable, Codable {
    case airPrint(url: URL)
    case network(host: String, port: Int)
    case bluetoothMFi(id: String)

    public var displayString: String {
        switch self {
        case .airPrint(let url):      return "AirPrint — \(url.host ?? url.absoluteString)"
        case .network(let h, let p):  return "Network — \(h):\(p)"
        case .bluetoothMFi(let id):   return "Bluetooth MFi — \(id)"
        }
    }
}

// MARK: - Printer Status

public enum PrinterStatus: Sendable, Equatable, Hashable, Codable {
    case idle
    case printing
    case error(String)
}

// MARK: - Print Job

public struct PrintJob: Sendable {
    public let id: UUID
    public let kind: JobKind
    public let payload: JobPayload
    public let createdAt: Date
    /// When `true`, the engine appends a cash-drawer-kick ESC/POS opcode after
    /// the print data and cut command. Only effective for thermal receipt printers
    /// that have a drawer connected via the RJ11 port. Defaults to `false`.
    public let kickDrawer: Bool
    /// Number of copies to print. Must be ≥ 1; clamped on init. Defaults to 1.
    /// The queue sends the same job to the engine `copies` times sequentially.
    public let copies: Int

    public init(
        id: UUID = UUID(),
        kind: JobKind,
        payload: JobPayload,
        createdAt: Date = Date(),
        kickDrawer: Bool = false,
        copies: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.kickDrawer = kickDrawer
        self.copies = max(1, copies)
    }
}

public enum JobKind: String, Sendable, Codable {
    case receipt
    case label
    case ticketTag
    case barcode
}

// MARK: - Print Engine Protocol

/// Core contract for every printer backend. Engines are Sendable so they can
/// be held by actors (e.g. `PrintJobQueue`) across concurrency boundaries.
public protocol PrintEngine: Sendable {
    /// Discover printers reachable by this engine. May be empty immediately
    /// (AirPrint uses a picker; network engine tries ping).
    func discover() async throws -> [Printer]

    /// Send `job` to `printer`. Throws `PrintEngineError` on failure.
    func print(_ job: PrintJob, on printer: Printer) async throws
}

// MARK: - Print Engine Errors

public enum PrintEngineError: Error, LocalizedError, Equatable {
    case printerNotReachable(String)
    case unsupportedJobKind(JobKind)
    case renderFailed(String)
    case sendFailed(String)
    case noPrinterConfigured
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .printerNotReachable(let id):
            return "Printer '\(id)' is not reachable."
        case .unsupportedJobKind(let k):
            return "This printer does not support \(k.rawValue) jobs."
        case .renderFailed(let detail):
            return "Render failed: \(detail)"
        case .sendFailed(let detail):
            return "Send to printer failed: \(detail)"
        case .noPrinterConfigured:
            return "No printer configured. Add a printer in Settings → Hardware."
        case .cancelled:
            return "Print job was cancelled."
        }
    }
}
