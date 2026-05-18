import Foundation
import Core

// MARK: - EscPosDrawerKick

/// Opens a cash drawer via the ESC/POS "Execute pulse" command (ESC p m t1 t2).
///
/// The drawer physically connects to the receipt printer's RJ-11 "cash drawer" port.
/// The printer relays the pulse when it receives the command sequence over whatever
/// transport (LAN, BT, USB) was used to connect the printer.
///
/// Command bytes (5 bytes total):
/// ```
/// ESC  p   m    t1   t2
/// 0x1B 0x70 0x00 0x19 0xFA
/// ```
/// - `m` = drawer number: 0 = drawer 1 (pin 2), 1 = drawer 2 (pin 5)
/// - `t1` = on-time in 2ms units: 0x19 = 50ms (Star/Epson typical)
/// - `t2` = off-time in 2ms units: 0xFA = 500ms
///
/// References:
/// - Star Micronics ESC/POS Command Specifications, §8 Cash Drawer Control
/// - Epson ESC/POS Application Programming Guide Rev. 1.12
public final class EscPosDrawerKick: CashDrawer, @unchecked Sendable {

    // MARK: - Command constants

    /// ESC character.
    public static let esc: UInt8 = 0x1B
    /// 'p' character — kick command identifier.
    public static let cmdP: UInt8 = 0x70
    /// Drawer 1 (pin 2).
    public static let drawer1: UInt8 = 0x00
    /// Drawer 2 (pin 5).
    public static let drawer2: UInt8 = 0x01
    /// On-time: 50 ms (0x19 × 2 ms).
    public static let defaultOnTime: UInt8 = 0x19
    /// Off-time: 500 ms (0xFA × 2 ms).
    public static let defaultOffTime: UInt8 = 0xFA

    /// The 5-byte kick command for drawer 1 with default timings.
    public static let kickCommand: [UInt8] = [esc, cmdP, drawer1, defaultOnTime, defaultOffTime]

    // MARK: - Dependencies

    private let sender: any EscPosSender
    private let drawerPin: UInt8
    private let onTime: UInt8
    private let offTime: UInt8

    // MARK: - Init

    /// - Parameters:
    ///   - sender: Transport that delivers raw bytes to the printer.
    ///   - drawerPin: `0x00` for drawer 1 (default), `0x01` for drawer 2.
    ///   - onTime: Pulse on-time in 2ms units. Default 0x19 = 50ms.
    ///   - offTime: Pulse off-time in 2ms units. Default 0xFA = 500ms.
    public init(
        sender: any EscPosSender,
        drawerPin: UInt8 = 0x00,
        onTime: UInt8 = 0x19,
        offTime: UInt8 = 0xFA
    ) {
        self.sender = sender
        self.drawerPin = drawerPin
        self.onTime = onTime
        self.offTime = offTime
    }

    // MARK: - CashDrawer

    public var isConnected: Bool { sender.isConnected }

    public func open() async throws {
        guard sender.isConnected else {
            throw CashDrawerError.printerRequired
        }
        let command: [UInt8] = [Self.esc, Self.cmdP, drawerPin, onTime, offTime]
        AppLog.hardware.info("EscPosDrawerKick: sending kick command [\(command.map { String(format: "0x%02X", $0) }.joined(separator: " "))]")
        do {
            try await sender.sendBytes(command)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: previously the catch wrapped every error as
            // `kickFailed("Task was cancelled")`, which `CashDrawerManager`
            // stamped onto `status = .warning("Failed to open: Task was
            // cancelled")` and `errorMessage`. That permanent fake-failure
            // banner persisted even after the next successful kick because
            // the manager only clears errorMessage at the *start* of the next
            // attempt — leaving a "Failed to open" alert under a cash-tender
            // sale that actually printed and kicked fine. Re-throw cancellation
            // unchanged so the manager's `AppError.isCancellation` branch (if
            // any) skips the warning.
            throw e
        } catch {
            throw CashDrawerError.kickFailed(error.localizedDescription)
        }
    }

    /// Build the raw kick bytes for inspection or logging (pure, no side effects).
    public func buildKickBytes() -> [UInt8] {
        [Self.esc, Self.cmdP, drawerPin, onTime, offTime]
    }
}
