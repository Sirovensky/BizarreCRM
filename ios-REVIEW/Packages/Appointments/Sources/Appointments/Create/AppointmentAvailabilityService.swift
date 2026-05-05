import Foundation
import Networking

// MARK: - §10.8 Appointment Availability Service
//
// Pure service — no I/O. Applies buffer-time padding and blackout-date filtering
// to raw server-provided AvailabilitySlots before they are shown in the
// slot picker grid.
//
// Consumed by AppointmentCreateFullViewModel (loadAvailability) and
// AppointmentSuggestView. The server already computes staff shifts ×
// resource capacity on the backend; this layer adds:
//   • Buffer padding: shrinks each slot by `bufferMinutes` so the next
//     appointment can't butt up against the previous.
//   • Blackout dates: drops any slot that falls within a tenant blackout window
//     (holidays, store closures).

// MARK: - Blackout Date

/// A period during which no appointments may be booked.
/// Server may return these as part of a tenant calendar settings response.
public struct AppointmentBlackoutDate: Codable, Sendable, Identifiable {
    public let id: Int64
    /// Label shown to staff (e.g. "Thanksgiving", "Store renovation")
    public let label: String
    public let start: Date
    public let end: Date

    public var formattedRange: String {
        let df = DateIntervalFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: start, to: end)
    }

    enum CodingKeys: String, CodingKey {
        case id, label
        case start = "start_date"
        case end   = "end_date"
    }

    public init(id: Int64, label: String, start: Date, end: Date) {
        self.id = id
        self.label = label
        self.start = start
        self.end = end
    }
}

// MARK: - Service

/// Pure helper — no side effects. Filters + pads server availability slots.
public enum AppointmentAvailabilityService: Sendable {

    // MARK: - Buffer

    /// Apply `bufferMinutes` padding to each slot.
    ///
    /// A buffer ensures back-to-back appointments have breathing room for
    /// cleanup, travel, etc. The buffer is subtracted from the *end* of each
    /// slot so the displayed duration equals `slot.duration − buffer`.
    ///
    /// - Parameters:
    ///   - slots:         Raw server-returned `AvailabilitySlot` values.
    ///   - bufferMinutes: Minutes of buffer to subtract from each slot's end.
    ///   - minDuration:   Minimum usable slot length in seconds. Slots shorter
    ///                    than this after buffering are dropped.
    /// - Returns: Filtered + padded `[AvailabilitySlot]`, sorted by `start`.
    public static func applyBuffer(
        to slots: [AvailabilitySlot],
        bufferMinutes: Int,
        minDuration: TimeInterval = 900  // 15 min
    ) -> [AvailabilitySlot] {
        guard bufferMinutes > 0 else { return slots }
        let bufferSeconds = TimeInterval(bufferMinutes * 60)
        let iso = ISO8601DateFormatter()

        return slots.compactMap { slot -> AvailabilitySlot? in
            guard
                let startDate = iso.date(from: slot.start),
                let endDate   = iso.date(from: slot.end)
            else { return nil }

            let paddedEnd = endDate.addingTimeInterval(-bufferSeconds)
            guard paddedEnd.timeIntervalSince(startDate) >= minDuration else { return nil }

            return AvailabilitySlot(start: slot.start, end: iso.string(from: paddedEnd))
        }
    }

    // MARK: - Blackout filter

    /// Remove any slots that overlap a blackout window.
    ///
    /// A slot is kept only when it does *not* intersect any blackout period.
    ///
    /// - Parameters:
    ///   - slots:    Source slots (may be pre-buffered or raw).
    ///   - blackouts: Tenant blackout windows (holidays, closures).
    /// - Returns: Slots that fall entirely outside all blackout windows.
    public static func filterBlackouts(
        slots: [AvailabilitySlot],
        blackouts: [AppointmentBlackoutDate]
    ) -> [AvailabilitySlot] {
        guard !blackouts.isEmpty else { return slots }
        let iso = ISO8601DateFormatter()

        return slots.filter { slot in
            guard
                let startDate = iso.date(from: slot.start),
                let endDate   = iso.date(from: slot.end)
            else { return false }

            // Keep the slot only if it doesn't intersect any blackout.
            return !blackouts.contains { blackout in
                startDate < blackout.end && endDate > blackout.start
            }
        }
    }

    // MARK: - Convenience

    /// Apply buffer and blackout filtering in one step.
    public static func process(
        slots: [AvailabilitySlot],
        bufferMinutes: Int,
        blackouts: [AppointmentBlackoutDate],
        minDuration: TimeInterval = 900
    ) -> [AvailabilitySlot] {
        let buffered = applyBuffer(to: slots, bufferMinutes: bufferMinutes, minDuration: minDuration)
        return filterBlackouts(slots: buffered, blackouts: blackouts)
    }

    // MARK: - Blackout check

    /// Returns `true` when the given `date` falls within any blackout window.
    /// Useful to grey out calendar days before loading per-day slot details.
    public static func isBlackedOut(_ date: Date, blackouts: [AppointmentBlackoutDate]) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        // Normalize to start-of-day for whole-day comparisons.
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }

        return blackouts.contains { blackout in
            dayStart < blackout.end && dayEnd > blackout.start
        }
    }
}

// MARK: - APIClient extension (§10.8 Blackout Dates)

public extension APIClient {

    /// GET /api/v1/appointments/blackout-dates
    ///
    /// Returns tenant blackout windows (holidays, closures). The server may
    /// return an empty array if no blackout management has been configured;
    /// callers treat this as "no restrictions."
    func listAppointmentBlackoutDates() async throws -> [AppointmentBlackoutDate] {
        return try await get(
            "/api/v1/appointments/blackout-dates",
            as: [AppointmentBlackoutDate].self
        )
    }
}
