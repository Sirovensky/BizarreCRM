import SwiftUI
import Observation
import UserNotifications
import Core
import DesignSystem

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Category preference model

/// Per-category in-app toggle state.  The system permission is the hard gate;
/// this is a soft client-side suppression that the user can layer on top.
public struct CategoryPreference: Identifiable, Sendable, Equatable {
    public let id: NotificationCategoryID
    public var enabled: Bool

    public var displayName: String {
        switch id {
        case .ticketUpdate:        return "Ticket Updates"
        case .smsReply:            return "SMS Messages"
        case .lowStock:            return "Low Stock Alerts"
        case .appointmentReminder: return "Appointment Reminders"
        case .paymentReceived:     return "Payments"
        case .deadLetterAlert:     return "Sync Alerts"
        case .mention:             return "Mentions"
        case .scheduleChange:      return "Schedule Changes"
        }
    }

    public var iconName: String {
        switch id {
        case .ticketUpdate:        return "wrench.and.screwdriver"
        case .smsReply:            return "message.fill"
        case .lowStock:            return "shippingbox.fill"
        case .appointmentReminder: return "calendar.badge.clock"
        case .paymentReceived:     return "creditcard.fill"
        case .deadLetterAlert:     return "exclamationmark.triangle.fill"
        case .mention:             return "at"
        case .scheduleChange:      return "calendar.badge.exclamationmark"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class NotificationSettingsViewModel {

    // MARK: - Public state

    public private(set) var preferences: [CategoryPreference] = NotificationCategoryID
        .allCases
        .map { CategoryPreference(id: $0, enabled: true) }

    public private(set) var systemAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    public private(set) var isLoadingStatus: Bool = false

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Toggle a category preference.
    public func toggle(id: NotificationCategoryID) {
        guard let idx = preferences.firstIndex(where: { $0.id == id }) else { return }
        preferences[idx] = CategoryPreference(id: id, enabled: !preferences[idx].enabled)
    }

    /// Fetch the current system authorization status.
    public func refreshSystemStatus() async {
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemAuthorizationStatus = settings.authorizationStatus
    }

    /// Human-readable description of the system status.
    public var systemStatusDescription: String {
        switch systemAuthorizationStatus {
        case .authorized:     return "Notifications are enabled"
        case .denied:         return "Notifications are disabled in System Settings"
        case .notDetermined:  return "Notification permission not yet requested"
        case .provisional:    return "Notifications enabled (provisional)"
        case .ephemeral:      return "Notifications enabled (ephemeral)"
        @unknown default:     return "Unknown status"
        }
    }

    /// True when the user has denied push at the system level.
    public var isDenied: Bool { systemAuthorizationStatus == .denied }
}

// MARK: - View

public struct NotificationSettingsView: View {

    @State private var vm: NotificationSettingsViewModel

    public init(viewModel: NotificationSettingsViewModel = NotificationSettingsViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Notification Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .task { await vm.refreshSystemStatus() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        List {
            systemStatusSection
            categoriesSection
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - System status section

    @ViewBuilder
    private var systemStatusSection: some View {
        Section {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: vm.isDenied ? "bell.slash.fill" : "bell.fill")
                    .foregroundStyle(vm.isDenied ? Color.bizarreError : Color.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(vm.systemStatusDescription)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel(vm.systemStatusDescription)

                    if vm.isDenied {
                        Button("Open System Settings") {
                            openSystemSettings()
                        }
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Open System Settings to enable notifications")
                        .accessibilityHint("Opens the iOS Settings app")
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("System Permission")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Categories section

    @ViewBuilder
    private var categoriesSection: some View {
        Section {
            ForEach(vm.preferences) { pref in
                categoryRow(pref: pref)
            }
        } header: {
            Text("Notification Categories")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Disabling a category suppresses in-app banners. System-level alerts may still appear.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private func categoryRow(pref: CategoryPreference) -> some View {
        Toggle(isOn: Binding(
            get: { pref.enabled },
            set: { _ in vm.toggle(id: pref.id) }
        )) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: pref.iconName)
                    .foregroundStyle(pref.enabled ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(pref.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .tint(.bizarreOrange)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("\(pref.displayName), \(pref.enabled ? "enabled" : "disabled")")
        .accessibilityHint("Double-tap to \(pref.enabled ? "disable" : "enable")")
        .accessibilityIdentifier("notifSettings.category.\(pref.id.rawValue)")
    }

    // MARK: - Helpers

    private func openSystemSettings() {
#if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#endif
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
#endif
