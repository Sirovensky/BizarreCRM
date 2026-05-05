import Foundation

// MARK: - WaitlistMatcher

/// Pure helper — ranks waitlist candidates for an open slot.
/// No I/O, fully testable without mocks.
public enum WaitlistMatcher: Sendable {

    // MARK: - Public API

    /// Ranks `candidates` for `availableSlot` by:
    ///   1. Preference match — candidate has a preferred window that contains the slot.
    ///   2. Oldest-waiting — earlier `createdAt` wins ties.
    ///
    /// Only `.waiting` and `.offered` entries are considered.
    /// - Parameters:
    ///   - candidates:     Full list of waitlist entries.
    ///   - availableSlot:  Start of the open appointment slot.
    ///   - duration:       Length of the slot in seconds.
    /// - Returns: Ranked array, best match first.
    public static func rank(
        candidates: [WaitlistEntry],
        availableSlot: Date,
        duration: TimeInterval
    ) -> [WaitlistEntry] {
        let slotEnd = availableSlot.addingTimeInterval(duration)
        let eligible = candidates.filter { $0.status == .waiting || $0.status == .offered }

        return eligible.sorted { lhs, rhs in
            let lScore = preferenceScore(entry: lhs, slotStart: availableSlot, slotEnd: slotEnd)
            let rScore = preferenceScore(entry: rhs, slotStart: availableSlot, slotEnd: slotEnd)
            if lScore != rScore { return lScore > rScore }
            // Tie-break: oldest first
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Private

    /// Returns 1 if any preferred window overlaps the slot, 0 otherwise.
    private static func preferenceScore(
        entry: WaitlistEntry,
        slotStart: Date,
        slotEnd: Date
    ) -> Int {
        let matches = entry.preferredWindows.contains { window in
            window.start < slotEnd && window.end > slotStart
        }
        return matches ? 1 : 0
    }
}
