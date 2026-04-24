import Foundation
import Networking

// MARK: - ShiftConflictDetector
//
// Pure, stateless functions that detect time-range overlaps between shifts
// for the same employee. No side effects; safe to call from any context.
//
// Overlap definition: two half-open intervals [a, b) and [c, d) overlap when
//   a < d  &&  c < b
// This matches the server's convention of inclusive start / exclusive end.

public enum ShiftConflictDetector {

    // MARK: - ConflictResult

    /// Describes a conflict found between a candidate shift and an existing one.
    public struct ConflictResult: Equatable, Sendable {
        /// The existing shift that the candidate clashes with.
        public let conflictingShift: Shift
        /// Human-readable summary suitable for display in UI.
        public let summary: String

        public init(conflictingShift: Shift, summary: String) {
            self.conflictingShift = conflictingShift
            self.summary = summary
        }
    }

    // MARK: - Public API

    /// Returns all existing shifts for `userId` that overlap with
    /// `[startAt, endAt)`. Ignores shifts whose `id` equals `excludingId`
    /// (use when editing an existing shift so it doesn't conflict with itself).
    ///
    /// - Parameters:
    ///   - startAt: Proposed shift start as an ISO-8601 string.
    ///   - endAt:   Proposed shift end as an ISO-8601 string.
    ///   - userId:  The employee whose calendar is checked.
    ///   - existing: The full roster of known shifts to check against.
    ///   - excludingId: Optional shift ID to skip (edit-in-place use case).
    /// - Returns: Ordered list of conflicts (may be empty).
    public static func conflicts(
        startAt: String,
        endAt: String,
        userId: Int64,
        in existing: [Shift],
        excludingId: Int64? = nil
    ) -> [ConflictResult] {
        guard
            let start = parseISO(startAt),
            let end   = parseISO(endAt),
            end > start
        else { return [] }

        return existing
            .filter { shift in
                shift.userId == userId &&
                shift.id != (excludingId ?? -1) &&
                shift.status != "cancelled"
            }
            .compactMap { shift -> ConflictResult? in
                guard
                    let existStart = parseISO(shift.startAt),
                    let existEnd   = parseISO(shift.endAt)
                else { return nil }

                // Half-open interval overlap: [start, end) ∩ [existStart, existEnd)
                guard start < existEnd && existStart < end else { return nil }

                let summary = conflictSummary(
                    candidate: (start, end),
                    existing: (existStart, existEnd),
                    shift: shift
                )
                return ConflictResult(conflictingShift: shift, summary: summary)
            }
    }

    /// Returns `true` if any overlap exists. Convenience wrapper around `conflicts(...)`.
    public static func hasConflict(
        startAt: String,
        endAt: String,
        userId: Int64,
        in existing: [Shift],
        excludingId: Int64? = nil
    ) -> Bool {
        !conflicts(startAt: startAt, endAt: endAt, userId: userId, in: existing, excludingId: excludingId).isEmpty
    }

    // MARK: - Private helpers

    private static func parseISO(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static func conflictSummary(
        candidate: (Date, Date),
        existing: (Date, Date),
        shift: Shift
    ) -> String {
        let name = shift.employeeDisplayName
        let start = timeFormatter.string(from: existing.0)
        let end   = timeFormatter.string(from: existing.1)
        return "\(name) already has a shift from \(start) to \(end)"
    }
}
