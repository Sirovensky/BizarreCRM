import Foundation
import Observation
import Networking
import Core

// MARK: - ShiftsViewModel
//
// Manages the weekly shift calendar.
//   GET    /api/v1/schedule/shifts  — load week
//   POST   /api/v1/schedule/shifts  — create shift
//   PATCH  /api/v1/schedule/shifts/:id — update shift
//   DELETE /api/v1/schedule/shifts/:id — delete shift
//
// The ViewModel is actor-isolated to @MainActor so all SwiftUI bindings
// observe mutations on the main thread.

@MainActor
@Observable
public final class ShiftsViewModel {

    // MARK: - State types

    public enum LoadState: Equatable, Sendable {
        case idle, loading, loaded, failed(String)
    }

    public enum WriteState: Equatable, Sendable {
        case idle, saving, saved, failed(String)
    }

    // MARK: - Published state

    public private(set) var loadState: LoadState = .idle
    public private(set) var writeState: WriteState = .idle
    public private(set) var shifts: [Shift] = []

    /// The ISO-8601 Monday date of the currently displayed week (yyyy-MM-dd'T'HH:mm:ssZ).
    public var weekStart: Date = ShiftsViewModel.currentWeekMonday()

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let calendar: Calendar

    // MARK: - Init

    public init(api: APIClient, calendar: Calendar = .autoupdatingCurrent) {
        self.api = api
        self.calendar = calendar
    }

    // MARK: - Load

    /// Loads all shifts for the week containing `weekStart`.
    public func loadWeek() async {
        loadState = .loading
        let (from, to) = weekBounds(for: weekStart)
        do {
            let result = try await api.listShifts(fromDate: iso(from), toDate: iso(to))
            shifts = result
            loadState = .loaded
        } catch {
            AppLog.ui.error("Shifts load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Navigation

    public func advanceWeek() {
        weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        Task { await loadWeek() }
    }

    public func retreatWeek() {
        weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        Task { await loadWeek() }
    }

    public func goToCurrentWeek() {
        weekStart = Self.currentWeekMonday(calendar: calendar)
        Task { await loadWeek() }
    }

    // MARK: - Create

    /// Creates a shift. Returns the created `Shift` on success.
    @discardableResult
    public func createShift(_ request: CreateShiftRequest) async -> Shift? {
        writeState = .saving
        do {
            let created = try await api.createShift(request)
            shifts = (shifts + [created]).sorted { $0.startAt < $1.startAt }
            writeState = .saved
            return created
        } catch {
            AppLog.ui.error("Shift create failed: \(error.localizedDescription, privacy: .public)")
            writeState = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Update

    /// Partially updates a shift. Returns the updated `Shift` on success.
    @discardableResult
    public func updateShift(id: Int64, _ request: UpdateShiftRequest) async -> Shift? {
        writeState = .saving
        do {
            let updated = try await api.updateShift(id: id, request)
            shifts = shifts.map { $0.id == id ? updated : $0 }
            writeState = .saved
            return updated
        } catch {
            AppLog.ui.error("Shift update failed: \(error.localizedDescription, privacy: .public)")
            writeState = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Delete

    public func deleteShift(id: Int64) async {
        writeState = .saving
        do {
            try await api.deleteShift(id: id)
            shifts = shifts.filter { $0.id != id }
            writeState = .saved
        } catch {
            AppLog.ui.error("Shift delete failed: \(error.localizedDescription, privacy: .public)")
            writeState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Conflict detection

    /// Returns conflicts for a proposed shift against the in-memory roster.
    public func conflicts(
        startAt: String,
        endAt: String,
        userId: Int64,
        excludingId: Int64? = nil
    ) -> [ShiftConflictDetector.ConflictResult] {
        ShiftConflictDetector.conflicts(
            startAt: startAt,
            endAt: endAt,
            userId: userId,
            in: shifts,
            excludingId: excludingId
        )
    }

    // MARK: - Computed helpers

    /// The 7 calendar days of the current week, starting from `weekStart`.
    public var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Shifts grouped by user ID, filtered to the current week.
    public var shiftsByEmployee: [Int64: [Shift]] {
        Dictionary(grouping: shifts, by: { $0.userId })
    }

    /// Shifts falling on `day` for `userId`, sorted by start time.
    public func shifts(for userId: Int64, on day: Date) -> [Shift] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return shifts
            .filter { $0.userId == userId }
            .filter { shift in
                guard let start = ISO8601DateFormatter().date(from: shift.startAt) else { return false }
                return start >= dayStart && start < dayEnd
            }
            .sorted { $0.startAt < $1.startAt }
    }

    // MARK: - Private helpers

    private static func currentWeekMonday(calendar: Calendar = .autoupdatingCurrent) -> Date {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2  // Monday
        return calendar.date(from: comps) ?? Date()
    }

    private func weekBounds(for monday: Date) -> (Date, Date) {
        let start = monday
        let end   = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        return (start, end)
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
