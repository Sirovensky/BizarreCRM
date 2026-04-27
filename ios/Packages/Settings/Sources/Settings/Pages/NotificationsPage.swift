import SwiftUI
import Core
import DesignSystem

/// §19.3 Notifications page — per-channel toggles, quiet hours, critical overrides.
public struct NotificationsPage: View {

    // MARK: Per-channel toggles (local UserDefaults mirror; server sync via Notifications pkg)

    @State private var newSmsEnabled: Bool = true
    @State private var newTicketEnabled: Bool = true
    @State private var ticketAssignedEnabled: Bool = true
    @State private var paymentReceivedEnabled: Bool = true
    @State private var paymentFailedEnabled: Bool = true
    @State private var appointmentReminderEnabled: Bool = true
    @State private var lowStockEnabled: Bool = false
    @State private var dailySummaryEnabled: Bool = false

    // MARK: §19.3 Quiet hours

    @State private var quietHoursEnabled: Bool = false
    @State private var quietStart: Date = Calendar.current.date(
        bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quietEnd: Date = Calendar.current.date(
        bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()

    // MARK: §19.3 Critical overrides (bypass quiet hours)

    @State private var paymentFailedCritical: Bool = true
    @State private var mentionCritical: Bool = false

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

            // MARK: - §19.3 Quiet hours

            Section {
                Toggle("Enable quiet hours", isOn: $quietHoursEnabled)
                    .accessibilityIdentifier("notif.quietHours.enabled")

                if quietHoursEnabled {
                    DatePicker("Start", selection: $quietStart, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("notif.quietHours.start")
                    DatePicker("End", selection: $quietEnd, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("notif.quietHours.end")
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("Notifications are suppressed during quiet hours except for critical overrides below.")
            }

            // MARK: - §19.3 Critical overrides

            if quietHoursEnabled {
                Section {
                    Toggle("Payment failed", isOn: $paymentFailedCritical)
                        .accessibilityIdentifier("notif.critical.paymentFailed")
                    Toggle("@Mention", isOn: $mentionCritical)
                        .accessibilityIdentifier("notif.critical.mention")
                } header: {
                    Text("Critical overrides")
                } footer: {
                    Text("These events bypass quiet hours when enabled.")
                }
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
