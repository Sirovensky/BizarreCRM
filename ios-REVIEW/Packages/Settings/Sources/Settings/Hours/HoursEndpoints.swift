import Foundation
import Networking

// MARK: - §19 Hours API endpoints

// MARK: Request / Response bodies

public struct HoursWeekResponse: Decodable, Sendable {
    public let hours: BusinessHoursWeek
    public init(hours: BusinessHoursWeek) { self.hours = hours }
}

public struct HolidaysResponse: Decodable, Sendable {
    public let holidays: [HolidayException]
    public init(holidays: [HolidayException]) { self.holidays = holidays }
}

public struct HolidayUpsertRequest: Encodable, Sendable {
    public let date: Date
    public let isOpen: Bool
    public let openAt: DateComponents?
    public let closeAt: DateComponents?
    public let reason: String
    public let recurring: String

    public init(holiday: HolidayException) {
        self.date = holiday.date
        self.isOpen = holiday.isOpen
        self.openAt = holiday.openAt
        self.closeAt = holiday.closeAt
        self.reason = holiday.reason
        self.recurring = holiday.recurring.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case date, reason, recurring
        case isOpen = "is_open"
        case openAt = "open_at"
        case closeAt = "close_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let iso = ISO8601DateFormatter()
        try c.encode(iso.string(from: date), forKey: .date)
        try c.encode(isOpen, forKey: .isOpen)
        try c.encode(reason, forKey: .reason)
        try c.encode(recurring, forKey: .recurring)
        if let openAt {
            try c.encodeIfPresent(timeString(from: openAt), forKey: .openAt)
        }
        if let closeAt {
            try c.encodeIfPresent(timeString(from: closeAt), forKey: .closeAt)
        }
    }

    private func timeString(from dc: DateComponents) -> String {
        String(format: "%02d:%02d", dc.hour ?? 0, dc.minute ?? 0)
    }
}

// MARK: - APIClient extension

public extension APIClient {

    // GET /tenant/hours
    func fetchBusinessHours() async throws -> BusinessHoursWeek {
        try await get("/tenant/hours", as: HoursWeekResponse.self).hours
    }

    // PATCH /tenant/hours
    @discardableResult
    func updateBusinessHours(_ week: BusinessHoursWeek) async throws -> BusinessHoursWeek {
        try await patch("/tenant/hours", body: week, as: HoursWeekResponse.self).hours
    }

    // GET /tenant/holidays
    func fetchHolidays() async throws -> [HolidayException] {
        try await get("/tenant/holidays", as: HolidaysResponse.self).holidays
    }

    // POST /tenant/holidays
    @discardableResult
    func createHoliday(_ holiday: HolidayException) async throws -> HolidayException {
        try await post("/tenant/holidays", body: HolidayUpsertRequest(holiday: holiday), as: HolidayException.self)
    }

    // PATCH /tenant/holidays/:id
    @discardableResult
    func updateHoliday(_ holiday: HolidayException) async throws -> HolidayException {
        try await patch("/tenant/holidays/\(holiday.id)", body: HolidayUpsertRequest(holiday: holiday), as: HolidayException.self)
    }

    // DELETE /tenant/holidays/:id
    func deleteHoliday(id: String) async throws {
        try await delete("/tenant/holidays/\(id)")
    }
}
