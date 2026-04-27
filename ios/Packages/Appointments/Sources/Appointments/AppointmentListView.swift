import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

@MainActor
@Observable
public final class AppointmentListViewModel {
    public private(set) var items: [Appointment] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Exposed for `StalenessIndicator` chip in toolbar.
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: AppointmentCachedRepository?

    public init(api: APIClient, cachedRepo: AppointmentCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
    }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.listAppointments()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listAppointments()
            }
        } catch {
            AppLog.ui.error("Appointments load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.forceRefresh()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listAppointments()
            }
        } catch {
            AppLog.ui.error("Appointments force-refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Quick status update from context menu (mark complete / no-show).
    public func updateStatus(for id: Int64, status: AppointmentStatus) async {
        let req = UpdateAppointmentRequest(status: status.rawValue)
        do {
            let updated = try await api.updateAppointment(id: id, req)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = updated
            }
        } catch {
            AppLog.ui.error("Appt status update failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - §10.1 Calendar view mode

/// Segmented control options for Appointments — Agenda / Day / Week / Month.
public enum AppointmentViewMode: String, CaseIterable, Identifiable {
    case agenda = "Agenda"
    case day    = "Day"
    case week   = "Week"
    case month  = "Month"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .agenda: return "list.bullet"
        case .day:    return "calendar.day.timeline.left"
        case .week:   return "calendar"
        case .month:  return "calendar.badge.plus"
        }
    }
}

// MARK: - §10.1 Appointment filter

/// Filter applied to the appointment list.
public struct AppointmentListFilter: Equatable, Sendable {
    public var assigneeId: Int64?
    public var status: String?

    public var isEmpty: Bool { assigneeId == nil && (status == nil || status!.isEmpty) }

    public init(assigneeId: Int64? = nil, status: String? = nil) {
        self.assigneeId = assigneeId
        self.status = status
    }
}

public struct AppointmentListView: View {
    @State private var vm: AppointmentListViewModel
    @State private var showingCreate: Bool = false
    @State private var selectedAppointment: Appointment?
    @State private var cancelTarget: Appointment?
    // §10.1 view mode segmented control
    @State private var viewMode: AppointmentViewMode = .agenda
    // §10.1 filter sheet
    @State private var showingFilter: Bool = false
    @State private var activeFilter: AppointmentListFilter = .init()
    // §10.1 month view — selected day; nil = show all month
    @State private var selectedMonthDate: Date? = nil
    private let api: APIClient

    public init(api: APIClient, cachedRepo: AppointmentCachedRepository? = nil) {
        self.api = api
        _vm = State(wrappedValue: AppointmentListViewModel(api: api, cachedRepo: cachedRepo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            AppointmentCreateFullView(api: api)
        }
        .sheet(item: $cancelTarget) { appt in
            AppointmentCancelView(appointment: appt, api: api) {
                Task { await vm.load() }
                cancelTarget = nil
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    // §10.1 Segmented control — Agenda / Day / Week
                    Picker("View", selection: $viewMode) {
                        ForEach(AppointmentViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                    .accessibilityLabel("Calendar view mode")
                    content
                }
            }
            .navigationTitle("Appointments")
            .toolbar {
                newButton
                todayButton
                filterButton
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
            .navigationDestination(item: $selectedAppointment) { appt in
                AppointmentDetailView(appointment: appt, api: api) {
                    selectedAppointment = nil
                    Task { await vm.load() }
                }
            }
        }
        .sheet(isPresented: $showingFilter) {
            AppointmentFilterSheet(filter: $activeFilter)
                .presentationDetents([.medium])
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    // §10.1 Segmented control — Agenda / Day / Week
                    Picker("View", selection: $viewMode) {
                        ForEach(AppointmentViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                    .accessibilityLabel("Calendar view mode")
                    content
                }
            }
            .navigationTitle("Appointments")
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .toolbar {
                newButton
                todayButton
                filterButton
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        } detail: {
            if let appt = selectedAppointment {
                AppointmentDetailView(appointment: appt, api: api) {
                    selectedAppointment = nil
                    Task { await vm.load() }
                }
            } else {
                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: "calendar.circle")
                            .font(.system(size: 52))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text("Select an appointment")
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationTitle("")
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var newButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("New appointment")
                .accessibilityIdentifier("appointments.new")
        }
    }

    /// §10.1 Today button — scrolls agenda to now; reloads with today's date range.
    private var todayButton: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await vm.load() }
            } label: {
                Text("Today").font(.brandLabelLarge())
            }
            .keyboardShortcut("T", modifiers: .command)
            .accessibilityLabel("Go to today")
            .accessibilityIdentifier("appointments.today")
        }
    }

    /// §10.1 Filter button — employee / status filter sheet.
    private var filterButton: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { showingFilter = true } label: {
                Image(systemName: activeFilter.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(activeFilter.isEmpty ? Color.bizarreOnSurface : Color.bizarreOrange)
            }
            .accessibilityLabel(activeFilter.isEmpty ? "Filter appointments" : "Filter active — tap to change")
            .accessibilityIdentifier("appointments.filter")
        }
    }

    // MARK: - §10.1 Filtered items helper

    private var filteredItems: [Appointment] {
        guard !activeFilter.isEmpty else { return vm.items }
        return vm.items.filter { appt in
            if let status = activeFilter.status, !status.isEmpty {
                guard appt.status?.lowercased() == status.lowercased() else { return false }
            }
            // assigneeId filter not feasible client-side without an assigned_to field on the model
            // — filtered server-side via reload when filter changes (future enhancement).
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading appointments")
        } else if let err = vm.errorMessage {
            PhaseErrorView(message: err) { Task { await vm.load() } }
        } else if vm.items.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "appointments")
        } else if vm.items.isEmpty {
            PhaseEmptyView(icon: "calendar", text: "No appointments")
        } else {
            switch viewMode {
            case .agenda:
                agendaList
            case .day:
                // §10.1 Day view — agenda grouped by time-block (morning/afternoon/evening)
                dayGroupedList
            case .week:
                // §10.1 Week view — use AppointmentCalendarGridView (iPad) or compact agenda (iPhone)
                if Platform.isCompact {
                    agendaList
                } else {
                    AppointmentCalendarGridView(api: api)
                }
            case .month:
                // §10.1 Month view — dot-per-day grid; tap day → agenda filtered to that date
                AppointmentMonthView(appointments: filteredItems, selectedDate: $selectedMonthDate)
            }
        }
    }

    private var agendaList: some View {
        List {
            ForEach(filteredItems) { appt in
                Button {
                    selectedAppointment = appt
                } label: {
                    Row(appointment: appt)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bizarreSurface1)
                .brandHover()
                .contextMenu { appointmentContextMenu(for: appt) }
                .accessibilityLabel(Row.a11y(for: appt))
                .accessibilityHint("Double tap to view details")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - §10.1 Day view — grouped by time-block

    /// §10.1 Day view: appointments grouped into Morning (before 12), Afternoon (12–17), Evening (17+).
    private var dayGroupedList: some View {
        List {
            ForEach(TimeBlock.allCases, id: \.self) { block in
                let blockItems = filteredItems.filter { appt in
                    guard let raw = appt.startTime, let date = Row.parse(raw) else { return false }
                    return block.contains(date)
                }
                if !blockItems.isEmpty {
                    Section {
                        ForEach(blockItems) { appt in
                            Button { selectedAppointment = appt } label: { Row(appointment: appt) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.bizarreSurface1)
                                .brandHover()
                                .contextMenu { appointmentContextMenu(for: appt) }
                                .accessibilityLabel(Row.a11y(for: appt))
                                .accessibilityHint("Double tap to view details")
                        }
                    } header: {
                        Text(block.title)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - TimeBlock

    private enum TimeBlock: CaseIterable {
        case morning    // before 12:00
        case afternoon  // 12:00–17:00
        case evening    // 17:00+

        var title: String {
            switch self {
            case .morning:   return "Morning"
            case .afternoon: return "Afternoon"
            case .evening:   return "Evening"
            }
        }

        /// Returns true if `date`'s hour falls in this block.
        func contains(_ date: Date) -> Bool {
            let hour = Calendar.current.component(.hour, from: date)
            switch self {
            case .morning:   return hour < 12
            case .afternoon: return hour >= 12 && hour < 17
            case .evening:   return hour >= 17
            }
        }
    }

    // MARK: - §22 Appointment context menu

    @ViewBuilder
    private func appointmentContextMenu(for appt: Appointment) -> some View {
        // View Details
        Button {
            selectedAppointment = appt
        } label: {
            Label("View Details", systemImage: "calendar")
        }
        .accessibilityLabel("View details for \(appt.title ?? "appointment")")

        // Reschedule (opens edit view)
        Button {
            selectedAppointment = appt
        } label: {
            Label("Reschedule", systemImage: "calendar.badge.plus")
        }
        .accessibilityLabel("Reschedule \(appt.title ?? "appointment")")

        // Mark Complete
        Button {
            Task { await vm.updateStatus(for: appt.id, status: .completed) }
        } label: {
            Label("Mark Complete", systemImage: "checkmark.circle")
        }
        .accessibilityLabel("Mark \(appt.title ?? "appointment") as complete")

        // Mark No-Show
        Button {
            Task { await vm.updateStatus(for: appt.id, status: .noShow) }
        } label: {
            Label("No-Show", systemImage: "person.slash")
        }
        .accessibilityLabel("Mark \(appt.title ?? "appointment") as no-show")

        Divider()

        // Cancel (destructive)
        Button(role: .destructive) {
            cancelTarget = appt
        } label: {
            Label("Cancel Appointment", systemImage: "xmark.circle")
        }
        .accessibilityLabel("Cancel \(appt.title ?? "appointment")")
    }

    private struct Row: View {
        let appointment: Appointment

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                dateColumn
                    .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(appointment.title ?? "Appointment")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let customer = appointment.customerName {
                        Text(customer).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let assigned = appointment.assignedName {
                        Text("with \(assigned)").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                if let status = appointment.status {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .accessibilityLabel("Status \(status)")
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: appointment))
        }

        /// Left-column date block. Parses SQL or ISO-8601 datetimes and
        /// renders a 2-line stamp (date + time). Raw string as fallback so
        /// we never hide data on parse failure.
        @ViewBuilder
        private var dateColumn: some View {
            if let raw = appointment.startTime, let date = Self.parse(raw) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateLabel(date))
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurface)
                    Text(Self.timeLabel(date))
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else if let raw = appointment.startTime {
                Text(String(raw.prefix(10)))
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
            }
        }

        static func parse(_ raw: String) -> Date? {
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

        static func dateLabel(_ date: Date) -> String {
            let cal = Calendar.current
            if cal.isDateInToday(date) { return "Today" }
            if cal.isDateInTomorrow(date) { return "Tomorrow" }
            if cal.isDateInYesterday(date) { return "Yesterday" }
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return df.string(from: date)
        }

        static func timeLabel(_ date: Date) -> String {
            let df = DateFormatter()
            df.timeStyle = .short
            df.dateStyle = .none
            return df.string(from: date)
        }

        /// VoiceOver utterance — "Today at 3:00 PM. Device pickup. Jane Doe. with Sam. Status confirmed."
        static func a11y(for appt: Appointment) -> String {
            var parts: [String] = []
            if let raw = appt.startTime, let date = parse(raw) {
                parts.append("\(dateLabel(date)) at \(timeLabel(date))")
            }
            parts.append(appt.title ?? "Appointment")
            if let name = appt.customerName { parts.append(name) }
            if let who = appt.assignedName { parts.append("with \(who)") }
            if let status = appt.status { parts.append("Status \(status)") }
            return parts.joined(separator: ". ")
        }
    }
}

// MARK: - Reusable pane helpers

struct PhaseErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhaseEmptyView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(text).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - §10.1 AppointmentFilterSheet

/// Sheet presented by the filter button in `AppointmentListView`.
/// Lets staff filter by status (and optionally employee — future when model carries assigned_to id).
public struct AppointmentFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var filter: AppointmentListFilter

    @State private var draftStatus: String

    private static let statuses: [String] = ["", "scheduled", "confirmed", "completed", "cancelled", "no-show"]

    public init(filter: Binding<AppointmentListFilter>) {
        _filter = filter
        _draftStatus = State(initialValue: filter.wrappedValue.status ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $draftStatus) {
                        Text("Any").tag("")
                            .accessibilityLabel("Any status")
                        ForEach(Self.statuses.dropFirst(), id: \.self) { s in
                            Text(s.capitalized).tag(s)
                        }
                    }
                    .accessibilityLabel("Appointment status filter")
                }
                .listRowBackground(Color.bizarreSurface1)
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Filter")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel filter")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = AppointmentListFilter(
                            status: draftStatus.isEmpty ? nil : draftStatus
                        )
                        dismiss()
                    }
                    .accessibilityLabel("Apply filter")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Clear") {
                    filter = .init()
                    dismiss()
                }
                .buttonStyle(.borderless)
                .tint(.bizarreOrange)
                .padding()
                .accessibilityLabel("Clear all filters")
            }
        }
    }
}

