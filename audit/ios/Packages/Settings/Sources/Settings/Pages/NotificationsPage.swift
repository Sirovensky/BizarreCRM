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

    // MARK: §19.3 Notification grouping

    /// When enabled, repeated pushes from the same thread/ticket are collapsed
    /// into a single notification group with a message-count badge.
    @State private var groupingEnabled: Bool = true

    // MARK: §19.3 Push-to-talk (PTT) volume

    /// In-app speaker volume used when a staff member receives a PTT audio burst.
    /// 0.0 = silent, 1.0 = full device volume. Stored in UserDefaults.
    @State private var pttVolume: Double = 0.8

    public init() {
        // Load persisted PTT volume (defaults to 0.8 if never set).
        let saved = UserDefaults.standard.object(forKey: "notif.pttVolume") as? Double
        _pttVolume = State(initialValue: saved ?? 0.8)
        let savedGrouping = UserDefaults.standard.object(forKey: "notif.grouping") as? Bool
        _groupingEnabled = State(initialValue: savedGrouping ?? true)
    }

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

            // MARK: - §19.3 Grouping

            Section {
                Toggle("Group related notifications", isOn: $groupingEnabled)
                    .accessibilityIdentifier("notif.grouping.enabled")
                    .onChange(of: groupingEnabled) { _, v in
                        UserDefaults.standard.set(v, forKey: "notif.grouping")
                    }
            } header: {
                Text("Grouping")
            } footer: {
                Text(groupingEnabled
                    ? "Repeated alerts from the same ticket or SMS thread are collapsed into one group with a message count badge."
                    : "Each notification appears individually in Notification Center.")
            }

            // MARK: - §19.3 Push-to-talk volume

            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    HStack {
                        Label("PTT volume", systemImage: "speaker.wave.2.fill")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .accessibilityHidden(true)
                        Spacer()
                        Text(pttVolume < 0.01 ? "Muted" : "\(Int(pttVolume * 100))%")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    Slider(value: $pttVolume, in: 0...1, step: 0.05)
                        .tint(.bizarreOrange)
                        .accessibilityLabel(
                            pttVolume < 0.01
                            ? "Push to talk volume, muted"
                            : "Push to talk volume, \(Int(pttVolume * 100)) percent"
                        )
                        .accessibilityIdentifier("notif.pttVolume")
                        .onChange(of: pttVolume) { _, v in
                            UserDefaults.standard.set(v, forKey: "notif.pttVolume")
                        }
                }
            } header: {
                Text("Push-to-talk")
            } footer: {
                Text("Controls the playback volume of incoming PTT audio bursts within the app. Device volume also applies.")
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
