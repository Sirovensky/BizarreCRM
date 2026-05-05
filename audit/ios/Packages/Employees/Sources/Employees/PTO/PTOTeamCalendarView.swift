import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - PTOTeamCalendarViewModel

@MainActor
@Observable
public final class PTOTeamCalendarViewModel {
    public var displayedMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    public private(set) var approvedRequests: [PTORequest] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        if approvedRequests.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            approvedRequests = try await api.listPTORequests(status: .approved)
        } catch {
            AppLog.ui.error("PTOTeamCalendar load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func advanceMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    public func retreatMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    /// Returns all employees out on a given day.
    public func employeesOut(on day: Date) -> [String] {
        approvedRequests
            .filter { $0.startDate <= day && $0.endDate >= day }
            .map { $0.employeeId }
    }

    /// Returns dates that have 2+ employees out (conflict).
    public func conflictDays(in month: Date) -> Set<Date> {
        let days = Calendar.current.daysInMonth(for: month)
        return Set(days.filter { employeesOut(on: $0).count >= 2 })
    }
}

// MARK: - PTOTeamCalendarView

public struct PTOTeamCalendarView: View {
    @State private var vm: PTOTeamCalendarViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: PTOTeamCalendarViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                calendarGrid
            }
            .navigationTitle("Team Calendar")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - Month navigation header

    @ViewBuilder private var monthHeader: some View {
        HStack {
            Button {
                vm.retreatMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: DesignTokens.Touch.minTargetSide,
                           minHeight: DesignTokens.Touch.minTargetSide)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(vm.displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)

            Spacer()

            Button {
                vm.advanceMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: DesignTokens.Touch.minTargetSide,
                           minHeight: DesignTokens.Touch.minTargetSide)
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - Weekday labels

    @ViewBuilder private var weekdayHeader: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        Divider()
    }

    // MARK: - Grid

    @ViewBuilder private var calendarGrid: some View {
        let days = Calendar.current.daysInMonth(for: vm.displayedMonth)
        let conflicts = vm.conflictDays(in: vm.displayedMonth)
        let firstOffset = Calendar.current.firstWeekdayOffset(for: vm.displayedMonth)

        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7), spacing: DesignTokens.Spacing.xs) {
            // Leading blank cells
            ForEach(0..<firstOffset, id: \.self) { _ in Color.clear.frame(height: 44) }
            // Day cells
            ForEach(days, id: \.self) { day in
                PTOCalendarDayCell(
                    day: day,
                    employeesOut: vm.employeesOut(on: day),
                    isConflict: conflicts.contains(day)
                )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.top, DesignTokens.Spacing.xs)
    }
}

// MARK: - PTOCalendarDayCell

private struct PTOCalendarDayCell: View {
    let day: Date
    let employeesOut: [String]
    let isConflict: Bool

    private var dayNumber: String {
        Calendar.current.component(.day, from: day).description
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(dayNumber)
                .font(.callout.monospacedDigit())
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 28, height: 28)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())

            if !employeesOut.isEmpty {
                Circle()
                    .fill(isConflict ? Color.red : Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityLabel(calendarDayCellAccessibilityLabel)
    }

    private var calendarDayCellAccessibilityLabel: String {
        let formatted = day.formatted(date: .complete, time: .omitted)
        if employeesOut.isEmpty { return formatted }
        let out = employeesOut.joined(separator: ", ")
        let conflict = isConflict ? " — conflict" : ""
        return "\(formatted), \(employeesOut.count) out: \(out)\(conflict)"
    }
}

// MARK: - Calendar helpers

private extension Calendar {
    func daysInMonth(for date: Date) -> [Date] {
        guard let range = range(of: .day, in: .month, for: date),
              let monthStart = self.date(from: dateComponents([.year, .month], from: date)) else { return [] }
        return range.compactMap { day in
            self.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }

    func firstWeekdayOffset(for date: Date) -> Int {
        guard let monthStart = self.date(from: dateComponents([.year, .month], from: date)) else { return 0 }
        let weekday = component(.weekday, from: monthStart)
        return (weekday - firstWeekday + 7) % 7
    }
}
