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
    /// §14.3: Verifies PIN against `/auth/verify-pin` before sending clock-in request.
    public func clockIn(pin: String) async {
        clockState = .loading
        do {
            // §14.3 PIN gate — skip verification if pin is empty (tenant has no PIN policy).
            if !pin.isEmpty {
                let valid = try await api.verifyPin(userId: employeeId, pin: pin)
                guard valid else {
                    clockState = .failed("Incorrect PIN. Please try again.")
                    return
                }
            }
            let entry = try await api.clockIn(userId: employeeId, pin: pin)
            clockState = .clockedIn(entry)
            updateElapsed(from: entry)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: cancellation may fire after the POST has
            // landed server-side. Painting "Clock-in failed" tempts the user
            // to retap, creating a duplicate clock-in row. Reconcile against
            // the server's truth instead of swallowing into .failed.
            await refresh()
        } catch {
            AppLog.ui.error(
                "EmployeeClockViewModel clockIn failed: \(error.localizedDescription, privacy: .public)"
            )
            clockState = .failed(error.localizedDescription)
        }
    }

    /// Clock out with the supplied PIN.
    /// §14.3: Verifies PIN against `/auth/verify-pin` before sending clock-out request.
    public func clockOut(pin: String) async {
        clockState = .loading
        do {
            if !pin.isEmpty {
                let valid = try await api.verifyPin(userId: employeeId, pin: pin)
                guard valid else {
                    clockState = .failed("Incorrect PIN. Please try again.")
                    // Restore clocked-in state so the UI doesn't drop the clock entry.
                    await refresh()
                    return
                }
            }
            _ = try await api.clockOut(userId: employeeId, pin: pin)
            clockState = .notClockedIn
            elapsedSeconds = 0
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: cancellation may fire after the POST has
            // landed. Painting "Clock-out failed" misleads the user into a
            // retap that would attempt a second clock-out. Refresh to let
            // the server be the source of truth.
            await refresh()
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
        // BUGHUNT-2026-05-18: ISO8601DateFormatter() default options reject
        // Node Date.toISOString() output (millisecond precision); the timer
        // displayed 0:00:00 on the clock-in tile even when the employee
        // had been clocked in for hours. Try fractional first, then plain.
        guard let date = Self.parseIso(entry.clockIn) else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = now().timeIntervalSince(date)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseIso(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? isoPlain.date(from: raw)
    }
}
