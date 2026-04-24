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

public struct AppointmentListView: View {
    @State private var vm: AppointmentListViewModel
    @State private var showingCreate: Bool = false
    @State private var selectedAppointment: Appointment?
    @State private var cancelTarget: Appointment?
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
                content
            }
            .navigationTitle("Appointments")
            .toolbar {
                newButton
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
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Appointments")
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .toolbar {
                newButton
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

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            PhaseErrorView(message: err) { Task { await vm.load() } }
        } else if vm.items.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "appointments")
        } else if vm.items.isEmpty {
            PhaseEmptyView(icon: "calendar", text: "No appointments")
        } else {
            List {
                ForEach(vm.items) { appt in
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
