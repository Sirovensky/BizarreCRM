import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentsScopeFilter

/// Sidebar scope selection for the three-column layout.
public enum AppointmentsScopeFilter: String, CaseIterable, Identifiable, Sendable {
    case today   = "Today"
    case week    = "This Week"
    case month   = "This Month"
    case all     = "All"

    public var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today:  return "sun.max"
        case .week:   return "calendar.badge.clock"
        case .month:  return "calendar"
        case .all:    return "list.bullet"
        }
    }
}

// MARK: - AppointmentsThreeColumnViewModel

@MainActor
@Observable
public final class AppointmentsThreeColumnViewModel {

    // MARK: - State

    public private(set) var allAppointments: [Appointment] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var selectedScope: AppointmentsScopeFilter = .today
    public var selectedAppointment: Appointment?
    public var selectedDate: Date = Date()

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cal = Calendar.current

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Data

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            allAppointments = try await api.listAppointments(pageSize: 500)
        } catch {
            AppLog.ui.error("ThreeColumn load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await load()
    }

    // MARK: - Derived

    /// Appointments filtered by the active scope.
    public var scopeAppointments: [Appointment] {
        switch selectedScope {
        case .today:
            return allAppointments.filter { isOnDay($0, day: Date()) }
                .sorted(by: startTimeSortAscending)
        case .week:
            let (start, end) = currentWeekRange()
            return allAppointments.filter { isInRange($0, start: start, end: end) }
                .sorted(by: startTimeSortAscending)
        case .month:
            let (start, end) = currentMonthRange()
            return allAppointments.filter { isInRange($0, start: start, end: end) }
                .sorted(by: startTimeSortAscending)
        case .all:
            return allAppointments.sorted(by: startTimeSortAscending)
        }
    }

    /// Appointments for the day-agenda column: filtered to `selectedDate`.
    public var dayAgendaAppointments: [Appointment] {
        allAppointments.filter { isOnDay($0, day: selectedDate) }
            .sorted(by: startTimeSortAscending)
    }

    // MARK: - Helpers

    private func isOnDay(_ appt: Appointment, day: Date) -> Bool {
        guard let raw = appt.startTime, let date = Self.parseDate(raw) else { return false }
        return cal.isDate(date, inSameDayAs: day)
    }

    private func isInRange(_ appt: Appointment, start: Date, end: Date) -> Bool {
        guard let raw = appt.startTime, let date = Self.parseDate(raw) else { return false }
        return date >= start && date < end
    }

    private var startTimeSortAscending: (Appointment, Appointment) -> Bool {
        { lhs, rhs in
            let l = lhs.startTime.flatMap(Self.parseDate) ?? .distantFuture
            let r = rhs.startTime.flatMap(Self.parseDate) ?? .distantFuture
            return l < r
        }
    }

    private func currentWeekRange() -> (Date, Date) {
        let start = AppointmentCalendarGridViewModel.startOfWeek(for: Date())
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    private func currentMonthRange() -> (Date, Date) {
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps) ?? Date()
        let end   = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
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

// MARK: - AppointmentsThreeColumnView

/// iPad three-column split: sidebar (scope) | day-agenda | detail.
///
/// Gate at call sites with `!Platform.isCompact`. On iPhone this view
/// should never be shown — use `AppointmentListView` instead.
public struct AppointmentsThreeColumnView: View {
    @State private var vm: AppointmentsThreeColumnViewModel
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: AppointmentsThreeColumnViewModel(api: api))
    }

    public var body: some View {
        NavigationSplitView {
            sidebarColumn
        } content: {
            agendaColumn
        } detail: {
            detailColumn
        }
        .task { await vm.load() }
    }

    // MARK: - Sidebar

    private var sidebarColumn: some View {
        List {
            ForEach(AppointmentsScopeFilter.allCases, id: \.self) { scope in
                Button {
                    vm.selectedScope = scope
                    vm.selectedDate = Date()
                } label: {
                    HStack {
                        Label(scope.rawValue, systemImage: scope.systemImage)
                            .font(.brandBodyLarge())
                        Spacer()
                        if vm.selectedScope == scope {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scope.rawValue)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Appointments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.bizarreOrange)
                }
                .accessibilityLabel("Refresh appointments")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .background(Color.bizarreSurfaceBase)
    }

    // MARK: - Agenda column

    @ViewBuilder
    private var agendaColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                PhaseErrorView(message: err) { Task { await vm.load() } }
            } else if vm.scopeAppointments.isEmpty {
                emptyAgendaView
            } else {
                agendaList
            }
        }
        .navigationTitle(vm.selectedScope.rawValue)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var agendaList: some View {
        List {
            ForEach(vm.scopeAppointments, id: \.self) { appt in
                Button { vm.selectedAppointment = appt } label: {
                    AppointmentAgendaRow(appointment: appt)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    AppointmentContextMenu(appointment: appt, api: api) {
                        Task { await vm.refresh() }
                    }
                }
                #if !os(macOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: DesignTokens.Motion.smooth), value: vm.selectedScope)
    }

    private var emptyAgendaView: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.bizarreOrange.opacity(0.6))
                .accessibilityHidden(true)
            Text("No Appointments")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Nothing scheduled for \(vm.selectedScope.rawValue.lowercased()).")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xxl)
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let appt = vm.selectedAppointment {
            AppointmentDetailView(appointment: appt, api: api) {
                vm.selectedAppointment = nil
                Task { await vm.refresh() }
            }
        } else {
            detailPlaceholder
        }
    }

    private var detailPlaceholder: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "calendar")
                .font(.system(size: 56))
                .foregroundStyle(Color.bizarreOrange.opacity(0.4))
                .accessibilityHidden(true)
            Text("Select an Appointment")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase)
    }
}

// MARK: - AppointmentAgendaRow

/// Single row used in the agenda (content) column of the three-column layout.
struct AppointmentAgendaRow: View {
    let appointment: Appointment

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(statusColor)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(appointment.title ?? "Appointment")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                HStack(spacing: BrandSpacing.xs) {
                    if let raw = appointment.startTime,
                       let date = AppointmentsThreeColumnViewModel.parseDate(raw) {
                        Text(Self.timeFormatter.string(from: date))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let customer = appointment.customerName {
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(customer)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if let status = appointment.status {
                Text(status.capitalized)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, BrandSpacing.xs)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch appointment.status?.lowercased() {
        case "confirmed":  return .bizarreSuccess
        case "completed":  return .bizarreSuccess
        case "cancelled":  return .bizarreError
        case "no-show":    return .bizarreWarning
        default:           return .bizarreOrange
        }
    }
}
