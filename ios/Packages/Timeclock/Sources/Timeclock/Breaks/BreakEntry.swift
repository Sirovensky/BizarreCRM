import Foundation

// MARK: - BreakKind

/// The category of a break. Server-authoritative; client displays only.
public enum BreakKind: String, Codable, Sendable, CaseIterable {
    case meal
    case rest
    case other
}

// MARK: - BreakEntry

/// A single break row within a shift.
///
/// - `duration` is computed from `startAt` / `endAt`; if the break is ongoing
///   `endAt` is `nil` and the caller should derive elapsed from the wall clock.
/// - Money is not relevant here; `paid` drives whether the break counts toward
///   billable hours (server authoritative).
/// - Minutes are stored as `Int` (whole minutes) matching the "hours in rational
///   minutes" architectural rule.
public struct BreakEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let employeeId: Int64
    public let shiftId: Int64
    /// ISO-8601 UTC string.
    public let startAt: String
    /// ISO-8601 UTC string; `nil` while break is in progress.
    public let endAt: String?
    public let kind: BreakKind
    /// Whether this break is paid time.
    public let paid: Bool

    /// Computed duration in whole minutes.
    /// Returns `nil` when the break is still ongoing (`endAt` is `nil`).
    ///
    /// BUGHUNT-2026-05-18: was `ISO8601DateFormatter()` with default options,
    /// which rejects both Node `Date.toISOString()` fractional strings AND
    /// SQLite's `YYYY-MM-DD HH:MM:SS` shape (see [[ios-iso-fractional-parser]]).
    /// Every server-returned break thus had `duration == nil`, so the timesheet
    /// row never showed paid-vs-unpaid break time.
    public var duration: Int? {
        guard let end = endAt,
              let startDate = ShiftTimestampParser.parse(startAt),
              let endDate = ShiftTimestampParser.parse(end)
        else { return nil }
        return max(0, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    public init(
        id: Int64,
        employeeId: Int64,
        shiftId: Int64,
        startAt: String,
        endAt: String? = nil,
        kind: BreakKind = .rest,
        paid: Bool = false
    ) {
        self.id = id
        self.employeeId = employeeId
        self.shiftId = shiftId
        self.startAt = startAt
        self.endAt = endAt
        self.kind = kind
        self.paid = paid
    }

    enum CodingKeys: String, CodingKey {
        case id
        case employeeId = "employee_id"
        case shiftId    = "shift_id"
        case startAt    = "start_at"
        case endAt      = "end_at"
        case kind
        case paid
    }
}
