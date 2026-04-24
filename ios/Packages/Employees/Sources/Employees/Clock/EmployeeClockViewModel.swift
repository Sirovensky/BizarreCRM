import Foundation
import Observation
import Networking
import Core

/// §46 Phase 4 — Clock-in/out ViewModel for the Employees package.
///
/// Backs `EmployeeClockInOutView` (employee detail → clock actions).
/// Uses the same Networking DTOs (`ClockEntry`, `ClockStatus`) and
/// APIClient wrappers (`clockIn`, `clockOut`, `getClockStatus`) as
/// the standalone Timeclock package — no cross-package import required.
///
/// Thread-safety: `@MainActor` + `@Observable`; all mutations on main.
@MainActor
@Observable
public final class EmployeeClockViewModel {

    // MARK: - State

    public enum ClockState: Sendable, Equatable {
        /// Initial state before the first `refresh()` call.
        case idle
        /// Network request in flight.
        case loading
        /// Employee is not currently clocked in.
        case notClockedIn
        /// Employee is clocked in; carries the active entry.
        case clockedIn(ClockEntry)
        /// Last action failed; carries a user-visible message.
        case failed(String)
    }

    public private(set) var clockState: ClockState = .idle
    /// Elapsed seconds since clock-in; updated by `tickElapsed()`.
    public private(set) var elapsedSeconds: TimeInterval = 0

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: Int64
    /// Injectable clock for deterministic tests.
    @ObservationIgnored var now: () -> Date

    // MARK: - Init

    public init(
        api: APIClient,
        employeeId: Int64,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.employeeId = employeeId
        self.now = now
    }

    // MARK: - Public API

    /// Fetch current clock status from the server.
    /// Call from `.task {}` in the owning view.
    public func refresh() async {
        clockState = .loading
        do {
            let status = try await api.getClockStatus(userId: employeeId)
            applyStatus(status)
        } catch {
            AppLog.ui.error(
                "EmployeeClockViewModel refresh failed: \(error.localizedDescription, privacy: .public)"
            )
            clockState = .failed(error.localizedDescription)
        }
    }

    /// Clock in with the supplied PIN (may be empty if tenant has no PIN).
    public func clockIn(pin: String) async {
        clockState = .loading
        do {
            let entry = try await api.clockIn(userId: employeeId, pin: pin)
            clockState = .clockedIn(entry)
            updateElapsed(from: entry)
        } catch {
            AppLog.ui.error(
                "EmployeeClockViewModel clockIn failed: \(error.localizedDescription, privacy: .public)"
            )
            clockState = .failed(error.localizedDescription)
        }
    }

    /// Clock out with the supplied PIN.
    public func clockOut(pin: String) async {
        clockState = .loading
        do {
            _ = try await api.clockOut(userId: employeeId, pin: pin)
            clockState = .notClockedIn
            elapsedSeconds = 0
        } catch {
            AppLog.ui.error(
                "EmployeeClockViewModel clockOut failed: \(error.localizedDescription, privacy: .public)"
            )
            clockState = .failed(error.localizedDescription)
        }
    }

    /// Called from the 30-second timer in the view layer to keep
    /// the elapsed time display current.
    public func tickElapsed() {
        guard case let .clockedIn(entry) = clockState else { return }
        updateElapsed(from: entry)
    }

    // MARK: - Elapsed formatting

    /// Compact duration string: "< 1m" / "42m" / "2h 15m" / "1d 3h".
    public static func formatElapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 {
            return "< 1m"
        } else if s < 3_600 {
            return "\(Int(s) / 60)m"
        } else if s < 86_400 {
            let h = Int(s) / 3_600
            let m = (Int(s) % 3_600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            let d = Int(s) / 86_400
            let h = (Int(s) % 86_400) / 3_600
            return h > 0 ? "\(d)d \(h)h" : "\(d)d"
        }
    }

    // MARK: - Private helpers

    private func applyStatus(_ status: ClockStatus?) {
        guard let status else {
            // nil = 404 (employee not found or endpoint unavailable)
            clockState = .notClockedIn
            return
        }
        if status.isClockedIn, let entry = status.entry {
            clockState = .clockedIn(entry)
            updateElapsed(from: entry)
        } else {
            clockState = .notClockedIn
            elapsedSeconds = 0
        }
    }

    private func updateElapsed(from entry: ClockEntry) {
        guard let date = ISO8601DateFormatter().date(from: entry.clockIn) else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = now().timeIntervalSince(date)
    }
}
