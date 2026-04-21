import Foundation
import Observation
import Networking
import Core

/// §3.11 — View model for the Clock in/out Dashboard tile.
///
/// Owns the async state machine and elapsed-time formatter. Designed to be
/// platform-agnostic (no SwiftUI imports) so unit tests run without a host app.
///
/// TODO(auth/me): `userId` defaults to `0` — a placeholder until the
/// `/auth/me` endpoint is plumbed in iOS (pending §2.x). Replace with the
/// real authenticated user ID once that route lands.
@MainActor
@Observable
public final class ClockInOutViewModel {

    // MARK: - State

    public enum State: Sendable, Equatable {
        case loading
        case idle
        case active(ClockEntry)
        case failed(String)
    }

    public private(set) var state: State = .loading
    /// Live elapsed seconds from clock-in; updated every 30 s (or on refresh).
    public private(set) var runningElapsed: TimeInterval = 0

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let userId: Int64
    /// Injectable clock for deterministic tests. Defaults to `Date.now`.
    @ObservationIgnored var now: () -> Date

    // MARK: - Init

    public init(
        api: APIClient,
        userId: Int64 = 0,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.userId = userId
        self.now = now
    }

    // MARK: - Public API

    /// Fetch the current clock status from the server. Call from `.task { }`.
    public func refresh() async {
        do {
            let status = try await api.getClockStatus(userId: userId)
            if let status {
                if status.isClockedIn, let entry = status.entry {
                    state = .active(entry)
                    updateElapsed(from: entry)
                } else {
                    state = .idle
                    runningElapsed = 0
                }
            } else {
                // nil → server returned 404; surface as idle so the tile
                // stays usable while the endpoint is unavailable.
                state = .idle
            }
        } catch {
            AppLog.ui.error("Timeclock refresh failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Attempt to clock in with the provided PIN (may be empty if tenant
    /// doesn't require a PIN — the server validates and returns 401 if wrong).
    public func clockIn(pin: String) async {
        state = .loading
        do {
            let entry = try await api.clockIn(userId: userId, pin: pin)
            state = .active(entry)
            updateElapsed(from: entry)
        } catch {
            AppLog.ui.error("Clock-in failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Attempt to clock out with the provided PIN.
    public func clockOut(pin: String) async {
        state = .loading
        do {
            _ = try await api.clockOut(userId: userId, pin: pin)
            state = .idle
            runningElapsed = 0
        } catch {
            AppLog.ui.error("Clock-out failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Recalculate elapsed from the active entry's `clockIn` string.
    /// Called on 30-second timer ticks from the view layer.
    public func tickElapsed() {
        guard case let .active(entry) = state else { return }
        updateElapsed(from: entry)
    }

    // MARK: - Elapsed formatting

    /// Compact "1h 23m" form. Exposed `public` so tests exercise it directly.
    ///
    /// Buckets:
    /// - < 60 s  → "< 1m"
    /// - < 1 h   → "42m"
    /// - < 24 h  → "1h 23m"
    /// - ≥ 24 h  → "2d 3h"
    public static func formatElapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 {
            return "< 1m"
        } else if s < 3600 {
            let m = Int(s) / 60
            return "\(m)m"
        } else if s < 86400 {
            let h = Int(s) / 3600
            let m = (Int(s) % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            let d = Int(s) / 86400
            let h = (Int(s) % 86400) / 3600
            return h > 0 ? "\(d)d \(h)h" : "\(d)d"
        }
    }

    // MARK: - Private

    private func updateElapsed(from entry: ClockEntry) {
        guard let date = ISO8601DateFormatter().date(from: entry.clockIn) else {
            runningElapsed = 0
            return
        }
        runningElapsed = now().timeIntervalSince(date)
    }
}
