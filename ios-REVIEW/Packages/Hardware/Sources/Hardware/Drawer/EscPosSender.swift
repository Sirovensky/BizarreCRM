import Foundation

// MARK: - EscPosSender

/// Minimal protocol abstracting the byte-send capability of an ESC/POS transport.
///
/// During parallel development the sibling agent owns `Hardware/Printing/EscPosNetworkEngine`.
/// To avoid a compile dependency on files that may not exist yet, `EscPosDrawerKick`
/// depends on this protocol instead of the concrete engine.
///
/// **Wire-up note (for the Printing agent or App-layer integrator):**
/// When `EscPosNetworkEngine` lands, add a conformance extension:
/// ```swift
/// extension EscPosNetworkEngine: EscPosSender {}
/// ```
/// Then register `EscPosDrawerKick(sender: EscPosNetworkEngine.shared)` in
/// `Container+Registrations.swift`.
public protocol EscPosSender: Sendable {
    /// Send raw bytes to the ESC/POS endpoint (printer socket or MFi stream).
    func sendBytes(_ bytes: [UInt8]) async throws
    /// `true` when the transport is live and can accept bytes.
    var isConnected: Bool { get }
}
