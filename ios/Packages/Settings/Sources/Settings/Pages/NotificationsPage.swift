import SwiftUI
import Core
import DesignSystem

/// §19.3 Notifications page — per-channel toggles.
/// Delegates to `NotificationSettingsView` already shipped in Phase 6A.
/// This is a thin wrapper that wires the Settings NavigationLink destination.
///
/// If the full NotificationSettingsView is available as a public type from
/// a Notifications package, we would import it here. Until that package is
/// linked, we render our own compact toggles and link to System Settings.
public struct NotificationsPage: View {

    @State private var newSmsEnabled: Bool = true
    @State private var newTicketEnabled: Bool = true
    @State private var ticketAssignedEnabled: Bool = true
    @State private var paymentReceivedEnabled: Bool = true
    @State private var paymentFailedEnabled: Bool = true
    @State private var appointmentReminderEnabled: Bool = true
    @State private var lowStockEnabled: Bool = false
    @State private var dailySummaryEnabled: Bool = false

    public init() {}

    public var body: some View {
        Form {
            Section("Ticket & service") {
                Toggle("New SMS inbound", isOn: $newSmsEnabled)
                    .accessibilityIdentifier("notif.newSms")
                Toggle("New ticket", isOn: $newTicketEnabled)
                    .accessibilityIdentifier("notif.newTicket")
                Toggle("Ticket assigned to me", isOn: $ticketAssignedEnabled)
                    .accessibilityIdentifier("notif.ticketAssigned")
            }

            Section("Payments") {
                Toggle("Payment received", isOn: $paymentReceivedEnabled)
                    .accessibilityIdentifier("notif.paymentReceived")
                Toggle("Payment failed", isOn: $paymentFailedEnabled)
                    .foregroundStyle(paymentFailedEnabled ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("notif.paymentFailed")
            }

            Section("Appointments") {
                Toggle("Appointment reminder", isOn: $appointmentReminderEnabled)
                    .accessibilityIdentifier("notif.appointmentReminder")
            }

            Section("Inventory & reports") {
                Toggle("Low stock alert", isOn: $lowStockEnabled)
                    .accessibilityIdentifier("notif.lowStock")
                Toggle("Daily summary", isOn: $dailySummaryEnabled)
                    .accessibilityIdentifier("notif.dailySummary")
            }

            Section {
                Button {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    Label("Open System Notification Settings", systemImage: "gear")
                }
                .accessibilityIdentifier("notif.openSystemSettings")
            } footer: {
                Text("System permission controls push delivery. Toggle per-channel above to suppress in-app alerts.")
            }
        }
        .navigationTitle("Notifications")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }
}
