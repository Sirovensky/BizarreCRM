import Foundation
import Observation

// MARK: - BreakDurationTracker

/// @Observable that tracks the currently active break and its elapsed time.
///
/// Designed to be driven by a timer in the view layer (e.g. a 30-second
/// `.onReceive(timer)` in `BreakInOutView`). No timers are started here —
/// this keeps the VM platform-agnostic for testing.
///
/// Swift 6 Sendable: all mutable state is confined to @MainActor.
@MainActor
@Observable
public final class BreakDurationTracker {

    // MARK: - State

    public enum BreakState: Sendable, Equatable {
        case idle
        case onBreak(BreakEntry)
        case failed(String)
    }

    public private(set) var breakState: BreakState = .idle
    /// Elapsed seconds since break started; 0 when idle.
    public private(set) var elapsedSeconds: TimeInterval = 0

    // MARK: - Dependencies

    @ObservationIgnored private let now: () -> Date

    // MARK: - Init

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Public API

    /// Called by the view layer when the server returns an active break.
    public func breakDidStart(_ entry: BreakEntry) {
        breakState = .onBreak(entry)
        updateElapsed(from: entry)
    }

    /// Called by the view layer when the server confirms break ended.
    public func breakDidEnd() {
        breakState = .idle
        elapsedSeconds = 0
    }

    /// Called when an error occurs in the parent view model.
    public func setFailed(_ message: String) {
        breakState = .failed(message)
    }

    /// Recalculate elapsed from the active break's `startAt` field.
    /// The view layer drives this on each timer tick.
    public func tick() {
        guard case let .onBreak(entry) = breakState else { return }
        updateElapsed(from: entry)
    }

    // MARK: - Formatting helpers

    /// Compact "14m" / "1h 2m" elapsed string for display.
    public static func formatElapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "< 1m" }
        let totalMinutes = Int(s) / 60
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    // MARK: - Private

    private func updateElapsed(from entry: BreakEntry) {
        // BUGHUNT-2026-05-18: same fix as ClockInOutViewModel and
        // EmployeeClockViewModel — default ISO8601DateFormatter options reject
        // millisecond-precision strings from Node Date.toISOString(), so this
        // returned nil on every real payload and pinned elapsedSeconds at 0.
        // The break elapsed badge then showed "< 1m" indefinitely no matter
        // how long the employee had been on break. Try fractional first,
        // then plain options as a fallback.
        guard let startDate = Self.parseIso(entry.startAt) else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = now().timeIntervalSince(startDate)
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
