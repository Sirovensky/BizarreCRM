import SwiftUI
import DesignSystem
import Networking

// MARK: - §37 Campaign Compliance

/// Compliance configuration card shown in `CampaignCreateView` and campaign detail.
///
/// Surfaces:
/// - Tenant quiet-hours window (sends never fire outside this window)
/// - Unsubscribe-suppression toggle (skip opted-out contacts)
/// - Test-number suppression toggle (skip any number in tenant's test list)
/// - Consent info: date + source stored per contact
///
/// The toggles are informational — actual enforcement is server-side.
/// The view simply makes compliance state visible and lets staff review it.
public struct CampaignComplianceView: View {
    @Binding public var config: CampaignComplianceConfig

    public init(config: Binding<CampaignComplianceConfig>) {
        _config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Header
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 18))
                    .accessibilityHidden(true)
                Text("Compliance")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
            }

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            // Quiet hours
            quietHoursRow

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            // Suppression toggles
            suppressionRow(
                icon: "hand.raised.slash.fill",
                label: "Skip unsubscribed contacts",
                detail: "Opted-out numbers never receive sends",
                isOn: $config.suppressUnsubscribed
            )

            suppressionRow(
                icon: "testtube.2",
                label: "Skip test numbers",
                detail: "Numbers in your tenant test list are excluded",
                isOn: $config.suppressTestNumbers
            )

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            // Consent info
            consentInfoRow
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Quiet hours

    private var quietHoursRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text("Quiet hours")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Toggle("", isOn: $config.quietHoursEnabled)
                    .labelsHidden()
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Enable quiet hours")
            }

            if config.quietHoursEnabled {
                HStack(spacing: BrandSpacing.sm) {
                    Text("No sends between")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)

                    Stepper(
                        hourLabel(config.quietStart),
                        value: $config.quietStart,
                        in: 0...23
                    )
                    .frame(maxWidth: 160)
                    .accessibilityLabel("Quiet start hour: \(hourLabel(config.quietStart))")

                    Text("–")
                        .foregroundStyle(.bizarreOnSurfaceMuted)

                    Stepper(
                        hourLabel(config.quietEnd),
                        value: $config.quietEnd,
                        in: 0...23
                    )
                    .frame(maxWidth: 160)
                    .accessibilityLabel("Quiet end hour: \(hourLabel(config.quietEnd))")
                }
                .font(.brandBodyMedium())

                Text("Applies in tenant's local timezone")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h):00 \(ampm)"
    }

    // MARK: - Suppression row

    private func suppressionRow(
        icon: String,
        label: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(isOn.wrappedValue ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .frame(width: 20)
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
                .accessibilityLabel(label)
        }
    }

    // MARK: - Consent info

    private var consentInfoRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.bizarreSuccess)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text("Consent tracking")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text("Consent date and source are stored per contact. Sends are blocked for contacts without recorded consent when strict mode is enabled.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Toggle(isOn: $config.requireConsent) {
                Text("Require recorded consent")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Require recorded consent before sending")
        }
    }
}

// MARK: - CampaignComplianceConfig

/// Compliance settings embedded in a campaign or tenant-level defaults.
public struct CampaignComplianceConfig: Codable, Sendable, Equatable {
    /// Whether quiet hours block sends outside the allowed window.
    public var quietHoursEnabled: Bool
    /// Hour (0–23) when quiet period starts (no sends after this hour).
    public var quietStart: Int
    /// Hour (0–23) when quiet period ends (sends resume at this hour).
    public var quietEnd: Int
    /// If true, opted-out contacts are silently skipped.
    public var suppressUnsubscribed: Bool
    /// If true, numbers in the tenant test list are excluded from live sends.
    public var suppressTestNumbers: Bool
    /// If true, contacts without recorded consent are blocked.
    public var requireConsent: Bool

    public init(
        quietHoursEnabled: Bool = true,
        quietStart: Int = 21,   // 9 PM
        quietEnd: Int = 8,      // 8 AM
        suppressUnsubscribed: Bool = true,
        suppressTestNumbers: Bool = true,
        requireConsent: Bool = false
    ) {
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.suppressUnsubscribed = suppressUnsubscribed
        self.suppressTestNumbers = suppressTestNumbers
        self.requireConsent = requireConsent
    }

    enum CodingKeys: String, CodingKey {
        case quietHoursEnabled   = "quiet_hours_enabled"
        case quietStart          = "quiet_start"
        case quietEnd            = "quiet_end"
        case suppressUnsubscribed = "suppress_unsubscribed"
        case suppressTestNumbers  = "suppress_test_numbers"
        case requireConsent      = "require_consent"
    }
}
