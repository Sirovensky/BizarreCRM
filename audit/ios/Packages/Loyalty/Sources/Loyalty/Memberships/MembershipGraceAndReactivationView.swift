import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Grace Period + Reactivation

/// Card shown on the customer membership section when a membership is in
/// `gracePeriod` or `expired` status.
///
/// - Grace period (7 days post-expiry): shows countdown, benefits still active, soft reminder.
/// - Expired: benefits suspended; one-tap reactivation with card on file or new card.
///
/// Usage: embed in `MembershipListView` or customer detail membership section.
public struct MembershipGraceAndReactivationView: View {
    public let membership: Membership
    public let plan: MembershipPlan?
    public var onReactivate: () -> Void
    public var onDismiss: () -> Void

    @State private var isReactivating = false
    @State private var errorMessage: String?

    public init(
        membership: Membership,
        plan: MembershipPlan? = nil,
        onReactivate: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.membership = membership
        self.plan = plan
        self.onReactivate = onReactivate
        self.onDismiss = onDismiss
    }

    // MARK: - Derived

    private var isGracePeriod: Bool { membership.status == .gracePeriod }
    private var isExpired: Bool     { membership.status == .expired }

    /// Days remaining in grace period (based on endDate + 7 days).
    private var graceDaysRemaining: Int? {
        guard isGracePeriod, let endDate = membership.endDate else { return nil }
        let graceEnd = Calendar.current.date(byAdding: .day, value: 7, to: endDate) ?? endDate
        let days = Calendar.current.dateComponents([.day], from: Date(), to: graceEnd).day ?? 0
        return max(0, days)
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            headerRow
            statusBody
            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
            actionButton
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: isGracePeriod ? "clock.badge.exclamationmark.fill" : "xmark.circle.fill")
                .foregroundStyle(isGracePeriod ? .bizarreWarning : .bizarreError)
                .font(.system(size: 22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isGracePeriod ? "Grace Period" : "Membership Expired")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                if let planName = plan?.name {
                    Text(planName)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
            // Dismiss if expired (allow staff to collapse card)
            if isExpired {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss expired membership card")
            }
        }
    }

    private var statusBody: some View {
        Group {
            if isGracePeriod {
                gracePeriodInfo
            } else {
                expiredInfo
            }
        }
    }

    private var gracePeriodInfo: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            if let days = graceDaysRemaining {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "timer").foregroundStyle(.bizarreWarning).accessibilityHidden(true)
                    Text(days == 0 ? "Grace period ends today" : "\(days) day\(days == 1 ? "" : "s") remaining")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreWarning)
                }
            }
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.bizarreSuccess).accessibilityHidden(true)
                Text("Benefits still active during grace period")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text("Renew now to avoid losing access to member perks and pricing.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var expiredInfo: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.bizarreError).accessibilityHidden(true)
                Text("Benefits suspended")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
            }
            if let endDate = membership.endDate {
                Text("Expired \(endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text("Reactivate to restore perks. Any remaining period credit will be applied.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var actionButton: some View {
        Button {
            isReactivating = true
            errorMessage = nil
            onReactivate()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                if isReactivating {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: isGracePeriod ? "arrow.clockwise.circle.fill" : "bolt.fill")
                        .accessibilityHidden(true)
                }
                Text(isGracePeriod ? "Renew Now" : "Reactivate Membership")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.md)
            .background(
                isReactivating ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOrange,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            )
        }
        .buttonStyle(.plain)
        .disabled(isReactivating)
        .accessibilityLabel(isGracePeriod ? "Renew membership now" : "Reactivate membership")
        .accessibilityIdentifier("loyalty.membership.reactivate")
    }

    // MARK: - Styling

    private var backgroundFill: Color {
        isGracePeriod ? Color.bizarreWarning.opacity(0.08) : Color.bizarreError.opacity(0.06)
    }

    private var borderColor: Color {
        isGracePeriod ? Color.bizarreWarning.opacity(0.4) : Color.bizarreError.opacity(0.3)
    }
}

// MARK: - MembershipRenewalChannelSettingsView

/// Per-member communication channel configuration for renewal reminders.
///
/// Channels: push notification / SMS / email. Each can be toggled independently.
/// Tenant can lock channels globally; this view shows per-member overrides.
public struct MembershipRenewalChannelSettingsView: View {
    @Binding public var settings: MembershipRenewalChannelSettings

    public init(settings: Binding<MembershipRenewalChannelSettings>) {
        _settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("RENEWAL REMINDERS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .accessibilityAddTraits(.isHeader)

            channelToggle(
                icon: "bell.fill",
                label: "Push notification",
                detail: "In-app alerts on member's device",
                isOn: $settings.pushEnabled
            )
            Divider().overlay(Color.bizarreOutline.opacity(0.2))
            channelToggle(
                icon: "message.fill",
                label: "SMS",
                detail: "Text message to member's phone",
                isOn: $settings.smsEnabled
            )
            Divider().overlay(Color.bizarreOutline.opacity(0.2))
            channelToggle(
                icon: "envelope.fill",
                label: "Email",
                detail: "Email to member's address on file",
                isOn: $settings.emailEnabled
            )
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private func channelToggle(icon: String, label: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(isOn.wrappedValue ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(detail)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.bizarreOrange)
                .accessibilityLabel("\(label) renewal reminders \(isOn.wrappedValue ? "on" : "off")")
        }
    }
}

// MARK: - MembershipRenewalChannelSettings

/// Per-member override for which channels deliver renewal reminder messages.
public struct MembershipRenewalChannelSettings: Codable, Sendable, Equatable {
    public var pushEnabled: Bool
    public var smsEnabled: Bool
    public var emailEnabled: Bool

    public init(pushEnabled: Bool = true, smsEnabled: Bool = true, emailEnabled: Bool = true) {
        self.pushEnabled = pushEnabled
        self.smsEnabled = smsEnabled
        self.emailEnabled = emailEnabled
    }

    enum CodingKeys: String, CodingKey {
        case pushEnabled  = "push_enabled"
        case smsEnabled   = "sms_enabled"
        case emailEnabled = "email_enabled"
    }
}
