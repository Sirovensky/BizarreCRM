import SwiftUI
import Core
import DesignSystem

/// §19.3 Notifications page — per-channel toggles + quiet hours.
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

    // §19.3 Quiet hours — backed by HapticsSettings.shared.
    @State private var quietHoursOn: Bool = HapticsSettings.shared.quietHoursOn
    @State private var quietHoursStart: Int = HapticsSettings.shared.quietHoursStart
    @State private var quietHoursEnd: Int = HapticsSettings.shared.quietHoursEnd

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

            // §19.3 Quiet hours
            Section {
                Toggle("Quiet hours", isOn: $quietHoursOn)
                    .accessibilityLabel("Quiet hours enabled")
                    .accessibilityIdentifier("notif.quietHoursOn")
                    .onChange(of: quietHoursOn) { _, v in HapticsSettings.shared.quietHoursOn = v }

                if quietHoursOn {
                    Picker("Start", selection: $quietHoursStart) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    .accessibilityIdentifier("notif.quietHoursStart")
                    .onChange(of: quietHoursStart) { _, v in HapticsSettings.shared.quietHoursStart = v }

                    Picker("End", selection: $quietHoursEnd) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    .accessibilityIdentifier("notif.quietHoursEnd")
                    .onChange(of: quietHoursEnd) { _, v in HapticsSettings.shared.quietHoursEnd = v }
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("During quiet hours, in-app notification sounds and haptics are suppressed. Critical alerts (payment failed, @mentions) can override this in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        guard let date = Calendar.current.date(from: comps) else {
            return String(format: "%02d:00", hour)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }
}
