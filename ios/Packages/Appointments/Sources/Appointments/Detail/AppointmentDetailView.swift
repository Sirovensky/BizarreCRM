import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentDetailViewModel

@MainActor
@Observable
public final class AppointmentDetailViewModel {

    // MARK: - State

    public private(set) var appointment: Appointment
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    /// Set to `true` after a successful no-show mark to trigger list reload.
    public private(set) var markedNoShow: Bool = false
    /// Set to `true` after marking completed.
    public private(set) var markedCompleted: Bool = false
    /// §10.6 Check-in timestamp (stamped locally when customer arrives).
    public private(set) var checkedInAt: Date?
    /// §10.6 Check-out timestamp (stamped locally when customer departs).
    public private(set) var checkedOutAt: Date?

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(appointment: Appointment, api: APIClient) {
        self.appointment = appointment
        self.api = api
    }

    // MARK: - Mark no-show

    public func markNoShow() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let req = UpdateAppointmentRequest(status: AppointmentStatus.noShow.rawValue, noShow: true)
            appointment = try await api.updateAppointment(id: appointment.id, req)
            markedNoShow = true
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Failed to mark no-show."
            AppLog.ui.error("Appt mark no-show failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Mark completed

    public func markCompleted() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let req = UpdateAppointmentRequest(status: AppointmentStatus.completed.rawValue)
            appointment = try await api.updateAppointment(id: appointment.id, req)
            markedCompleted = true
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Failed to mark completed."
            AppLog.ui.error("Appt mark completed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - §10.2 Send reminder

    /// Sends a reminder to the customer by re-confirming the appointment.
    /// The server dispatches SMS / email on every PUT with `status: confirmed`.
    public private(set) var reminderSent: Bool = false

    public func sendReminder() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let req = UpdateAppointmentRequest(status: AppointmentStatus.confirmed.rawValue)
            appointment = try await api.updateAppointment(id: appointment.id, req)
            reminderSent = true
            AppLog.ui.info("Reminder sent for appointment \(appointment.id, privacy: .public)")
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Failed to send reminder."
            AppLog.ui.error("Reminder send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - §10.6 Check-in / check-out

    /// Stamps the check-in time and transitions appointment to "confirmed".
    /// Persists via `PUT /api/v1/leads/appointments/:id` with `status: confirmed`.
    public func checkIn() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        checkedInAt = Date()
        do {
            let req = UpdateAppointmentRequest(status: AppointmentStatus.confirmed.rawValue)
            appointment = try await api.updateAppointment(id: appointment.id, req)
        } catch {
            checkedInAt = nil
            errorMessage = AppError.from(error).errorDescription ?? "Check-in failed."
            AppLog.ui.error("Appt check-in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stamps the check-out time and transitions appointment to "completed".
    /// Persists via `PUT /api/v1/leads/appointments/:id` with `status: completed`.
    public func checkOut() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        checkedOutAt = Date()
        do {
            let req = UpdateAppointmentRequest(status: AppointmentStatus.completed.rawValue)
            appointment = try await api.updateAppointment(id: appointment.id, req)
            markedCompleted = true
        } catch {
            checkedOutAt = nil
            errorMessage = AppError.from(error).errorDescription ?? "Check-out failed."
            AppLog.ui.error("Appt check-out failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - AppointmentDetailView

/// Detail view for a single appointment.
///
/// iPhone: full-width scroll view.
/// iPad: narrowed to ~720pt so content doesn't stretch across a 13" landscape.
public struct AppointmentDetailView: View {
    @State private var vm: AppointmentDetailViewModel
    @State private var showEdit = false
    @State private var showCancel = false
    @State private var showNoShowConfirm = false
    @State private var showCompletedConfirm = false
    // §10.6 Check-in / check-out confirm
    @State private var showCheckInConfirm = false
    @State private var showCheckOutConfirm = false
    // §10.2 Send reminder confirm
    @State private var showReminderConfirm = false
    @State private var showReminderSentToast = false

    private let api: APIClient
    private let onDismissAction: (() -> Void)?

    public init(appointment: Appointment, api: APIClient, onDismiss: (() -> Void)? = nil) {
        _vm = State(wrappedValue: AppointmentDetailViewModel(appointment: appointment, api: api))
        self.api = api
        self.onDismissAction = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if Platform.isCompact { compactContent } else { regularContent }
            }
        }
        .navigationTitle(vm.appointment.title ?? "Appointment")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showEdit) {
            AppointmentEditView(appointment: vm.appointment, api: api)
        }
        .sheet(isPresented: $showCancel) {
            AppointmentCancelView(appointment: vm.appointment, api: api) {
                onDismissAction?()
            }
        }
        .confirmationDialog("Mark as No-Show?", isPresented: $showNoShowConfirm, titleVisibility: .visible) {
            Button("Mark No-Show", role: .destructive) { Task { await vm.markNoShow() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will flag the customer as a no-show and update the appointment status.")
        }
        .confirmationDialog("Mark as Completed?", isPresented: $showCompletedConfirm, titleVisibility: .visible) {
            Button("Mark Completed") { Task { await vm.markCompleted() } }
            Button("Cancel", role: .cancel) {}
        }
        // §10.6 Check-in confirm
        .confirmationDialog("Customer arrived?", isPresented: $showCheckInConfirm, titleVisibility: .visible) {
            Button("Check in") { Task { await vm.checkIn() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stamps the arrival time and marks the appointment confirmed.")
        }
        // §10.6 Check-out confirm
        .confirmationDialog("Customer departed?", isPresented: $showCheckOutConfirm, titleVisibility: .visible) {
            Button("Check out") { Task { await vm.checkOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stamps the departure time and marks the appointment completed.")
        }
        // §10.2 Send reminder confirm
        .confirmationDialog("Send reminder to customer?", isPresented: $showReminderConfirm, titleVisibility: .visible) {
            Button("Send Reminder") {
                Task {
                    await vm.sendReminder()
                    if vm.reminderSent { showReminderSentToast = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("An SMS/email reminder will be sent to the customer.")
        }
        .alert("Reminder Sent", isPresented: $showReminderSentToast) {
            Button("OK") { showReminderSentToast = false }
        } message: {
            Text("The customer has been notified about their appointment.")
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout

    private var compactContent: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                statusBadge
                infoCard
                customerContactCard  // §10.2
                quickActionsSection
                notesCard
            }
            .padding(BrandSpacing.md)
        }
    }

    // MARK: - iPad layout (capped at 720pt)

    private var regularContent: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                statusBadge
                HStack(alignment: .top, spacing: BrandSpacing.lg) {
                    VStack(spacing: BrandSpacing.lg) {
                        infoCard
                        customerContactCard  // §10.2
                    }
                    .frame(maxWidth: 400)
                    VStack(spacing: BrandSpacing.lg) {
                        quickActionsSection
                        notesCard
                    }
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        HStack {
            if let status = vm.appointment.status {
                Text(status.capitalized)
                    .font(.brandLabelLarge())
                    .foregroundStyle(statusColor(status))
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(statusColor(status).opacity(0.12), in: Capsule())
                    .accessibilityLabel("Status: \(status)")
            }
            Spacer()
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            infoRow(icon: "calendar", label: "Date", value: formattedDate(vm.appointment.startTime))
            infoRow(icon: "clock",    label: "Duration", value: durationText)
            if let customer = vm.appointment.customerName {
                infoRow(icon: "person", label: "Customer", value: customer)
            }
            if let assigned = vm.appointment.assignedName {
                infoRow(icon: "person.badge.key", label: "Technician", value: assigned)
            }
            // §10.2 — type, location, recurrence
            if let typeName = vm.appointment.typeDisplayName {
                infoRow(icon: "tag", label: "Type", value: typeName)
            }
            if vm.appointment.locationId != nil {
                infoRow(icon: "mappin.circle", label: "Location", value: "Location #\(vm.appointment.locationId!)")
            }
            if let recurrence = vm.appointment.recurrence, !recurrence.isEmpty {
                infoRow(icon: "arrow.clockwise", label: "Repeats", value: recurrence)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: - §10.2 Customer contact card (call / SMS / email)

    @ViewBuilder
    private var customerContactCard: some View {
        let phone = vm.appointment.customerPhone
        let email = vm.appointment.customerEmail
        if phone != nil || email != nil {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Contact Customer")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                HStack(spacing: BrandSpacing.md) {
                    if let phone {
                        Link(destination: URL(string: "tel:\(phone.filter { !$0.isWhitespace })")!) {
                            Label("Call", systemImage: "phone.fill")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.white)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.sm)
                                .background(Color.bizarreSuccess, in: Capsule())
                        }
                        .accessibilityLabel("Call customer: \(phone)")

                        Link(destination: URL(string: "sms:\(phone.filter { !$0.isWhitespace })")!) {
                            Label("SMS", systemImage: "message.fill")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.white)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.sm)
                                .background(Color.bizarreOrange, in: Capsule())
                        }
                        .accessibilityLabel("Send SMS to customer: \(phone)")
                    }
                    if let email {
                        Link(destination: URL(string: "mailto:\(email)")!) {
                            Label("Email", systemImage: "envelope.fill")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.white)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.sm)
                                .background(.bizarreOnSurfaceMuted, in: Capsule())
                        }
                        .accessibilityLabel("Email customer: \(email)")
                    }
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
    }

    // MARK: - Quick actions (glass chips)

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Quick Actions")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: BrandSpacing.sm
            ) {
                // §10.6 Check-in chip — shown until customer arrives
                if vm.checkedInAt == nil {
                    actionChip(icon: "person.badge.plus",    label: "Customer Arrived", color: .bizarreSuccess) {
                        showCheckInConfirm = true
                    }
                } else {
                    // §10.6 Check-out chip — shown after check-in
                    actionChip(icon: "person.badge.minus",   label: "Customer Departed", color: .bizarreOrange) {
                        showCheckOutConfirm = true
                    }
                }

                actionChip(icon: "calendar.badge.plus",  label: "Reschedule",  color: .bizarreOrange) {
                    showEdit = true
                }
                .keyboardShortcut("E", modifiers: .command)

                actionChip(icon: "checkmark.circle",     label: "Completed",   color: .bizarreSuccess) {
                    showCompletedConfirm = true
                }

                actionChip(icon: "person.slash",         label: "No-Show",     color: .bizarreWarning) {
                    showNoShowConfirm = true
                }

                actionChip(icon: "xmark.circle",         label: "Cancel",      color: .bizarreError,
                           isDestructive: true) {
                    showCancel = true
                }

                // §10.2 Send reminder chip
                actionChip(icon: "bell.badge",           label: "Send Reminder", color: .bizarreOrange) {
                    showReminderConfirm = true
                }
            }

            // §10.6 Timestamps
            if let checkedIn = vm.checkedInAt {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "clock.badge.checkmark").foregroundStyle(.bizarreSuccess).accessibilityHidden(true)
                    Text("Arrived: \(checkedIn.formatted(date: .omitted, time: .shortened))")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let co = vm.checkedOutAt {
                        Text("· Departed: \(co.formatted(date: .omitted, time: .shortened))")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(checkInA11y(checkedIn: checkedIn, checkedOut: vm.checkedOutAt))
            }
        }
    }

    private func checkInA11y(checkedIn: Date, checkedOut: Date?) -> String {
        var parts = ["Arrived at \(checkedIn.formatted(date: .omitted, time: .shortened))"]
        if let co = checkedOut { parts.append("Departed at \(co.formatted(date: .omitted, time: .shortened))") }
        return parts.joined(separator: ", ")
    }

    private func actionChip(
        icon: String,
        label: String,
        color: Color,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isBusy = vm.isLoading
        return Button(action: action) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isBusy ? Color.bizarreOnSurfaceMuted : color)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isBusy ? Color.bizarreOnSurfaceMuted : .bizarreOnSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(label)
        #if !os(macOS)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Notes card

    @ViewBuilder
    private var notesCard: some View {
        if let notes = vm.appointment.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Label("Notes", systemImage: "note.text")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(notes)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "scheduled":   return .bizarreOrange
        case "confirmed":   return .bizarreSuccess
        case "completed":   return .bizarreSuccess
        case "cancelled":   return .bizarreError
        case "no-show":     return .bizarreWarning
        default:            return .bizarreOnSurfaceMuted
        }
    }

    private func formattedDate(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
            ?? {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.timeZone = TimeZone(identifier: "UTC")
                f.locale = Locale(identifier: "en_US_POSIX")
                return f.date(from: raw)
            }()
        guard let date else { return String(raw.prefix(16)) }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private var durationText: String {
        guard
            let rawS = vm.appointment.startTime,
            let rawE = vm.appointment.endTime
        else { return "—" }
        let iso = ISO8601DateFormatter()
        guard
            let s = iso.date(from: rawS) ?? sqlDate(rawS),
            let e = iso.date(from: rawE) ?? sqlDate(rawE)
        else { return "—" }
        let secs = e.timeIntervalSince(s)
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins) min" }
        let hours = mins / 60
        let rem   = mins % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }

    private func sqlDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: raw)
    }
}
