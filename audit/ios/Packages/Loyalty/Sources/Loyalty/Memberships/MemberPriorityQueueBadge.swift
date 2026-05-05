import SwiftUI
import DesignSystem

// MARK: - §38.5 Priority Queue — badge in intake flow
//
// When a customer has an active membership with the priority-queue perk,
// this badge surfaces in the ticket-intake / appointment create flow to
// signal staff should move the customer to the front of the queue.
//
// Usage: embed in TicketCreateView / AppointmentCreateFullView customer card.

// MARK: - Priority perk detection

public extension MembershipPlan {
    /// `true` when any perk in this plan grants priority queue access.
    var hasPriorityQueue: Bool {
        perks.contains { perk in
            if case .priorityQueue = perk { return true }
            return false
        }
    }
}

// MARK: - Badge view

/// A compact Liquid-Glass badge shown in the intake header when the
/// selected customer holds an active membership with priority-queue perk.
public struct MemberPriorityQueueBadge: View {
    public let planName: String
    public let style: Style

    public enum Style: Sendable {
        /// Small capsule for row/header use.
        case compact
        /// Larger banner for prominent intake-flow placement.
        case banner
    }

    public init(planName: String, style: Style = .compact) {
        self.planName = planName
        self.style = style
    }

    public var body: some View {
        switch style {
        case .compact:  compactBadge
        case .banner:   bannerView
        }
    }

    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.up.2")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text("Priority")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.bizarreWarning)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bizarreWarning.opacity(0.4), lineWidth: 0.5))
        .accessibilityLabel("Priority queue member: \(planName)")
    }

    private var bannerView: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "chevron.up.2")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Priority Queue Member")
                    .font(.brandLabelLarge().weight(.semibold))
                    .foregroundStyle(.bizarreOnSurface)
                Text(planName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundStyle(.bizarreWarning.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(BrandSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.bizarreWarning.opacity(0.35), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priority queue member: \(planName). This customer should be served next.")
    }
}

// MARK: - Intake modifier

/// Attach to any intake view to auto-surface the priority banner when
/// the selected customer has an active plan with priority-queue perk.
public struct MemberPriorityQueueModifier: ViewModifier {
    public let membership: Membership?
    public let plan: MembershipPlan?

    public func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if membership?.status == .active,
               let plan, plan.hasPriorityQueue {
                MemberPriorityQueueBadge(planName: plan.name, style: .banner)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
            }
            content
        }
    }
}

public extension View {
    /// Wraps the view with a priority-queue banner when the customer is an eligible member.
    func memberPriorityQueue(membership: Membership?, plan: MembershipPlan?) -> some View {
        modifier(MemberPriorityQueueModifier(membership: membership, plan: plan))
    }
}
