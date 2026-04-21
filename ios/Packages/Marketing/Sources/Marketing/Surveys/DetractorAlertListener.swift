import SwiftUI
import DesignSystem

// MARK: - DetractorAlert model

/// Payload of a `kind: "survey.detractor"` push notification.
/// Only surfaced to manager-role users.
public struct DetractorAlert: Identifiable, Sendable {
    public let id: String
    public let customerId: String
    public let customerName: String
    public let customerPhone: String?
    public let npsScore: Int
    public let ticketId: String?
    public let receivedAt: Date

    public init(
        id: String,
        customerId: String,
        customerName: String,
        customerPhone: String?,
        npsScore: Int,
        ticketId: String?,
        receivedAt: Date
    ) {
        self.id = id
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.npsScore = npsScore
        self.ticketId = ticketId
        self.receivedAt = receivedAt
    }

    /// Parse from `kind: "survey.detractor"` push payload.
    public static func parse(from userInfo: [AnyHashable: Any]) -> DetractorAlert? {
        guard
            let kind = userInfo["kind"] as? String,
            kind == "survey.detractor",
            let id = userInfo["alertId"] as? String,
            let customerId = userInfo["customerId"] as? String,
            let customerName = userInfo["customerName"] as? String,
            let score = userInfo["npsScore"] as? Int
        else {
            return nil
        }
        return DetractorAlert(
            id: id,
            customerId: customerId,
            customerName: customerName,
            customerPhone: userInfo["customerPhone"] as? String,
            npsScore: score,
            ticketId: userInfo["ticketId"] as? String,
            receivedAt: Date()
        )
    }
}

// MARK: - DetractorAlertView

/// Manager-role only sheet: shows detractor NPS alert + quick-recover CTA.
/// Presented by the host app when a `kind: "survey.detractor"` push is tapped.
public struct DetractorAlertView: View {
    let alert: DetractorAlert
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(alert: DetractorAlert) {
        self.alert = alert
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                    alertHeader
                    scoreSection
                    Divider()
                    recoveryActions
                }
                .padding(BrandSpacing.base)
            }
            .navigationTitle("Detractor Alert")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - Header

    private var alertHeader: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(alert.customerName)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Left a low NPS score — recovery recommended within 2h")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.customerName) left a low NPS score. Recovery recommended within 2 hours.")
    }

    // MARK: - Score

    private var scoreSection: some View {
        HStack {
            Text("NPS Score")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text("\(alert.npsScore) / 10")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreError)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NPS Score: \(alert.npsScore) out of 10")
    }

    // MARK: - Recovery CTAs

    private var recoveryActions: some View {
        VStack(spacing: BrandSpacing.md) {
            Text("Quick Recovery Actions")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            if let phone = alert.customerPhone {
                recoveryButton(
                    icon: "phone.fill",
                    label: "Call Now",
                    description: phone,
                    tint: .bizarreSuccess
                ) {
                    if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                        openURL(url)
                    }
                }
            }

            recoveryButton(
                icon: "message.fill",
                label: "Send Apology SMS",
                description: "Open Messages with a pre-filled apology",
                tint: .bizarreTeal
            ) {
                let body = "Hi \(alert.customerName), this is [Manager] from BizarreCRM. I saw your recent feedback and I'd like to personally make this right. Can we chat?"
                let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let phone = alert.customerPhone ?? ""
                if let url = URL(string: "sms:\(phone)&body=\(encoded)") {
                    openURL(url)
                }
            }

            recoveryButton(
                icon: "person.badge.shield.checkmark",
                label: "Assign to Manager",
                description: "Flag this customer for manager follow-up",
                tint: .bizarreOrange
            ) {
                // The host app handles manager assignment navigation
                // We dismiss and let the host route to the ticket/customer detail
                dismiss()
            }
        }
    }

    private func recoveryButton(
        icon: String,
        label: String,
        description: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(label)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(description)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .accessibilityLabel("\(label): \(description)")
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
    }
}
