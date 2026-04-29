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
        case .paymentFailed:       return "Payment Failed"
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
        case .paymentFailed:       return "creditcard.trianglebadge.exclamationmark"
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

    // MARK: - Re-prompt copy (§13.2)

    /// Short rationale shown before the system permission sheet re-prompt.
    ///
    /// Displayed in the in-app rationale sheet (`PermissionRationaleSheet`) that
    /// appears before calling `UNUserNotificationCenter.requestAuthorization()` a
    /// second time.  Must be concise and explain the concrete benefit so users opt in.
    public static let repromptTitle = "Stay on top of your shop"

    /// Body text for the re-prompt rationale sheet.
    public static let repromptBody =
        "Enable notifications to get instant alerts for new SMS messages, " +
        "ticket updates, payment receipts, and appointment reminders — " +
        "so nothing slips through while you're away from the desk."

    /// CTA label on the rationale sheet's primary button (leads to system prompt).
    public static let repromptCTA = "Enable Notifications"

    /// Label for the secondary "maybe later" button on the rationale sheet.
    public static let repromptSkip = "Not Now"
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

// MARK: - PermissionRationaleSheet (§13.2 re-prompt copy)

/// Modal rationale sheet shown before re-requesting notification permission.
///
/// Present this as a `.sheet` when the user taps a contextual prompt
/// (e.g. a banner inside the ticket list) and their current auth status is
/// `.notDetermined` or `.denied`.  The sheet explains the value, then either
/// opens the system prompt (`.notDetermined`) or Settings (`.denied`).
///
/// ```swift
/// .sheet(isPresented: $showRationale) {
///     PermissionRationaleSheet { granted in
///         // handle outcome
///     }
/// }
/// ```
public struct PermissionRationaleSheet: View {

    public var onDismiss: ((_ granted: Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    public init(onDismiss: ((_ granted: Bool) -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text(NotificationSettingsViewModel.repromptTitle)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text(NotificationSettingsViewModel.repromptBody)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, BrandSpacing.xl)

            Spacer()

            VStack(spacing: BrandSpacing.sm) {
                Button {
                    Task { await requestOrOpenSettings() }
                } label: {
                    if isRequesting {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        Text(NotificationSettingsViewModel.repromptCTA)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(isRequesting)
                .accessibilityIdentifier("notifRationale.enableButton")

                Button(NotificationSettingsViewModel.repromptSkip) {
                    dismiss()
                    onDismiss?(false)
                }
                .buttonStyle(.plain)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("notifRationale.skipButton")
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.bottom, BrandSpacing.xl)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func requestOrOpenSettings() async {
        isRequesting = true
        defer { isRequesting = false }

        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()

        if current.authorizationStatus == .denied {
            // Cannot re-prompt; guide user to Settings.
#if canImport(UIKit)
            await MainActor.run {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
#endif
            dismiss()
            onDismiss?(false)
        } else {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            dismiss()
            onDismiss?(granted)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}

#Preview("Rationale Sheet") {
    Color.bizarreSurfaceBase
        .sheet(isPresented: .constant(true)) {
            PermissionRationaleSheet()
        }
}
#endif
