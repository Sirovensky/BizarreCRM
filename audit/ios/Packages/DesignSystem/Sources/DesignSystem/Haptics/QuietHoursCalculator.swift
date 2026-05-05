import Foundation

// §66 — QuietHoursCalculator
// Pure, dependency-free calculation of whether haptics/sounds should be
// suppressed for the given time. Tested at ≥80% coverage.

// MARK: - QuietHoursCalculator

/// Determines whether haptic/sound output should be suppressed for a given `Date`.
///
/// All methods are pure (no side effects, no shared state) so they are trivially
/// testable and safe to call from any concurrency domain.
///
/// ## Quiet-hours logic
/// The window `[quietStart, quietEnd)` may span midnight. For example,
/// `start=21, end=7` means "quiet from 9 pm tonight until 7 am tomorrow."
///
/// When `start == end`, quiet hours are treated as disabled (24-hour window
/// that wraps to zero length is nonsensical).
public enum QuietHoursCalculator: Sendable {

    // MARK: - Primary API

    /// Returns `true` if output should be suppressed for `date`.
    ///
    /// - Parameters:
    ///   - date: The current date/time to evaluate. Defaults to `Date()`.
    ///   - quietStart: Hour-of-day (0–23) when quiet period begins.
    ///   - quietEnd:   Hour-of-day (0–23) when quiet period ends.
    ///   - exceptCritical: When `true`, the caller is about to produce a
    ///     critical event and quiet-hours suppression is lifted. The caller
    ///     must decide independently whether its event qualifies as critical.
    /// - Returns: `true` → suppress output; `false` → allow output.
    public static func shouldSuppress(
        at date: Date,
        quietStart: Int,
        quietEnd: Int,
        exceptCritical: Bool
    ) -> Bool {
        if exceptCritical { return false }

        // Equal start/end → no window defined → never suppress.
        guard quietStart != quietEnd else { return false }

        let hour = hourOfDay(from: date)
        return isWithinQuietWindow(hour: hour, start: quietStart, end: quietEnd)
    }

    // MARK: - Internal helpers (internal so tests can reach them)

    /// Returns the hour-of-day component (0–23) in the current calendar.
    static func hourOfDay(from date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    /// Returns `true` if `hour` falls within the `[start, end)` quiet window.
    ///
    /// Handles overnight wrapping, e.g. start=21, end=7.
    static func isWithinQuietWindow(hour: Int, start: Int, end: Int) -> Bool {
        // Validate inputs
        guard (0...23).contains(start), (0...23).contains(end), start != end else {
            return false
        }

        if start < end {
            // Same-day window, e.g. 9:00 → 17:00
            return hour >= start && hour < end
        } else {
            // Overnight window, e.g. 21:00 → 07:00
            return hour >= start || hour < end
        }
    }
}
