import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §19.3 Extended Notifications Settings
//
// Extends NotificationsPage.swift with:
//   - Delivery medium per channel (Push / Email / SMS / In-app only)
//   - Quiet hours (start/end time + critical overrides)
//   - Test push (admin-only)

// MARK: - Models

public enum DeliveryMedium: String, CaseIterable, Sendable, Identifiable {
    case push    = "push"
    case email   = "email"
    case sms     = "sms"
    case inApp   = "in_app"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .push:  return "Push"
        case .email: return "Email"
        case .sms:   return "SMS"
        case .inApp: return "In-app only"
        }
    }
    public var icon: String {
        switch self {
        case .push:  return "bell.badge"
        case .email: return "envelope"
        case .sms:   return "message"
        case .inApp: return "app.badge"
        }
    }
}

public struct ChannelDeliveryPrefs: Sendable {
    public let channel: String
    public var mediums: Set<DeliveryMedium>
    public init(channel: String, mediums: Set<DeliveryMedium> = [.push, .inApp]) {
        self.channel = channel
        self.mediums = mediums
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class NotificationsExtendedViewModel: Sendable {
    // Quiet hours
    var quietHoursEnabled: Bool = false
    var quietHoursStart: Date = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    var quietHoursEnd: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    var criticalOverrideEnabled: Bool = true  // "Payment failed" + "@mention" bypass quiet hours

    // Delivery mediums — map channelKey → set of mediums
    var channelMediums: [String: Set<DeliveryMedium>] = [
        "sms_inbound":            [.push, .inApp],
        "ticket_new":             [.push, .inApp],
        "ticket_assigned":        [.push, .inApp],
        "payment_received":       [.push, .inApp],
        "payment_failed":         [.push, .inApp],
        "appointment_reminder":   [.push, .inApp],
        "low_stock":              [.inApp],
        "daily_summary":          [.push, .inApp],
    ]

    var isSending: Bool = false
    var testPushSent: Bool = false

    private let defaults: UserDefaults
    private let api: APIClient
    public let isAdmin: Bool

    public init(defaults: UserDefaults = .standard, api: APIClient, isAdmin: Bool = false) {
        self.defaults = defaults
        self.api = api
        self.isAdmin = isAdmin
        load()
    }

    private func load() {
        quietHoursEnabled = defaults.bool(forKey: "notif.quietHours.enabled")
        criticalOverrideEnabled = defaults.bool(forKey: "notif.quietHours.criticalOverride") != false
        if let start = defaults.object(forKey: "notif.quietHours.start") as? Date {
            quietHoursStart = start
        }
        if let end = defaults.object(forKey: "notif.quietHours.end") as? Date {
            quietHoursEnd = end
        }
    }

    func save() {
        defaults.set(quietHoursEnabled, forKey: "notif.quietHours.enabled")
        defaults.set(criticalOverrideEnabled, forKey: "notif.quietHours.criticalOverride")
        defaults.set(quietHoursStart, forKey: "notif.quietHours.start")
        defaults.set(quietHoursEnd, forKey: "notif.quietHours.end")
        Task {
            try? await api.putNotifSettings(NotifSettingsWire(
                quietHoursEnabled: quietHoursEnabled,
                quietHoursStart: timeString(quietHoursStart),
                quietHoursEnd: timeString(quietHoursEnd),
                criticalOverride: criticalOverrideEnabled
            ))
        }
    }

    func sendTestPush() async {
        isSending = true
        defer { isSending = false }
        try? await api.postTestPush()
        testPushSent = true
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // API wrappers live in NotificationsSettingsEndpoints.swift (§20 containment rule)
}

// MARK: - View

/// §19.3 Extended notification settings page — quiet hours, delivery medium, test push.
public struct NotificationsExtendedPage: View {
    @State private var vm: NotificationsExtendedViewModel
    @State private var showTestConfirm = false

    public init(api: APIClient, isAdmin: Bool = false, defaults: UserDefaults = .standard) {
        _vm = State(wrappedValue: NotificationsExtendedViewModel(
            defaults: defaults, api: api, isAdmin: isAdmin
        ))
    }

    public var body: some View {
        Form {
            // §19.3 Quiet hours
            Section {
                Toggle("Enable quiet hours", isOn: $vm.quietHoursEnabled)
                    .accessibilityIdentifier("notif.quietHoursEnabled")
                if vm.quietHoursEnabled {
                    DatePicker(
                        "Start",
                        selection: $vm.quietHoursStart,
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("notif.quietHoursStart")
                    DatePicker(
                        "End",
                        selection: $vm.quietHoursEnd,
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("notif.quietHoursEnd")
                    Toggle("Critical overrides (payment failed, @mention)", isOn: $vm.criticalOverrideEnabled)
                        .accessibilityIdentifier("notif.criticalOverride")
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                if vm.quietHoursEnabled {
                    Text("Pushes are suppressed between these times. Critical events can still come through.")
                        .font(.caption)
                }
            }

            // §19.3 Delivery medium per channel
            Section {
                ForEach(Array(channelLabels.sorted(by: { $0.key < $1.key })), id: \.key) { key, label in
                    DeliveryMediumRow(
                        label: label,
                        mediums: Binding(
                            get: { vm.channelMediums[key, default: [.push, .inApp]] },
                            set: { vm.channelMediums[key] = $0 }
                        )
                    )
                }
            } header: {
                Text("Delivery channel")
            } footer: {
                Text("Choose where each event is delivered. SMS and Email to staff are off by default.")
                    .font(.caption)
            }

            // §19.3 Test push (admin only)
            if vm.isAdmin {
                Section {
                    Button {
                        showTestConfirm = true
                    } label: {
                        Label("Send test push", systemImage: "bell.badge")
                            .foregroundStyle(.bizarreOrange)
                    }
                    .disabled(vm.isSending)
                    .accessibilityIdentifier("notif.testPush")
                } footer: {
                    if vm.testPushSent {
                        Text("Test notification sent to this device.")
                            .foregroundStyle(.bizarreSuccess)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { vm.save() }
                    .accessibilityIdentifier("notif.save")
            }
        }
        .alert("Send test push?", isPresented: $showTestConfirm) {
            Button("Send") { Task { await vm.sendTestPush() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A test notification will be delivered to this device.")
        }
    }

    private let channelLabels: [String: String] = [
        "sms_inbound":            "New SMS inbound",
        "ticket_new":             "New ticket",
        "ticket_assigned":        "Ticket assigned to me",
        "payment_received":       "Payment received",
        "payment_failed":         "Payment failed",
        "appointment_reminder":   "Appointment reminder",
        "low_stock":              "Low stock alert",
        "daily_summary":          "Daily summary",
    ]
}

// MARK: - Delivery medium row

private struct DeliveryMediumRow: View {
    let label: String
    @Binding var mediums: Set<DeliveryMedium>

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            HStack(spacing: BrandSpacing.sm) {
                ForEach(DeliveryMedium.allCases) { medium in
                    let selected = mediums.contains(medium)
                    Button {
                        if selected {
                            mediums.remove(medium)
                        } else {
                            mediums.insert(medium)
                        }
                    } label: {
                        Label(medium.label, systemImage: medium.icon)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 13))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                selected ? Color.bizarreOrange : Color.bizarreSurface2,
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? .white : .bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel("\(medium.label)\(selected ? ", enabled" : ", disabled")")
                    .accessibilityIdentifier("notif.medium.\(label.lowercased()).\(medium.rawValue)")
                }
                Spacer()
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}
