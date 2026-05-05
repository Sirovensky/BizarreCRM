import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentCalendarGridView
//
// iPad-only weekly calendar grid: 7 columns (one per day), each showing
// appointment chips stacked vertically. Activated when `!Platform.isCompact`.
//
// Layout contract:
//   - Columns: Sun–Sat for the selected week.
//   - Each chip shows time + truncated title.
//   - Tapping a chip pushes `AppointmentDetailView`.
//   - "Today" column header is highlighted with `.bizarreOrange`.
//   - No glass on the grid cells — glass is navigation chrome only (CLAUDE.md).

@MainActor
@Observable
public final class AppointmentCalendarGridViewModel {

    // MARK: - State

    public private(set) var appointments: [Appointment] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var weekStart: Date

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cal = Calendar.current

    // MARK: - Init

    public init(api: APIClient, referenceDate: Date = Date()) {
        self.api = api
        // Snap to the Monday of the current week (ISO week).
        self.weekStart = Self.startOfWeek(for: referenceDate)
    }

    // MARK: - Navigation

    public func previousWeek() {
        weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
    }

    public func nextWeek() {
        weekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
    }

    public func goToToday() {
        weekStart = Self.startOfWeek(for: Date())
    }

    // MARK: - Data

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let from = df.string(from: weekStart)
        let to   = df.string(from: weekEnd)
        do {
            appointments = try await api.listAppointments(fromDate: from, toDate: to)
        } catch {
            AppLog.ui.error("CalendarGrid load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// The 7 days of the currently displayed week (Mon–Sun).
    public var weekDays: [Date] {
        (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: weekStart)
        }
    }

    public var weekEnd: Date {
        cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }

    /// Appointments on a given calendar day, sorted by start time.
    public func appointments(on day: Date) -> [Appointment] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return appointments.filter { appt in
            guard let raw = appt.startTime, let date = Self.parseDate(raw) else { return false }
            return date >= start && date < end
        }.sorted { lhs, rhs in
            let l = lhs.startTime.flatMap(Self.parseDate) ?? .distantPast
            let r = rhs.startTime.flatMap(Self.parseDate) ?? .distantPast
            return l < r
        }
    }

    public func isToday(_ day: Date) -> Bool {
        cal.isDateInToday(day)
    }

    /// Returns appointments that span the full day (no specific start time, or
    /// the start time resolves to exactly midnight local time) for a given day.
    public func allDayAppointments(on day: Date) -> [Appointment] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return appointments.filter { appt in
            // No start time → treat as all-day.
            guard let raw = appt.startTime else { return true }
            guard let date = Self.parseDate(raw) else { return false }
            guard date >= start && date < end else { return false }
            let comps = cal.dateComponents([.hour, .minute, .second], from: date)
            return (comps.hour ?? -1) == 0 && (comps.minute ?? -1) == 0 && (comps.second ?? -1) == 0
        }
    }

    /// `true` when the week shown contains today.
    public var isShowingCurrentWeek: Bool {
        cal.isDate(weekStart, equalTo: Self.startOfWeek(for: Date()), toGranularity: .weekOfYear)
    }

    // MARK: - Helpers

    static func startOfWeek(for date: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        return cal.date(from: comps) ?? date
    }

    static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        let iso2 = ISO8601DateFormatter()
        if let d = iso2.date(from: raw) { return d }
        let sql = DateFormatter()
        sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sql.timeZone = TimeZone(identifier: "UTC")
        sql.locale = Locale(identifier: "en_US_POSIX")
        return sql.date(from: raw)
    }
}

// MARK: - AppointmentCalendarGridView

