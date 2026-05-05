import Foundation

// MARK: - DigestCadence

/// How often the digest fires.
/// Stored as a stable raw value for persistence.
public enum DigestCadence: String, Sendable, CaseIterable, Codable, Identifiable {
    case off        = "off"
    case hourly     = "hourly"
    case threeDaily = "3x_daily"
    case daily      = "daily"

    public var id: String { rawValue }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .off:        return "Off"
        case .hourly:     return "Hourly"
        case .threeDaily: return "3× Daily"
        case .daily:      return "Once Daily"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .off:        return "Digest disabled"
        case .hourly:     return "Digest sent every hour"
        case .threeDaily: return "Digest sent three times per day"
        case .daily:      return "Digest sent once per day"
        }
    }

    // MARK: - Fire times

    /// UTC hour offsets (from midnight) at which each cadence fires.
    /// Callers should map these through the user's calendar/timezone.
    public var fireHours: [Int] {
        switch self {
        case .off:        return []
        case .hourly:     return Array(0..<24)
        case .threeDaily: return [8, 13, 18]
        case .daily:      return [9]
        }
    }

    /// Returns `true` if the cadence produces at least one fire.
    public var isActive: Bool { self != .off }
}

// MARK: - QuietHoursConfig

/// An inclusive window during which digest delivery is suppressed.
/// Start and end are wall-clock hours (0–23).
/// If `start > end` the window wraps midnight (e.g. 22–06).
public struct QuietHoursConfig: Sendable, Codable, Equatable {

    /// Start of quiet window, hour component (0–23).
    public let startHour: Int
    /// End of quiet window, hour component (0–23).
    public let endHour: Int
    /// Whether quiet-hours suppression is active.
    public let isEnabled: Bool

    public init(startHour: Int, endHour: Int, isEnabled: Bool = true) {
        self.startHour = max(0, min(23, startHour))
        self.endHour   = max(0, min(23, endHour))
        self.isEnabled = isEnabled
    }

    /// Sensible default: 10 PM–7 AM.
    public static let defaultNight = QuietHoursConfig(startHour: 22, endHour: 7)

    // MARK: - Query

    /// Returns `true` if the given hour falls inside the quiet window.
    public func isSuppressed(hour: Int) -> Bool {
        guard isEnabled else { return false }
        let h = max(0, min(23, hour))
        if startHour <= endHour {
            // Normal window e.g. 09–17
            return h >= startHour && h <= endHour
        } else {
            // Wrap-midnight window e.g. 22–06
            return h >= startHour || h <= endHour
        }
    }

    // MARK: - Copy-on-write helpers

    public func withStartHour(_ hour: Int) -> QuietHoursConfig {
        QuietHoursConfig(startHour: hour, endHour: endHour, isEnabled: isEnabled)
    }

    public func withEndHour(_ hour: Int) -> QuietHoursConfig {
        QuietHoursConfig(startHour: startHour, endHour: hour, isEnabled: isEnabled)
    }

    public func withEnabled(_ enabled: Bool) -> QuietHoursConfig {
        QuietHoursConfig(startHour: startHour, endHour: endHour, isEnabled: enabled)
    }

    // MARK: - Display

    public var displayString: String {
        let fmt = { (h: Int) -> String in
            let ampm = h < 12 ? "AM" : "PM"
            let hr   = h == 0 ? 12 : (h > 12 ? h - 12 : h)
            return "\(hr) \(ampm)"
        }
        return "\(fmt(startHour)) – \(fmt(endHour))"
    }
}

// MARK: - DigestScheduleConfig

/// Combines cadence + quiet-hours into a single immutable config value.
/// All mutations return a new copy — no in-place mutation.
public struct DigestScheduleConfig: Sendable, Codable, Equatable {

    public let cadence: DigestCadence
    public let quietHours: QuietHoursConfig

    public init(
        cadence: DigestCadence = .daily,
        quietHours: QuietHoursConfig = .defaultNight
    ) {
        self.cadence = cadence
        self.quietHours = quietHours
    }

    // MARK: - Copy-on-write helpers

    public func withCadence(_ cadence: DigestCadence) -> DigestScheduleConfig {
        DigestScheduleConfig(cadence: cadence, quietHours: quietHours)
    }

    public func withQuietHours(_ quietHours: QuietHoursConfig) -> DigestScheduleConfig {
        DigestScheduleConfig(cadence: cadence, quietHours: quietHours)
    }

    // MARK: - Effective fire hours

    /// Fire hours after removing any suppressed by quiet-hours.
    public var effectiveFireHours: [Int] {
        cadence.fireHours.filter { !quietHours.isSuppressed(hour: $0) }
    }

    /// Next fire hour on or after `currentHour`, wrapping to the next day if needed.
    /// Returns `nil` when cadence is `.off` or all hours are suppressed.
    public func nextFireHour(after currentHour: Int) -> Int? {
        let hours = effectiveFireHours
        guard !hours.isEmpty else { return nil }
        let sorted = hours.sorted()
        return sorted.first(where: { $0 > currentHour }) ?? sorted.first
    }
}
