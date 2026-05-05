import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Next Billing Date — shown on customer detail
//
// Displayed inside the customer detail membership section.
// Server cron handles the actual charge; iOS just surfaces the date.
// Also shows auto-renew status and last payment result.

public struct MembershipNextBillingCard: View {
    public let membership: Membership
    public let plan: MembershipPlan?

    public init(membership: Membership, plan: MembershipPlan? = nil) {
        self.membership = membership
        self.plan = plan
    }

    // MARK: - Derived

    private var nextBillingLabel: String {
        guard let date = membership.nextBillingAt else { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let days = cal.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days > 0 && days <= 7 { return "In \(days) day\(days == 1 ? "" : "s")" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }

    private var isUpcoming: Bool {
        guard let date = membership.nextBillingAt else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return days >= 0 && days <= 7
    }

    private var amountLabel: String {
        guard let plan else { return "" }
        let dollars = Double(plan.pricePerPeriodCents) / 100
        return String(format: "$%.2f", dollars)
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 18))
                    .accessibilityHidden(true)
                Text("Billing")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if membership.autoRenew {
                    autoRenewPill
                }
            }

            Divider().opacity(0.4)

            // Next billing row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next charge")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(nextBillingLabel)
                        .font(.brandBodyMedium().weight(.semibold))
                        .foregroundStyle(isUpcoming ? .bizarreWarning : .bizarreOnSurface)
                }
                Spacer()
                if !amountLabel.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Amount")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(amountLabel)
                            .font(.brandMono(size: 15).weight(.semibold))
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
            }

            // Plan name
            if let plan {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityHidden(true)
                    Text(plan.name)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isUpcoming ? Color.bizarreWarning.opacity(0.4) : Color.bizarreOutline.opacity(0.4),
                    lineWidth: isUpcoming ? 1 : 0.5
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buildA11y())
    }

    private var autoRenewPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text("Auto-renew")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.bizarreSuccess)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.bizarreSuccess.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bizarreSuccess.opacity(0.3), lineWidth: 0.5))
        .accessibilityLabel("Auto-renew enabled")
    }

    private func buildA11y() -> String {
        var parts: [String] = ["Billing section"]
        parts.append("Next charge: \(nextBillingLabel)")
        if !amountLabel.isEmpty { parts.append("Amount: \(amountLabel)") }
        if membership.autoRenew { parts.append("Auto-renew is on.") }
        if let plan { parts.append("Plan: \(plan.name).") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Auto-renew notification result card
//
// §38.5: Notify success/failure of auto-renew.
// Staff see the last charge outcome when they open the customer's membership.

public struct AutoRenewResultBanner: View {
    public enum Result: Sendable {
        case success(date: Date, amountCents: Int)
        case failure(reason: String, date: Date)
        case pending
    }

    public let result: Result

    public init(result: Result) {
        self.result = result
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.brandLabelLarge().weight(.semibold))
                    .foregroundStyle(foregroundColor)
                Text(subtitle)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.sm)
        .background(backgroundColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(backgroundColor.opacity(0.3), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 18))
            .foregroundStyle(foregroundColor)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    private var iconName: String {
        switch result {
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "exclamationmark.circle.fill"
        case .pending:  return "clock.fill"
        }
    }

    private var foregroundColor: Color {
        switch result {
        case .success:  return .bizarreSuccess
        case .failure:  return .bizarreError
        case .pending:  return .bizarreWarning
        }
    }

    private var backgroundColor: Color { foregroundColor }

    private var title: String {
        switch result {
        case .success:  return "Renewal Successful"
        case .failure:  return "Renewal Failed"
        case .pending:  return "Renewal Pending"
        }
    }

    private var subtitle: String {
        switch result {
        case .success(let date, let cents):
            let amt = String(format: "$%.2f", Double(cents) / 100)
            let fmt = DateFormatter(); fmt.dateStyle = .medium
            return "\(amt) charged on \(fmt.string(from: date))"
        case .failure(let reason, let date):
            let fmt = DateFormatter(); fmt.dateStyle = .medium
            return "\(reason) — \(fmt.string(from: date))"
        case .pending:
            return "Charge will be attempted at the next billing cycle."
        }
    }
}
