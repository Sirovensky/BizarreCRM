#if canImport(UIKit)
import Foundation
import Observation
import Core

// MARK: - CashDrawerManager
//
// §17 Cash drawer sub-tasks:
//  - Fire on specific tenders (cash / checks).
//  - Manager override: open drawer without sale (reconciliation) — requires PIN.
//  - Manager override: PIN + audit log.
//  - Surface open/closed status where drawer reports via printer bus.
//  - Warn if drawer left open > 5 minutes.
//  - Log drawer-open events with cashier + time.
//  - Anti-theft: multiple opens without sale → alert.
//
// Architecture: @Observable MainActor wrapper around the low-level `CashDrawer`
// protocol. Holds a timer to detect "drawer open too long" and a counter for
// anti-theft detection (opens-without-sale within a session).
//
// PIN gate: a manager PIN check is injected via `ManagerPinValidator` protocol
// so this class does not depend on the Auth package (avoiding cross-package refs).

// MARK: - Tender type that triggers drawer

/// The payment tender types that trigger an automatic drawer-kick.
public enum DrawerTriggerTender: String, Sendable, CaseIterable {
    case cash   = "Cash"
    case check  = "Check"
}

// MARK: - Drawer status

public enum CashDrawerStatus: Equatable, Sendable {
    case unknown
    case open
    case closed
    case warning(String)   // e.g. "Open > 5 min"
}

// MARK: - ManagerPinValidator protocol

/// Abstraction so Hardware doesn't import Auth.
public protocol ManagerPinValidator: Sendable {
    /// Returns `true` if the provided PIN is a valid manager PIN for the current tenant.
    func validate(pin: String) async -> Bool
}

// MARK: - CashDrawerAuditLogger protocol

/// Abstraction for logging drawer events without importing Networking.
public protocol CashDrawerAuditLogger: Sendable {
    /// Log that the drawer was opened.
    /// - Parameters:
    ///   - reason: Free-text reason (e.g. "Sale", "Manager override", "No-sale").
    ///   - cashierName: Staff member who triggered the open.
    func logDrawerOpen(reason: String, cashierName: String) async
}

// MARK: - CashDrawerManager

@Observable
@MainActor
public final class CashDrawerManager {

    // MARK: - Published state

    /// Current reported status of the drawer.
    public private(set) var status: CashDrawerStatus = .unknown
    /// Banner text when the anti-theft threshold is exceeded.
    public private(set) var antiTheftAlert: String?
    /// True while a manager-override PIN check is in flight.
    public private(set) var isPinValidating: Bool = false
    /// Non-nil when an operation fails.
    public private(set) var errorMessage: String?

    // MARK: - Configuration

    /// Tenders that automatically trigger a drawer kick.
    public var triggerTenders: Set<DrawerTriggerTender> = [.cash, .check]
    /// Anti-theft threshold: alert if this many opens occur without an intervening sale.
    public var antiTheftOpenLimit: Int = 3
    /// How long the drawer can remain open before showing a warning (default 5 min).
    public var openWarningDuration: TimeInterval = 5 * 60

    // MARK: - Private state

    private let drawer: any CashDrawer
    private let pinValidator: (any ManagerPinValidator)?
    private let auditLogger: (any CashDrawerAuditLogger)?

