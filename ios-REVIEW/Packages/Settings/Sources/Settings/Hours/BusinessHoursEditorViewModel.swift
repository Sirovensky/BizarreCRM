import Foundation
import Observation

// MARK: - §19 BusinessHoursEditorViewModel

@Observable
@MainActor
public final class BusinessHoursEditorViewModel {

    // MARK: - State

    public var week: BusinessHoursWeek = .defaultWeek
    public var isSaving: Bool = false
    public var errorMessage: String?
    public var saveSucceeded: Bool = false

    // MARK: - Dependencies

    private let repository: any HoursRepository
    public let timezone: TimeZone

    // MARK: - Init

    public init(repository: any HoursRepository, timezone: TimeZone = .current) {
        self.repository = repository
        self.timezone = timezone
    }

    // MARK: - Load

    public func load() async {
        do {
            week = try await repository.fetchHoursWeek()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Day mutations (immutable — always return new week)

    public func setOpen(_ isOpen: Bool, for weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: isOpen,
            openAt: isOpen ? (day.openAt ?? DateComponents(hour: 9, minute: 0)) : nil,
            closeAt: isOpen ? (day.closeAt ?? DateComponents(hour: 17, minute: 0)) : nil,
            breaks: day.breaks
        )
        week = week.updatingDay(updated)
    }

    public func setOpenTime(_ components: DateComponents, for weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: day.isOpen,
            openAt: components,
            closeAt: day.closeAt,
            breaks: day.breaks
        )
        week = week.updatingDay(updated)
    }

    public func setCloseTime(_ components: DateComponents, for weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: day.isOpen,
            openAt: day.openAt,
            closeAt: components,
            breaks: day.breaks
        )
        week = week.updatingDay(updated)
    }

    // MARK: - Break mutations

    public func addBreak(to weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let newBreak = TimeBreak(
            startAt: DateComponents(hour: 12, minute: 0),
            endAt: DateComponents(hour: 13, minute: 0),
            label: "Lunch"
        )
        var breaks = day.breaks ?? []
        breaks.append(newBreak)
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: day.isOpen,
            openAt: day.openAt,
            closeAt: day.closeAt,
            breaks: breaks
        )
        week = week.updatingDay(updated)
    }

    public func removeBreak(id: UUID, from weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let breaks = (day.breaks ?? []).filter { $0.id != id }
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: day.isOpen,
            openAt: day.openAt,
            closeAt: day.closeAt,
            breaks: breaks.isEmpty ? nil : breaks
        )
        week = week.updatingDay(updated)
    }

    public func updateBreakStart(_ components: DateComponents, id: UUID, weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let breaks = (day.breaks ?? []).map { br -> TimeBreak in
            guard br.id == id else { return br }
            return TimeBreak(id: br.id, startAt: components, endAt: br.endAt, label: br.label)
        }
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: day.isOpen,
            openAt: day.openAt,
            closeAt: day.closeAt,
            breaks: breaks
        )
        week = week.updatingDay(updated)
    }

    public func updateBreakEnd(_ components: DateComponents, id: UUID, weekday: Int) {
        guard let day = week.day(for: weekday) else { return }
        let breaks = (day.breaks ?? []).map { br -> TimeBreak in
            guard br.id == id else { return br }
            return TimeBreak(id: br.id, startAt: br.startAt, endAt: components, label: br.label)
        }
        let updated = BusinessDay(
            weekday: day.weekday,
            isOpen: day.isOpen,
            openAt: day.openAt,
            closeAt: day.closeAt,
            breaks: breaks
        )
        week = week.updatingDay(updated)
    }

    // MARK: - Convenience helpers

    /// Copy Monday's schedule to all weekdays (Tue-Fri). Leaves Sat/Sun untouched.
    public func copyMondayToWeekdays() {
        // weekday index: 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri
        guard let monday = week.day(for: 2) else { return }
        for weekday in 3...6 {
            let updated = BusinessDay(
                weekday: weekday,
                isOpen: monday.isOpen,
                openAt: monday.openAt,
                closeAt: monday.closeAt,
                breaks: monday.breaks
            )
            week = week.updatingDay(updated)
        }
    }

    /// Copy Saturday's schedule to Sunday.
    public func copySaturdayToSunday() {
        // 7 = Saturday, 1 = Sunday
        guard let saturday = week.day(for: 7) else { return }
        let sunday = BusinessDay(
            weekday: 1,
            isOpen: saturday.isOpen,
            openAt: saturday.openAt,
            closeAt: saturday.closeAt,
            breaks: saturday.breaks
        )
        week = week.updatingDay(sunday)
    }

    // MARK: - Save

    public func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            week = try await repository.saveHoursWeek(week)
            saveSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
