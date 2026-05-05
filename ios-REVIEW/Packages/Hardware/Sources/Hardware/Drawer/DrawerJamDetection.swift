#if canImport(UIKit)
import Foundation
import Core

// MARK: - DrawerJamDetection
//
// §17 Cash drawer — jam / stuck-drawer detection.
//
// A cash drawer "jam" is detected when:
//   (a) The drawer kick command was sent (ESC/POS opcode ACK'd by printer), AND
//   (b) The drawer status does not transition to `.open` within a configurable
//       deadline (default 3 s), AND
//   (c) The drawer is known to have a status-reporting path (i.e. not all
//       drawers report open/closed — see `CashDrawer.isConnected` semantics).
//
// Many entry-level drawers are "dumb" — they receive the kick and physically open,
// but provide no feedback signal. For those, jam detection falls back to watching
// whether the *next* sale's drawer kick also fails, at which point an advisory is
// raised. The `DrawerJamDetector` handles both cases via `DrawerSensingMode`.
//
// Architecture:
//   `DrawerJamDetector` is a lightweight class owned by `CashDrawerManager`.
//   It does not perform any I/O itself; `CashDrawerManager` calls
//   `recordKickSent()` and `recordStatusUpdate(_:)` after each relevant event.
//   `DrawerJamDetector` publishes `currentJamState` which `CashDrawerManager`
//   surfaces via its own `status` property.

// MARK: - DrawerSensingMode

/// Whether the drawer hardware reports open/closed status via the printer bus.
public enum DrawerSensingMode: String, Sendable {
    /// Drawer actively reports open/closed through the printer's status byte.
    /// The `DrawerJamDetector` can wait for the status to flip to `.open` and
    /// time out if it doesn't.
    case active
    /// Drawer is dumb — receives kick but sends no status feedback.
    /// Detection is advisory only: two consecutive kick failures within a shift
    /// are flagged.
    case advisory
}

// MARK: - DrawerJamState

/// The current jam assessment from `DrawerJamDetector`.
public enum DrawerJamState: Equatable, Sendable {
    /// No jam suspected.
    case clear
    /// Drawer kick sent but status didn't flip to open within the deadline (active mode).
    case suspected(detail: String)
    /// Two or more kicks in a row have not been followed by a successful sale
    /// (advisory mode) — manual inspection recommended.
    case advisory(openCount: Int)

    public var isJammed: Bool {
        switch self {
        case .clear:    return false
        default:        return true
        }
    }

    public var displayMessage: String {
        switch self {
        case .clear:
            return ""
        case .suspected(let detail):
            return "Drawer jam suspected — \(detail). Check for obstructions and try opening manually."
        case .advisory(let n):
            return "Drawer has not opened reliably (\(n) consecutive kick\(n == 1 ? "" : "s") without confirmation). Inspect for paper, coins, or debris."
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .clear:             return "Drawer operating normally"
        case .suspected(let d):  return "Drawer jam suspected: \(d)"
        case .advisory(let n):   return "Drawer advisory: \(n) unconfirmed kicks"
        }
    }
}

// MARK: - DrawerJamDetector

/// Lightweight jam detector owned by `CashDrawerManager`.
///
/// Usage:
/// ```swift
/// // After sending kick:
/// detector.recordKickSent()
///
/// // When status byte received from printer:
/// detector.recordStatusUpdate(isOpen: true)
///
/// // Read result:
/// print(detector.currentJamState)
/// ```
public final class DrawerJamDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// How long to wait for an open-status confirmation after a kick (active mode).
    public var openConfirmationDeadline: TimeInterval
    /// How many unconfirmed kicks in a row trigger an advisory (advisory mode).
    public var advisoryThreshold: Int
    /// The sensing capability of the paired drawer.
    public let sensingMode: DrawerSensingMode

    // MARK: - State

    private var lastKickTime: Date?
    private var consecutiveUnconfirmedKicks: Int = 0
    private var jamStateInternal: DrawerJamState = .clear
    private var confirmationTask: Task<Void, Never>?

    // MARK: - Published state

    /// The current jam assessment. Updated synchronously in advisory mode;
    /// updated by the confirmation task in active mode.
    public private(set) var currentJamState: DrawerJamState = .clear

    // Callback invoked on the calling queue when `currentJamState` changes.
    public var onJamStateChanged: ((DrawerJamState) -> Void)?

    // MARK: - Init

    public init(
        sensingMode: DrawerSensingMode = .advisory,
        openConfirmationDeadline: TimeInterval = 3,
        advisoryThreshold: Int = 2
    ) {
        self.sensingMode = sensingMode
        self.openConfirmationDeadline = openConfirmationDeadline
        self.advisoryThreshold = advisoryThreshold
    }

    // MARK: - Public API

    /// Call this immediately after sending a drawer-kick command to the printer.
    public func recordKickSent() {
        lastKickTime = Date()
        consecutiveUnconfirmedKicks += 1
        AppLog.hardware.info("DrawerJamDetector: kick recorded (unconfirmed=\(self.consecutiveUnconfirmedKicks))")

        switch sensingMode {
        case .active:
            startConfirmationTimer()
        case .advisory:
            checkAdvisoryThreshold()
        }
    }

    /// Call when the drawer status byte reports an open or closed state.
    /// - Parameter isOpen: `true` = drawer successfully opened.
    public func recordStatusUpdate(isOpen: Bool) {
        guard sensingMode == .active else { return }
        if isOpen {
            confirmationTask?.cancel()
            consecutiveUnconfirmedKicks = 0
            updateState(.clear)
            AppLog.hardware.info("DrawerJamDetector: open status confirmed — jam cleared")
        }
        // Closed-status while counting: wait for the deadline to fire.
    }

    /// Call when a sale completes successfully (drawer opened as expected).
    /// Clears the advisory counter.
    public func recordSuccessfulSale() {
        consecutiveUnconfirmedKicks = 0
        updateState(.clear)
        AppLog.hardware.info("DrawerJamDetector: successful sale — advisory counter reset")
    }

    /// Manually clear the jam state (e.g. after staff confirms drawer is free).
    public func manuallyResolveJam() {
        consecutiveUnconfirmedKicks = 0
        confirmationTask?.cancel()
        updateState(.clear)
        AppLog.hardware.info("DrawerJamDetector: jam manually resolved")
    }

    // MARK: - Private

    private func startConfirmationTimer() {
        confirmationTask?.cancel()
        let deadline = openConfirmationDeadline
        confirmationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
            } catch {
                return // cancelled — status confirmed before deadline
            }
            // If still not confirmed:
            let msg = "no open status within \(Int(deadline))s"
            AppLog.hardware.warning("DrawerJamDetector: suspected jam — \(msg, privacy: .public)")
            self.updateState(.suspected(detail: msg))
        }
    }

    private func checkAdvisoryThreshold() {
        if consecutiveUnconfirmedKicks >= advisoryThreshold {
            let n = consecutiveUnconfirmedKicks
            AppLog.hardware.warning("DrawerJamDetector: advisory threshold reached — \(n) unconfirmed kicks")
            updateState(.advisory(openCount: n))
        }
    }

    private func updateState(_ newState: DrawerJamState) {
        guard newState != currentJamState else { return }
        currentJamState = newState
        onJamStateChanged?(newState)
    }
}

#endif