    /// Monotonic count of opens since last sale was recorded.
    private var opensSinceLastSale: Int = 0
    /// Timestamp when drawer was last opened.
    private var openedAt: Date?
    /// Async task for the open-too-long warning timer.
    private var warningTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        drawer: any CashDrawer,
        pinValidator: (any ManagerPinValidator)? = nil,
        auditLogger: (any CashDrawerAuditLogger)? = nil
    ) {
        self.drawer = drawer
        self.pinValidator = pinValidator
        self.auditLogger = auditLogger
    }

    // MARK: - Public API: tender-driven kick

    /// Call when a sale is tendered. Opens the drawer if the tender type is in the trigger set.
    /// - Parameters:
    ///   - tender: The payment method used.
    ///   - cashierName: Name of the cashier for the audit log.
    public func handleTender(_ tender: DrawerTriggerTender, cashierName: String = "Cashier") async {
        guard triggerTenders.contains(tender) else { return }
        await openDrawer(reason: tender.rawValue + " sale", cashierName: cashierName, recordAsSale: true)
    }

    /// Call when a sale completes (without a drawer kick) to reset the anti-theft counter.
    public func recordSaleCompleted() {
        opensSinceLastSale = 0
    }

    // MARK: - Public API: manager override

    /// Opens the drawer without a sale after validating a manager PIN.
    ///
    /// - Parameters:
    ///   - pin: The manager PIN entered by staff.
    ///   - cashierName: Name of the manager performing the override.
    /// - Returns: `true` if the PIN was valid and the drawer was kicked.
    @discardableResult
    public func managerOverride(pin: String, cashierName: String = "Manager") async -> Bool {
        guard let validator = pinValidator else {
            // No PIN validator configured — allow in debug; deny in release.
#if DEBUG
            AppLog.hardware.warning("CashDrawerManager: no PIN validator configured — allowing override in DEBUG")
#else
            errorMessage = "Manager PIN validation is not configured. Contact your system administrator."
            return false
#endif
            await openDrawer(reason: "Manager no-sale override (no PIN gate)", cashierName: cashierName, recordAsSale: false)
            return true
        }
        isPinValidating = true
        defer { isPinValidating = false }
        let valid = await validator.validate(pin: pin)
        guard valid else {
            errorMessage = "Incorrect PIN. Manager override denied."
            AppLog.hardware.warning("CashDrawerManager: manager PIN rejected")
            return false
        }
        await openDrawer(reason: "Manager no-sale override", cashierName: cashierName, recordAsSale: false)
        return true
    }

    // MARK: - Public API: status polling

    /// Marks the drawer status as closed (call when drawer emits a close signal or on POS settle).
    public func markClosed() {
        status = .closed
        warningTask?.cancel()
        warningTask = nil
        openedAt = nil
    }

    // MARK: - Private: core open

    private func openDrawer(reason: String, cashierName: String, recordAsSale: Bool) async {
        errorMessage = nil
        do {
            try await drawer.open()
            let now = Date()
            openedAt = now
            status = .open

            if recordAsSale {
                opensSinceLastSale = 0
            } else {
                opensSinceLastSale += 1
                checkAntiTheft()
            }

            // Audit log
            await auditLogger?.logDrawerOpen(reason: reason, cashierName: cashierName)
            AppLog.hardware.info("CashDrawerManager: drawer opened — reason=\(reason, privacy: .public) cashier=\(cashierName, privacy: .private)")

            // Start open-too-long timer
            startWarningTimer()

        } catch {
            status = .warning("Failed to open: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            AppLog.hardware.error("CashDrawerManager: failed to open drawer — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Warning timer (drawer open > openWarningDuration)

    private func startWarningTimer() {
        warningTask?.cancel()
        let duration = openWarningDuration
        warningTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if case .open = self.status {
                    let minutes = Int(duration / 60)
                    self.status = .warning("Drawer open > \(minutes) min — please close")
                    AppLog.hardware.warning("CashDrawerManager: drawer left open > \(minutes) minutes")
                }
            }
        }
    }

    // MARK: - Anti-theft check

    private func checkAntiTheft() {
        guard opensSinceLastSale >= antiTheftOpenLimit else {
            antiTheftAlert = nil
            return
        }
        let msg = "Alert: drawer opened \(opensSinceLastSale) times without a recorded sale. Possible unauthorized access."
        antiTheftAlert = msg
        AppLog.hardware.error("CashDrawerManager: anti-theft threshold exceeded — \(opensSinceLastSale) no-sale opens")
    }
}

// MARK: - NullCashDrawerAuditLogger

/// No-op logger used when no audit backend is wired.
public struct NullCashDrawerAuditLogger: CashDrawerAuditLogger {
    public init() {}
    public func logDrawerOpen(reason: String, cashierName: String) async {}
}

#endif
