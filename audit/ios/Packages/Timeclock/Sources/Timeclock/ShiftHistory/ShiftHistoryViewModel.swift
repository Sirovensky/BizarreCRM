import Foundation
import Observation
import Networking
import Core

/// §14 Phase 4 — ViewModel for the shift history list.
///
/// Loads clock entries from `GET /api/v1/employees/:id/hours`.
/// Applies a client-side day filter so "today" can be highlighted.
/// Injectable `userIdProvider` and `now` for deterministic testing.
@MainActor
@Observable
public final class ShiftHistoryViewModel {

    // MARK: - State

    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var entries: [ClockEntry] = []
    public private(set) var totalHours: Double = 0

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public var userIdProvider: @Sendable () async -> Int64
    /// Injectable clock; defaults to `Date()`.
    @ObservationIgnored var now: () -> Date

    // MARK: - Init

    public init(
        api: APIClient,
        userIdProvider: @escaping @Sendable () async -> Int64 = { 0 },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.userIdProvider = userIdProvider
        self.now = now
    }

    // MARK: - Public API

    /// Load the full clock-entry history (no date filter).
    public func loadAll() async {
        loadState = .loading
        let userId = await userIdProvider()
        do {
            let response = try await api.getHours(userId: userId)
            entries = response.entries
            totalHours = response.totalHours
            loadState = .loaded
        } catch {
            AppLog.ui.error("ShiftHistory loadAll failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Load entries for the current ISO week only (Mon–Sun UTC).
    public func loadCurrentWeek() async {
        loadState = .loading
        let userId = await userIdProvider()
        let (from, to) = currentWeekBounds()
        do {
            let response = try await api.getHours(userId: userId, fromDate: from, toDate: to)
            entries = response.entries
            totalHours = response.totalHours
            loadState = .loaded
        } catch {
            AppLog.ui.error("ShiftHistory loadCurrentWeek failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Computed helpers

    /// Entries whose `clock_in` falls on today's UTC calendar day.
    ///
    /// Uses UTC so the comparison is consistent regardless of the device time zone
    /// and the server-stored ISO-8601 UTC timestamps always map to the right day.
    public var todayEntries: [ClockEntry] {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let today = utcCal.startOfDay(for: now())
        let iso = ISO8601DateFormatter()
        return entries.filter { entry in
            guard let date = iso.date(from: entry.clockIn) else { return false }
            return utcCal.isDate(date, inSameDayAs: today)
        }
    }

    /// Historical entries (not today), ordered most-recent first.
    /// Uses UTC calendar day matching to mirror `todayEntries`.
    public var historicalEntries: [ClockEntry] {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let today = utcCal.startOfDay(for: now())
        let iso = ISO8601DateFormatter()
        return entries.filter { entry in
            guard let date = iso.date(from: entry.clockIn) else { return true }
            return !utcCal.isDate(date, inSameDayAs: today)
        }
    }

    // MARK: - Private

    private func currentWeekBounds() -> (from: String, to: String) {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let current = now()
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: current))!
        let endOfWeek = cal.date(byAdding: .day, value: 6, to: startOfWeek)!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!
        return (dateFormatter.string(from: startOfWeek), dateFormatter.string(from: endOfWeek))
    }
}
