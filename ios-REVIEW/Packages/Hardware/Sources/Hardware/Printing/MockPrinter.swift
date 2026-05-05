import Foundation
import Core

// MARK: - MockPrinter
//
// Controllable in-process `ReceiptPrinter` for unit tests and SwiftUI previews.
// Production containers must NOT register this — it belongs in test targets and
// #if DEBUG preview scaffolding only.
//
// Usage in tests:
// ```swift
// let mock = MockPrinter()
// // Simulate success:
// let printer: ReceiptPrinter = mock
// try await printer.printReceipt(payload)   // succeeds; mock.printedPayloads.last == payload
// // Simulate failure:
// mock.printError = ReceiptPrinterError.printFailed("paper jam")
// do { try await printer.printReceipt(payload) } catch { ... }
// ```

public final class MockPrinter: ReceiptPrinter, @unchecked Sendable {

    // MARK: - Configuration (set before calling)

    /// When non-nil, `printReceipt(_:)` throws this error.
    public var printError: Error?

    /// When non-nil, `openCashDrawer()` throws this error.
    public var drawerError: Error?

    /// When `false`, `isAvailable()` returns false.
    public var available: Bool

    // MARK: - Captured calls

    /// Every payload passed to `printReceipt(_:)` in order.
    public private(set) var printedPayloads: [ReceiptPayload] = []

    /// Number of times `openCashDrawer()` was called (regardless of outcome).
    public private(set) var drawerKickCount: Int = 0

    // MARK: - Init

    public init(available: Bool = true) {
        self.available = available
    }

    // MARK: - ReceiptPrinter

    public func isAvailable() -> Bool { available }

    public func printReceipt(_ payload: ReceiptPayload) async throws {
        if let error = printError { throw error }
        printedPayloads.append(payload)
        AppLog.hardware.debug("MockPrinter.printReceipt: captured receipt \(payload.receiptNumber, privacy: .public)")
    }

    public func openCashDrawer() async throws {
        drawerKickCount += 1
        if let error = drawerError { throw error }
        AppLog.hardware.debug("MockPrinter.openCashDrawer: kick #\(self.drawerKickCount)")
    }

    // MARK: - Reset helper

    /// Clear captured state between tests.
    public func reset() {
        printError = nil
        drawerError = nil
        available = true
        printedPayloads = []
        drawerKickCount = 0
    }
}