/// iPad weekly calendar grid.
///
/// iPhone: not rendered — guard with `Platform.isCompact` at the call site,
/// or use `AppointmentListView` which already branches on platform.
public struct AppointmentCalendarGridView: View {
    @State private var vm: AppointmentCalendarGridViewModel
    @State private var selectedAppointment: Appointment?
    private let api: APIClient

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE\nd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    public init(api: APIClient, referenceDate: Date = Date()) {
        self.api = api
        _vm = State(wrappedValue: AppointmentCalendarGridViewModel(api: api, referenceDate: referenceDate))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                weekHeader
                Divider()
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    PhaseErrorView(message: err) { Task { await vm.load() } }
                } else {
                    gridBody
                }
            }
        }
        .navigationTitle(weekRangeTitle)
        .task { await vm.load() }
        .onChange(of: vm.weekStart) { _, _ in Task { await vm.load() } }
        .navigationDestination(item: $selectedAppointment) { appt in
            AppointmentDetailView(appointment: appt, api: api) {
                selectedAppointment = nil
                Task { await vm.load() }
            }
        }
    }

    // MARK: - Week header (prev / title / next + Today)

    private var weekHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            Button {
                vm.previousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Previous week")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Text(weekRangeTitle)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)

            Button("Today") { vm.goToToday() }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .keyboardShortcut("T", modifiers: .command)

            Button {
                vm.nextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Next week")
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
    }

    // MARK: - Grid

    private var gridBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                // All-day section — pinned above the scrollable timed grid.
                allDaySection
                    .background(Color.bizarreSurface1)
                Divider()
                // Timed appointment grid.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
                    spacing: 1
                ) {
                    // Column headers
                    ForEach(vm.weekDays, id: \.self) { day in
                        columnHeader(for: day)
                    }
                    // Appointment chips — one cell per day
                    ForEach(vm.weekDays, id: \.self) { day in
                        dayColumn(for: day)
                    }
                }
                .background(Color.bizarreSurface2)
            }
        }
    }

    // MARK: - All-day section

    /// Horizontal strip above the timed grid listing all-day appointments for
    /// each day of the week. Hidden when no day has an all-day appointment.
    @ViewBuilder
    private var allDaySection: some View {
        let allDayCounts = vm.weekDays.map { vm.allDayAppointments(on: $0) }
        let hasAnyAllDay = allDayCounts.contains { !$0.isEmpty }
        if hasAnyAllDay {
            HStack(spacing: 1) {
                // Left gutter label.
                Text("All-day")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 48, alignment: .trailing)
                    .padding(.trailing, BrandSpacing.xs)
                    .accessibilityHidden(true)

                // One cell per weekday.
                ForEach(Array(zip(vm.weekDays, allDayCounts)), id: \.0) { day, appts in
                    VStack(spacing: 2) {
                        ForEach(appts) { appt in
                            Text(appt.title ?? "Appointment")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel(allDayChipA11y(for: appt, on: day))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
                    .padding(.vertical, BrandSpacing.xxs)
                }
            }
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("All-day appointments")
        }
    }

    private func allDayChipA11y(for appt: Appointment, on day: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        var parts = [df.string(from: day)]
        parts.append("All day")
        parts.append(appt.title ?? "Appointment")
        if let customer = appt.customerName { parts.append(customer) }
        if let status = appt.status { parts.append("Status \(status)") }
        return parts.joined(separator: ", ")
    }

    private func columnHeader(for day: Date) -> some View {
        let isToday = vm.isToday(day)
        return VStack(spacing: BrandSpacing.xxs) {
            Text(Self.dayFormatter.string(from: day))
                .font(isToday ? .brandLabelLarge() : .brandLabelSmall())
                .foregroundStyle(isToday ? Color.bizarreOrange : .bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            if isToday {
                Circle()
                    .fill(Color.bizarreOrange)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
        .accessibilityLabel(isToday ? "Today, \(Self.dayFormatter.string(from: day))" : Self.dayFormatter.string(from: day))
    }

    private func dayColumn(for day: Date) -> some View {
        let appts = vm.appointments(on: day)
        return VStack(spacing: BrandSpacing.xxs) {
            ForEach(appts) { appt in
                appointmentChip(appt)
            }
            if appts.isEmpty {
                Color.clear.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
        .padding(BrandSpacing.xxs)
        .background(Color.bizarreSurface1)
    }

    private func appointmentChip(_ appt: Appointment) -> some View {
        Button {
            selectedAppointment = appt
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                if let raw = appt.startTime, let date = AppointmentCalendarGridViewModel.parseDate(raw) {
                    Text(Self.timeFormatter.string(from: date))
                        .font(.brandMono(size: 10))
                        .foregroundStyle(chipTextColor(for: appt.status))
                        .accessibilityHidden(true)
                }
                Text(appt.title ?? "Appointment")
                    .font(.brandLabelSmall())
                    .foregroundStyle(chipTextColor(for: appt.status))
                    .lineLimit(2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                chipBackground(for: appt.status),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chipA11y(for: appt))
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Helpers

    private var weekRangeTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let start = f.string(from: vm.weekStart)
        let end = f.string(from: vm.weekEnd)
        let yearF = DateFormatter()
        yearF.dateFormat = "yyyy"
        return "\(start) – \(end), \(yearF.string(from: vm.weekStart))"
    }

    private func chipBackground(for status: String?) -> Color {
        switch status?.lowercased() {
        case "confirmed":  return Color.bizarreSuccess.opacity(0.15)
        case "completed":  return Color.bizarreSuccess.opacity(0.08)
        case "cancelled":  return Color.bizarreError.opacity(0.10)
        case "no-show":    return Color.bizarreWarning.opacity(0.12)
        default:           return Color.bizarreOrange.opacity(0.15)
        }
    }

    private func chipTextColor(for status: String?) -> Color {
        switch status?.lowercased() {
        case "confirmed":  return .bizarreSuccess
        case "completed":  return .bizarreSuccess
        case "cancelled":  return .bizarreError
        case "no-show":    return .bizarreWarning
        default:           return .bizarreOrange
        }
    }

    /// Full VoiceOver utterance for a timed appointment chip.
    ///
    /// Format: "<weekday, date> at <time>. <title>. <customer>. with <assignee>.
    ///          Duration <N> minutes. Status <status>."
    ///
    /// Every non-nil field is included so a screen-reader user gets the same
    /// information as a sighted user who can read the chip and the column header.
    private func chipA11y(for appt: Appointment) -> String {
        var parts: [String] = []

        if let raw = appt.startTime, let date = AppointmentCalendarGridViewModel.parseDate(raw) {
            // Full date so the user knows which column the chip belongs to.
            let dayDF = DateFormatter()
            dayDF.dateFormat = "EEEE, MMMM d"
            parts.append("\(dayDF.string(from: date)) at \(Self.timeFormatter.string(from: date))")

            // Duration — derive from end time if available.
            if let endRaw = appt.endTime,
               let endDate = AppointmentCalendarGridViewModel.parseDate(endRaw) {
                let mins = Int(endDate.timeIntervalSince(date) / 60)
                if mins > 0 {
                    parts.append("Duration \(mins) \(mins == 1 ? "minute" : "minutes")")
                }
            }
        }

        parts.append(appt.title ?? "Appointment")
        if let customer = appt.customerName { parts.append(customer) }
        if let assignee = appt.assignedName  { parts.append("with \(assignee)") }
        if let status   = appt.status        { parts.append("Status \(status)") }

        return parts.joined(separator: ". ")
    }
}
