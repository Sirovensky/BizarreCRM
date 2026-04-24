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

    private func chipA11y(for appt: Appointment) -> String {
        var parts: [String] = []
        if let raw = appt.startTime, let date = AppointmentCalendarGridViewModel.parseDate(raw) {
            parts.append(Self.timeFormatter.string(from: date))
        }
        parts.append(appt.title ?? "Appointment")
        if let status = appt.status { parts.append("Status \(status)") }
        return parts.joined(separator: ", ")
    }
}
