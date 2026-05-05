import Foundation

// MARK: - CashDrawerError

public enum CashDrawerError: Error, LocalizedError, Sendable {
    case notConnected
    case kickFailed(String)
    case printerRequired

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Cash drawer is not connected. Pair a receipt printer with a drawer port in Settings → Hardware."
        case .kickFailed(let detail):
            return "Failed to open drawer: \(detail)"
        case .printerRequired:
            return "A receipt printer must be connected to trigger the cash drawer."
        }
    }
}

// MARK: - CashDrawer Protocol

/// Abstract contract for opening a physical cash drawer.
///
/// Concrete implementations:
/// - `EscPosDrawerKick` — ESC/POS command over receipt printer (primary path).
/// - `NetworkDrawerKick` — direct TCP send for networked drawer kickers (fallback).
/// - `NullCashDrawer` — no-op stub when no hardware is paired.
public protocol CashDrawer: Sendable {
    /// Open the drawer. Throws on failure.
    func open() async throws
    /// Returns `true` when the underlying transport is available.
    var isConnected: Bool { get }
}

// MARK: - NullCashDrawer

/// Stub returned when no printer / drawer is paired.
public struct NullCashDrawer: CashDrawer {
    public init() {}
    public var isConnected: Bool { false }
    public func open() async throws {
        throw CashDrawerError.notConnected
    }
}
