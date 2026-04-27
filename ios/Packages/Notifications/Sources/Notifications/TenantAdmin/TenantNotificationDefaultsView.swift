import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §70.2 Tenant notification defaults admin UI

// MARK: - Models

/// A single tenant-level override for a notification event default.
/// Mirrors server shape: `PUT /notifications/tenant-defaults`.
public struct TenantNotificationOverride: Identifiable, Equatable, Codable, Sendable {
    public var id: String { event.rawValue }
    public let event: NotificationEvent
    /// Whether to shift the default push delivery on for all staff.
    public var defaultPush: Bool
    /// Whether to shift the default in-app delivery on.
    public var defaultInApp: Bool
    /// Whether to shift the default email to staff on.
    public var defaultEmail: Bool
    /// Whether to shift the default SMS to staff on.
    public var defaultSms: Bool

    public init(event: NotificationEvent,
                defaultPush: Bool, defaultInApp: Bool,
                defaultEmail: Bool, defaultSms: Bool) {
        self.event      = event
        self.defaultPush    = defaultPush
        self.defaultInApp   = defaultInApp
        self.defaultEmail   = defaultEmail
        self.defaultSms     = defaultSms
    }
}

// MARK: - Repository protocol

public protocol TenantNotificationDefaultsRepository: Sendable {
    func fetchTenantDefaults() async throws -> [TenantNotificationOverride]
    func saveTenantDefaults(_ overrides: [TenantNotificationOverride]) async throws
}

// MARK: - ViewModel

@MainActor
@Observable
public final class TenantNotificationDefaultsViewModel: Sendable {

    public private(set) var overrides: [TenantNotificationOverride] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var isDirty = false
    private(set) var isSaving = false

    @ObservationIgnored private let repo: any TenantNotificationDefaultsRepository

    public init(repo: any TenantNotificationDefaultsRepository) {
        self.repo = repo
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            overrides = try await repo.fetchTenantDefaults()
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("TenantNotificationDefaultsVM: load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func update(event: NotificationEvent, keyPath: WritableKeyPath<TenantNotificationOverride, Bool>, value: Bool) {
        guard let idx = overrides.firstIndex(where: { $0.event == event }) else { return }
        overrides[idx][keyPath: keyPath] = value
        isDirty = true
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            try await repo.saveTenantDefaults(overrides)
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("TenantNotificationDefaultsVM: save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delta: events where tenant override diverges from Bizarre's shipped defaults (push-only).
    public var deltaFromShipped: [TenantNotificationOverride] {
        overrides.filter { o in
            // Shipped default: push=true, inApp=true, email=false, sms=false
            o.defaultEmail || o.defaultSms || !o.defaultPush || !o.defaultInApp
        }
    }
}

// MARK: - View

/// §70.2 — Admin view: shift tenant-wide notification defaults (email/SMS opt-in
/// per event category). Per-user overrides in Settings §19.3 still take precedence.
public struct TenantNotificationDefaultsView: View {
    @State private var vm: TenantNotificationDefaultsViewModel

    public init(vm: TenantNotificationDefaultsViewModel) {
        _vm = State(initialValue: vm)
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading tenant notification defaults")
            } else if let err = vm.errorMessage, vm.overrides.isEmpty {
                errorState(err)
            } else {
                overridesList
            }
        }
        .navigationTitle("Staff Notification Defaults")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            if vm.isDirty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task { await vm.save() }
                    }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("tenantNotifDefaults.save")
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Overrides list

    private var overridesList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Shift the default delivery channel for all staff. Push + In-App are on by default. Email and SMS to staff are off by default.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if !vm.deltaFromShipped.isEmpty {
                        HStack(spacing: BrandSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.bizarreWarning)
                                .accessibilityHidden(true)
                            Text("\(vm.deltaFromShipped.count) events diverge from Bizarre's defaults")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreWarning)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(vm.deltaFromShipped.count) events diverge from Bizarre's defaults")
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            }

