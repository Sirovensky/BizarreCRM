import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentContextMenu
//
// Context-menu button group for an Appointment row.
//
// Provides four actions:
//   Open           → triggers onOpen callback (navigate to detail)
//   Reschedule     → presents AppointmentEditView sheet
//   Cancel         → presents AppointmentCancelView sheet
//   Send Reminder  → fires the reminder-policy endpoint and shows a confirmation toast
//
// Usage (attach to a list row):
//   .contextMenu {
//       AppointmentContextMenu(appointment: appt, api: api) { Task { await reload() } }
//   }
//
// All network side-effects are contained inside this view's state; the caller
// only receives `onRefresh` so the list can reload after a mutation.

// MARK: - AppointmentContextMenuViewModel

@MainActor
@Observable
final class AppointmentContextMenuViewModel {

    private(set) var isSendingReminder = false
    private(set) var reminderSent = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let onRefresh: () -> Void

    init(api: APIClient, onRefresh: @escaping () -> Void) {
        self.api = api
        self.onRefresh = onRefresh
    }

    /// POSTs a reminder for the given appointment by updating its status to "confirmed"
    /// (server triggers the reminder notification on that transition).
    /// Falls back to no-op if the appointment is already confirmed.
    func sendReminder(for appointment: Appointment) async {
        guard !isSendingReminder else { return }
        isSendingReminder = true
        errorMessage = nil
        defer { isSendingReminder = false }
        do {
            // Sending a reminder is modeled as a status re-confirmation.
            // The server sends the reminder SMS/email on every PUT that contains status=confirmed.
            let req = UpdateAppointmentRequest(status: AppointmentStatus.confirmed.rawValue)
            _ = try await api.updateAppointment(id: appointment.id, req)
            reminderSent = true
            onRefresh()
            AppLog.ui.info("Reminder sent for appointment \(appointment.id, privacy: .public)")
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Failed to send reminder."
            AppLog.ui.error("Reminder send failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - AppointmentContextMenu

/// Context-menu contents for an Appointment row.
///
/// Embed inside `.contextMenu { }` on a List row. Sheets are managed
/// internally so they don't require the parent to carry sheet state.
public struct AppointmentContextMenu: View {

    public let appointment: Appointment
    public let api: APIClient
    public let onRefresh: () -> Void

    @State private var vmCtx: AppointmentContextMenuViewModel
    @State private var showReschedule = false
    @State private var showCancel = false
    @State private var showReminderConfirm = false

    public init(
        appointment: Appointment,
        api: APIClient,
        onRefresh: @escaping () -> Void
    ) {
        self.appointment = appointment
        self.api = api
        self.onRefresh = onRefresh
        _vmCtx = State(wrappedValue: AppointmentContextMenuViewModel(api: api, onRefresh: onRefresh))
    }

    public var body: some View {
        Group {
            // Open / detail
            Button {
                // Navigation is handled by the parent (NavigationSplitView selection binding).
                // Emitting onRefresh here acts as a tap-through signal to select the appointment.
                onRefresh()
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
            }
            .accessibilityLabel("Open appointment")

            Divider()

            // Reschedule
            Button {
                showReschedule = true
            } label: {
                Label("Reschedule", systemImage: "calendar.badge.clock")
            }
            .accessibilityLabel("Reschedule appointment")

            // Cancel
            Button(role: .destructive) {
                showCancel = true
            } label: {
                Label("Cancel Appointment", systemImage: "xmark.circle")
            }
            .accessibilityLabel("Cancel appointment")

            Divider()

            // Send reminder
            Button {
                showReminderConfirm = true
            } label: {
                if vmCtx.isSendingReminder {
                    Label("Sending…", systemImage: "ellipsis.circle")
                } else if vmCtx.reminderSent {
                    Label("Reminder Sent", systemImage: "checkmark.circle")
                } else {
                    Label("Send Reminder", systemImage: "bell.badge")
                }
            }
            .disabled(vmCtx.isSendingReminder || isCancelledOrComplete)
            .accessibilityLabel(vmCtx.reminderSent ? "Reminder already sent" : "Send reminder to customer")
        }
        // Sheets rendered outside context menu so they can present properly.
        .sheet(isPresented: $showReschedule) {
            AppointmentEditView(appointment: appointment, api: api)
        }
        .sheet(isPresented: $showCancel) {
            AppointmentCancelView(appointment: appointment, api: api, onCancelled: onRefresh)
        }
        .confirmationDialog(
            "Send Reminder?",
            isPresented: $showReminderConfirm,
            titleVisibility: .visible
        ) {
            Button("Send Reminder") {
                Task { await vmCtx.sendReminder(for: appointment) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will send a reminder notification to the customer for \(appointment.title ?? "this appointment").")
        }
    }

    // MARK: - Helpers

    private var isCancelledOrComplete: Bool {
        switch appointment.status?.lowercased() {
        case "cancelled", "completed", "no-show": return true
        default: return false
        }
    }
}
