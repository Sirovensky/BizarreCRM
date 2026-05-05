import Foundation
import Core
import Networking

// MARK: - PeerFeedbackFrequencyCap
//
// §46.5 — Max 1 feedback request per peer per quarter.
// Client-side enforcement using locally cached request timestamps.
// Server also enforces; client shows a clear message before attempting.
//
// Persistence: UserDefaults keyed by `"peerFeedback.lastRequest.\(fromId).\(toId)"`.
// Value: ISO-8601 date string of the last request sent.
//
// Quarter boundary: calendar-based (Q1 Jan–Mar, Q2 Apr–Jun, etc.).

public enum PeerFeedbackFrequencyCap {

    // MARK: - Public API

    /// Returns `nil` if sending is allowed, or a user-facing explanation string if capped.
    public static func checkCap(fromEmployeeId: String, toEmployeeId: String) -> String? {
        let key = defaultsKey(from: fromEmployeeId, to: toEmployeeId)
        guard
            let raw = UserDefaults.standard.string(forKey: key),
            let lastDate = ISO8601DateFormatter().date(from: raw)
        else {
            return nil  // No previous request → allowed.
        }
        if sameCalendarQuarter(lastDate, Date()) {
            let nextStart = nextQuarterStart(from: lastDate)
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            return "You already requested feedback from this colleague this quarter. You can request again after \(fmt.string(from: nextStart))."
        }
        return nil  // Different quarter → allowed.
    }

    /// Record that a request was sent now. Call on successful submission.
    public static func recordRequest(fromEmployeeId: String, toEmployeeId: String) {
        let key = defaultsKey(from: fromEmployeeId, to: toEmployeeId)
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: key)
    }

    // MARK: - Private helpers

    private static func defaultsKey(from: String, to: String) -> String {
        "peerFeedback.lastRequest.\(from).\(to)"
    }

    /// Two dates are in the same calendar quarter if they share year + quarter.
    static func sameCalendarQuarter(_ a: Date, _ b: Date) -> Bool {
        let cal = Calendar.current
        let yearA  = cal.component(.year, from: a)
        let yearB  = cal.component(.year, from: b)
        guard yearA == yearB else { return false }
        let quarterA = (cal.component(.month, from: a) - 1) / 3
        let quarterB = (cal.component(.month, from: b) - 1) / 3
        return quarterA == quarterB
    }

    /// Returns the first day of the quarter following `date`.
    static func nextQuarterStart(from date: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        let month = cal.component(.month, from: date)
        let year  = cal.component(.year, from: date)
        let currentQuarter = (month - 1) / 3
        let nextQuarterMonth = (currentQuarter + 1) * 3 + 1  // 1-based
        var comps = DateComponents()
        if nextQuarterMonth > 12 {
            comps.year  = year + 1
            comps.month = 1
        } else {
            comps.year  = year
            comps.month = nextQuarterMonth
        }
        comps.day = 1
        return cal.date(from: comps) ?? date
    }
}
