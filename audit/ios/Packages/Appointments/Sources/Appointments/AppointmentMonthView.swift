import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentMonthCalendarViewModel

@MainActor
@Observable
public final class AppointmentMonthCalendarViewModel {

    // MARK: State

    public private(set) var appointments: [Appointment] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// The month being displayed — always snapped to the 1st of the month.
    public var displayMonth: Date

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cal = Calendar.current

    // MARK: Init

    public init(api: APIClient, referenceDate: Date = Date()) {
        self.api = api
        self.displayMonth = Self.startOfMonth(for: referenceDate)
    }

    // MARK: Navigation

    public func previousMonth() {
        displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
    }

    public func nextMonth() {
        displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
    }

    /// Jump-to-today: snap displayMonth to the month that contains today.
    public func jumpToToday() {
        displayMonth = Self.startOfMonth(for: Date())
    }

    public var isShowingCurrentMonth: Bool {
        cal.isDate(displayMonth, equalTo: Self.startOfMonth(for: Date()), toGranularity: .month)
    }

    // MARK: Data

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: displayMonth) else { return }
        let from = df.string(from: displayMonth)
        let to   = df.string(from: monthEnd)
        do {
            appointments = try await api.listAppointments(fromDate: from, toDate: to)
        } catch {
            AppLog.ui.error("MonthView load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Derived

    /// All calendar days visible in the grid (including padding from adjacent months).
    public var gridDays: [Date] {
        let firstWeekday = cal.component(.weekday, from: displayMonth)
        // Offset so Mon = 0 (ISO week).
        let leadingPad = (firstWeekday + 5) % 7
        let start = cal.date(byAdding: .day, value: -leadingPad, to: displayMonth) ?? displayMonth
        // 6 rows × 7 cols = 42 cells.
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    public func appointmentCount(on day: Date) -> Int {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return appointments.filter { appt in
            guard let raw = appt.startTime,
                  let date = AppointmentCalendarGridViewModel.parseDate(raw) else { return false }
            return date >= start && date < end
        }.count
    }

    public func appointments(on day: Date) -> [Appointment] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return appointments.filter { appt in
            guard let raw = appt.startTime,
                  let date = AppointmentCalendarGridViewModel.parseDate(raw) else { return false }
            return date >= start && date < end
        }.sorted {
            let l = $0.startTime.flatMap(AppointmentCalendarGridViewModel.parseDate) ?? .distantPast
            let r = $1.startTime.flatMap(AppointmentCalendarGridViewModel.parseDate) ?? .distantPast
            return l < r
        }
    }

    public func isToday(_ day: Date) -> Bool { cal.isDateInToday(day) }
    public func isInDisplayMonth(_ day: Date) -> Bool {
        cal.isDate(day, equalTo: displayMonth, toGranularity: .month)
    }

    // MARK: Helpers

    static func startOfMonth(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }
}

// MARK: - AppointmentMonthCalendarView

/// Month-grid calendar view.
///
/// - Displays a 6-row × 7-column grid (Mon–Sun header).
/// - Each day cell shows a dot-badge for each appointment (max 3 dots).
/// - Tapping a day reveals the day's appointment agenda in a bottom sheet.
/// - **"Today" button** in the header bar jumps back to the current month
///   and is hidden when already showing the current month.
public struct AppointmentMonthCalendarView: View {

    @State private var vm: AppointmentMonthCalendarViewModel
    @State private var selectedDay: Date?
    private let api: APIClient

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    public init(api: APIClient, referenceDate: Date = Date()) {
        self.api = api
        _vm = State(wrappedValue: AppointmentMonthCalendarViewModel(api: api, referenceDate: referenceDate))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                monthHeader
                Divider()
                weekdayLabels
                Divider()
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    PhaseErrorView(message: err) { Task { await vm.load() } }
                } else {
                    monthGrid
                }
            }
        }
        .navigationTitle(Self.monthYearFormatter.string(from: vm.displayMonth))
        .task { await vm.load() }
        .onChange(of: vm.displayMonth) { _, _ in Task { await vm.load() } }
        .sheet(item: $selectedDay) { day in
            DayAgendaSheet(day: day, appointments: vm.appointments(on: day), api: api)
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            Button {
                vm.previousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Previous month")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Text(Self.monthYearFormatter.string(from: vm.displayMonth))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            // Jump-to-today button — hidden when already on the current month.
            if !vm.isShowingCurrentMonth {
                Button("Today") {
                    vm.jumpToToday()
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .keyboardShortcut("T", modifiers: .command)
                .accessibilityLabel("Jump to today")
                .accessibilityHint("Returns calendar to the current month")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Button {
                vm.nextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Next month")
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
        .animation(.easeInOut(duration: 0.2), value: vm.isShowingCurrentMonth)
    }

    // MARK: - Weekday labels

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { label in
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.xs)
                    .accessibilityHidden(true) // row is announced per-cell below
            }
        }
        .background(Color.bizarreSurface1)
    }

    // MARK: - Month grid

    private var monthGrid: some View {
        let days = vm.gridDays
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
            spacing: 1
        ) {
            ForEach(days, id: \.self) { day in
                dayCell(for: day)
            }
        }
        .background(Color.bizarreSurface2)
        .padding(.bottom, BrandSpacing.md)
    }

    private func dayCell(for day: Date) -> some View {
        let isToday        = vm.isToday(day)
        let isCurrentMonth = vm.isInDisplayMonth(day)
        let count          = vm.appointmentCount(on: day)

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: BrandSpacing.xxs) {
                // Day number
                Text(Self.dayNumberFormatter.string(from: day))
                    .font(isToday ? .brandLabelLarge() : .brandLabelSmall())
                    .foregroundStyle(
                        isToday ? Color.white :
                        isCurrentMonth ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        isToday ? Color.bizarreOrange : Color.clear,
                        in: Circle()
                    )

                // Dot badge row — up to 3 dots per cell.
                HStack(spacing: 3) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isCurrentMonth ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
            .padding(.top, BrandSpacing.xs)
            .background(isCurrentMonth ? Color.bizarreSurface1 : Color.bizarreSurfaceBase)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cellA11yLabel(for: day, count: count))
        .accessibilityHint(count > 0 ? "Double tap to view appointments" : "Double tap to view day")
    }

    // MARK: - A11y helpers

    private func cellA11yLabel(for day: Date, count: Int) -> String {
        let cal = Calendar.current
        let df  = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        var label = df.string(from: day)
        if cal.isDateInToday(day) { label = "Today, \(label)" }
        switch count {
        case 0: break
        case 1: label += ", 1 appointment"
        default: label += ", \(count) appointments"
        }
        return label
    }
}

// MARK: - DayAgendaSheet

/// Bottom-sheet listing appointments for a tapped day in the month grid.
private struct DayAgendaSheet: View {
    let day: Date
    let appointments: [Appointment]
    let api: APIClient

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAppointment: Appointment?

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if appointments.isEmpty {
                        PhaseEmptyView(icon: "calendar", text: "No appointments")
                    } else {
                        List {
                            ForEach(appointments) { appt in
                                Button {
                                    selectedAppointment = appt
                                } label: {
                                    agendaRow(for: appt)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.bizarreSurface1)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(Self.dayHeaderFormatter.string(from: day))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $selectedAppointment) { appt in
                AppointmentDetailView(appointment: appt, api: api) {
                    selectedAppointment = nil
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func agendaRow(for appt: Appointment) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            if let raw = appt.startTime,
               let date = AppointmentCalendarGridViewModel.parseDate(raw) {
                Text(timeString(from: date))
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 56, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(appt.title ?? "Appointment")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let customer = appt.customerName {
                    Text(customer)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Date + Identifiable shim

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSinceReferenceDate }
}