// MARK: - §10.1 Month view

/// Calendar-style month grid where each day shows a dot badge for the number of
/// appointments on that day. Tapping a day cell selects it and scrolls the
/// agenda below to that date's events.
public struct AppointmentMonthView: View {
    public let appointments: [Appointment]
    @Binding public var selectedDate: Date?

    @State private var displayMonth: Date = {
        var cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    private var cal: Calendar { Calendar.current }

    private var daysInMonth: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: displayMonth),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: displayMonth))
        else { return [] }
        let weekdayOffset = (cal.component(.weekday, from: firstDay) - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: weekdayOffset)
        for day in range {
            let d = cal.date(byAdding: .day, value: day - 1, to: firstDay)
            days.append(d)
        }
        // Pad to full weeks
        let remainder = days.count % 7
        if remainder != 0 { days += Array(repeating: nil, count: 7 - remainder) }
        return days
    }

    private func appointmentCount(for date: Date) -> Int {
        appointments.filter { appt in
            guard let raw = appt.startTime, let d = Row.parse(raw) else { return false }
            return cal.isDate(d, inSameDayAs: date)
        }.count
    }

    private var monthTitle: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df.string(from: displayMonth)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Month navigation header
            HStack {
                Button {
                    displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Text(monthTitle)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Next month")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)

            // Day-of-week header row
            let symbols = cal.veryShortWeekdaySymbols
            let ordered = Array((cal.firstWeekday - 1..<7) + (0..<cal.firstWeekday - 1))
                .map { symbols[$0] }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                ForEach(ordered, id: \.self) { sym in
                    Text(sym)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.xxs)
                        .accessibilityHidden(true)
                }
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date: day,
                            count: appointmentCount(for: day),
                            isSelected: selectedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                            isToday: cal.isDateInToday(day)
                        ) {
                            selectedDate = (selectedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
                                ? nil : day
                        }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.sm)

            Divider()
                .padding(.top, BrandSpacing.xs)

            // Agenda for selected day (or all if no selection)
            let dayItems: [Appointment] = selectedDate.map { sel in
                appointments.filter { appt in
                    guard let raw = appt.startTime, let d = Row.parse(raw) else { return false }
                    return cal.isDate(d, inSameDayAs: sel)
                }
            } ?? appointments

            if dayItems.isEmpty {
                Text(selectedDate != nil ? "No appointments this day" : "No appointments this month")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(BrandSpacing.lg)
            } else {
                List {
                    ForEach(dayItems) { appt in
                        Row(appointment: appt)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.bizarreSurfaceBase)
    }
}

private struct DayCell: View {
    let date: Date
    let count: Int
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        let df = DateFormatter()
        df.dateFormat = "d"
        return df.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.bizarreOrange : (isToday ? Color.bizarreOrange.opacity(0.15) : Color.clear))
                        .frame(width: 32, height: 32)
                    Text(dayNumber)
                        .font(.brandBodyMedium())
                        .foregroundStyle(isSelected ? .white : (isToday ? .bizarreOrange : .bizarreOnSurface))
                        .monospacedDigit()
                }
                // Dot badge — 1 dot per appointment, max 3
                if count > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(count, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? Color.white : Color.bizarreOrange)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Spacer().frame(height: 6)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dayNumber), \(count) appointment\(count == 1 ? "" : "s")\(isToday ? ", today" : "")")
    }
}
