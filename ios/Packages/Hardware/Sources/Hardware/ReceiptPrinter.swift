import Foundation
import Core

/// Printable receipt payload. Kept intentionally shallow: the printer
/// adapter receives already-rendered lines (via `PosReceiptRenderer`)
/// plus the metadata it needs for the header band. Money lives in cents
/// so summation never drifts across the serialization boundary.
public struct ReceiptPayload: Sendable, Equatable {
    public let lines: [String]
    public let totalCents: Int
    public let merchant: String
    public let date: Date

    public init(lines: [String], totalCents: Int, merchant: String, date: Date) {
        self.lines = lines
        self.totalCents = totalCents
        self.merchant = merchant
        self.date = date
    }
}

/// Errors surfaced by any `ReceiptPrinter` adapter. Wrapped as an enum
/// rather than bare `Error` so the Pos layer can branch on "not paired
/// yet" vs "IO failed mid-print" without string-matching.
public enum ReceiptPrinterError: Error, LocalizedError, Equatable {
    case notPaired
    case notAvailable
    case printFailed(String)
    case drawerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notPaired:
            return "Receipt printer is not paired. Pair a printer in Settings to enable printing."
        case .notAvailable:
            return "Receipt printer is unavailable."
        case .printFailed(let detail):
            return "Print failed: \(detail)"
        case .drawerFailed(let detail):
            return "Cash drawer failed: \(detail)"
        }
    }
}

/// Thin contract the Pos layer talks to. Concrete adapters (MFi /
/// Star / Epson / network) slot in behind this interface so the
/// POS view-models never see vendor SDK types.
///
/// TODO §17.4 — wire a real adapter (Star SDK or MFi StarPRNT /
/// Bluetooth) that implements this protocol. Until then, the null
/// printer below is the default registered in `ContainerBootstrap`
/// so callers can fail gracefully with `.notPaired`.
public protocol ReceiptPrinter: AnyObject, Sendable {
    func isAvailable() -> Bool
    func printReceipt(_ payload: ReceiptPayload) async throws
    func openCashDrawer() async throws
}

/// No-op default registered when no hardware is paired. Every mutation
/// fails with `.notPaired` so the Pos UI can show the glass "Pair a
/// printer" banner instead of silently succeeding.
public final class NullReceiptPrinter: ReceiptPrinter, @unchecked Sendable {
    public init() {}

    public func isAvailable() -> Bool { false }

    public func printReceipt(_ payload: ReceiptPayload) async throws {
        AppLog.hardware.info("NullReceiptPrinter.printReceipt: no printer paired (\(payload.lines.count) lines)")
        throw ReceiptPrinterError.notPaired
    }

    public func openCashDrawer() async throws {
        AppLog.hardware.info("NullReceiptPrinter.openCashDrawer: no printer paired")
        throw ReceiptPrinterError.notPaired
    }
}
