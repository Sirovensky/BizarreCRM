import Foundation
import Networking

// MARK: - §19 HoursRepository

/// Contract for persisting and fetching business hours + holiday exceptions.
public protocol HoursRepository: Sendable {
    func fetchHoursWeek() async throws -> BusinessHoursWeek
    func saveHoursWeek(_ week: BusinessHoursWeek) async throws -> BusinessHoursWeek
    func fetchHolidays() async throws -> [HolidayException]
    func createHoliday(_ holiday: HolidayException) async throws -> HolidayException
    func updateHoliday(_ holiday: HolidayException) async throws -> HolidayException
    func deleteHoliday(id: String) async throws
}

// MARK: - Live implementation

public final class LiveHoursRepository: HoursRepository {
    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchHoursWeek() async throws -> BusinessHoursWeek {
        try await api.fetchBusinessHours()
    }

    public func saveHoursWeek(_ week: BusinessHoursWeek) async throws -> BusinessHoursWeek {
        try await api.updateBusinessHours(week)
    }

    public func fetchHolidays() async throws -> [HolidayException] {
        try await api.fetchHolidays()
    }

    public func createHoliday(_ holiday: HolidayException) async throws -> HolidayException {
        try await api.createHoliday(holiday)
    }

    public func updateHoliday(_ holiday: HolidayException) async throws -> HolidayException {
        try await api.updateHoliday(holiday)
    }

    public func deleteHoliday(id: String) async throws {
        try await api.deleteHoliday(id: id)
    }
}