            ForEach(NotificationEventGroup.allGroups, id: \.title) { group in
                let groupOverrides = vm.overrides.filter { group.events.contains($0.event) }
                if !groupOverrides.isEmpty {
                    Section(group.title) {
                        ForEach(groupOverrides) { override in
                            TenantOverrideRow(
                                override: override,
                                onTogglePush: { v in vm.update(event: override.event, keyPath: \.defaultPush, value: v) },
                                onToggleInApp: { v in vm.update(event: override.event, keyPath: \.defaultInApp, value: v) },
                                onToggleEmail: { v in vm.update(event: override.event, keyPath: \.defaultEmail, value: v) },
                                onToggleSms: { v in vm.update(event: override.event, keyPath: \.defaultSms, value: v) }
                            )
                            .listRowBackground(Color.bizarreSurface1)
                        }
                    }
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Couldn't load defaults")
                .font(.brandTitleMedium())
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TenantOverrideRow

private struct TenantOverrideRow: View {
    let override: TenantNotificationOverride
    let onTogglePush: (Bool) -> Void
    let onToggleInApp: (Bool) -> Void
    let onToggleEmail: (Bool) -> Void
    let onToggleSms: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(override.event.displayName)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack(spacing: BrandSpacing.sm) {
                channelChip("Push",   systemImage: "bell.fill",       value: override.defaultPush,   toggle: onTogglePush)
                channelChip("In-App", systemImage: "app.badge",       value: override.defaultInApp,  toggle: onToggleInApp)
                channelChip("Email",  systemImage: "envelope",        value: override.defaultEmail,  toggle: onToggleEmail)
                channelChip("SMS",    systemImage: "message",         value: override.defaultSms,    toggle: onToggleSms)
                Spacer()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(override.event.displayName)
    }

    private func channelChip(_ label: String, systemImage: String, value: Bool, toggle: @escaping (Bool) -> Void) -> some View {
        Button {
            toggle(!value)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(label)
                    .font(.brandLabelSmall())
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(value ? .white : .bizarreOnSurfaceMuted)
            .background(
                Capsule().fill(value ? Color.bizarreOrange : Color.bizarreSurface1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value ? "on" : "off")")
        .accessibilityAddTraits(value ? .isSelected : [])
        .accessibilityIdentifier("tenantOverride.\(override.event.rawValue).\(label.lowercased())")
    }
}

// MARK: - Event grouping helper

private struct NotificationEventGroup {
    let title: String
    let events: [NotificationEvent]

    static let allGroups: [NotificationEventGroup] = [
        NotificationEventGroup(title: "Tickets", events: [
            .ticketAssigned, .ticketStatusChangeMine, .ticketStatusChangeAny
        ]),
        NotificationEventGroup(title: "SMS & Communications", events: [
            .smsInbound, .smsDeliveryFailed
        ]),
        NotificationEventGroup(title: "Invoices & Payments", events: [
            .invoiceOverdue, .invoicePaid, .paymentDeclined, .refundProcessed, .cashRegisterShort
        ]),
        NotificationEventGroup(title: "Estimates & Appointments", events: [
            .estimateApproved, .estimateDeclined,
            .appointmentReminder24h, .appointmentReminder1h, .appointmentCanceled
        ]),
        NotificationEventGroup(title: "Inventory", events: [
            .lowStock, .outOfStock
        ]),
        NotificationEventGroup(title: "Customers & CRM", events: [
            .newCustomerCreated, .npsDetractor, .mentionInNote
        ]),
        NotificationEventGroup(title: "Team & HR", events: [
            .goalAchieved, .ptoApprovedDenied, .shiftStartedEnded
        ]),
        NotificationEventGroup(title: "Marketing & Admin", events: [
            .campaignSent, .setupWizardIncomplete, .subscriptionRenewal,
            .integrationDisconnected, .backupFailed, .securityEvent
        ]),
    ]
}

// MARK: - NotificationEvent display name

public extension NotificationEvent {
    var displayName: String {
        switch self {
        case .ticketAssigned:             return "Ticket assigned to me"
        case .ticketStatusChangeMine:     return "Ticket status change (mine)"
        case .ticketStatusChangeAny:      return "Ticket status change (anyone)"
        case .smsInbound:                 return "New SMS from customer"
        case .smsDeliveryFailed:          return "SMS delivery failed"
        case .newCustomerCreated:         return "New customer created"
        case .invoiceOverdue:             return "Invoice overdue"
        case .invoicePaid:                return "Invoice paid"
        case .estimateApproved:           return "Estimate approved"
        case .estimateDeclined:           return "Estimate declined"
        case .appointmentReminder24h:     return "Appointment reminder 24 h"
        case .appointmentReminder1h:      return "Appointment reminder 1 h"
        case .appointmentCanceled:        return "Appointment canceled"
        case .mentionInNote:              return "@Mention in note / chat"
        case .lowStock:                   return "Low stock"
        case .outOfStock:                 return "Out of stock"
        case .paymentDeclined:            return "Payment declined"
        case .refundProcessed:            return "Refund processed"
        case .cashRegisterShort:          return "Cash register short"
        case .shiftStartedEnded:          return "Shift started / ended"
        case .goalAchieved:               return "Goal achieved"
        case .ptoApprovedDenied:          return "PTO approved / denied"
        case .campaignSent:               return "Campaign sent"
        case .npsDetractor:               return "NPS detractor"
        case .setupWizardIncomplete:      return "Setup wizard incomplete (24 h)"
        case .subscriptionRenewal:        return "Subscription renewal"
        case .integrationDisconnected:    return "Integration disconnected"
        case .backupFailed:               return "Backup failed (critical)"
        case .securityEvent:              return "Security event"
        }
    }
}

// MARK: - API client extension

/// Minimal response type used when we only need success/message.
private struct VoidData: Decodable, Sendable {}

public extension APIClient {
    /// `GET /api/v1/notifications/tenant-defaults`
    func fetchTenantNotificationDefaults() async throws -> [TenantNotificationOverride] {
        let wrapper = try await get("notifications/tenant-defaults", as: APIResponse<[TenantNotificationOverride]>.self)
        return wrapper.data ?? []
    }

    /// `PUT /api/v1/notifications/tenant-defaults`
    func putTenantNotificationDefaults(_ overrides: [TenantNotificationOverride]) async throws {
        _ = try await put("notifications/tenant-defaults", body: overrides, as: APIResponse<VoidData>.self)
    }
}
