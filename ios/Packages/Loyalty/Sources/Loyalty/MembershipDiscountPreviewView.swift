import SwiftUI
import DesignSystem

// MARK: - MembershipDiscountPreview (model)

/// §38 — Computed discount preview for a membership at checkout.
///
/// Pure value type; no I/O. Constructed by the POS checkout layer
/// and passed to `MembershipDiscountPreviewView` for display.
public struct MembershipDiscountPreview: Sendable {
    /// Customer's active membership (nil = no membership).
    public let membership: Membership?
    /// The plan linked to the membership.
    public let plan: MembershipPlan?
    /// Cart subtotal in cents.
    public let subtotalCents: Int
    /// Computed discount in cents (always ≥ 0, capped at subtotal).
    public let discountCents: Int
    /// Post-discount total in cents.
    public let totalAfterDiscountCents: Int

    public init(membership: Membership?, plan: MembershipPlan?, subtotalCents: Int) {
        self.membership = membership
        self.plan = plan
        self.subtotalCents = subtotalCents
        let cart = LoyaltyCart(subtotalCents: subtotalCents)
        self.discountCents = MembershipPerkApplier.discount(
            cart: cart,
            membership: membership,
            plan: plan
        )
        self.totalAfterDiscountCents = max(0, subtotalCents - self.discountCents)
    }

    /// `true` when a positive discount is applied.
    public var hasDiscount: Bool { discountCents > 0 }

    /// Formatted discount string, e.g. "-$5.00".
    public var formattedDiscount: String {
        String(format: "-$%.2f", Double(discountCents) / 100.0)
    }

    /// Formatted total after discount.
    public var formattedTotal: String {
        String(format: "$%.2f", Double(totalAfterDiscountCents) / 100.0)
    }

    /// Human-readable summary of which perk applied (or nil if no discount).
    public var appliedPerkSummary: String? {
        guard hasDiscount, let plan else { return nil }
        // Identify the winning perk from the plan.
        let subtotal = subtotalCents
        var bestPerk: MembershipPerk? = nil
        var bestAmount = 0
        for perk in plan.perks {
            switch perk {
            case .percentageDiscount(let pct) where pct > 0:
                let amount = (subtotal * pct) / 100
                if amount > bestAmount {
                    bestAmount = amount
                    bestPerk = perk
                }
            case .fixedDiscount(let cents) where cents > 0:
                if cents > bestAmount {
                    bestAmount = cents
                    bestPerk = perk
                }
            default:
                break
            }
        }
        return bestPerk?.displayName
    }
}

// MARK: - MembershipDiscountPreviewView

/// §38 — Inline checkout widget showing the member discount applied to the cart.
///
/// Usage in POS checkout:
/// ```swift
/// let preview = MembershipDiscountPreview(
///     membership: customer.activeMembership,
///     plan: plans.first { $0.id == customer.activeMembership?.planId },
///     subtotalCents: cart.subtotalCents
/// )
/// MembershipDiscountPreviewView(preview: preview)
/// ```
///
/// iPhone: horizontal discount row with plan name badge.
/// iPad: same layout, wider.
///
/// When `preview.hasDiscount` is `false` the view renders nothing (zero height).
public struct MembershipDiscountPreviewView: View {

    private let preview: MembershipDiscountPreview

    public init(preview: MembershipDiscountPreview) {
        self.preview = preview
    }

    public var body: some View {
        if preview.hasDiscount {
            discountRow
        }
        // When no discount applies, render nothing (zero height, no padding).
    }

    // MARK: - Discount row

    private var discountRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Membership badge (glass on chrome — nav/badge context)
            memberBadge
                .brandGlass(.ultraThin, in: Capsule())

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(preview.plan?.name ?? "Member Discount")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                if let summary = preview.appliedPerkSummary {
                    Text(summary)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(preview.formattedDiscount)
                    .font(.brandMono(size: 16))
                    .foregroundStyle(.bizarreSuccess)
                Text(preview.formattedTotal)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(Color.bizarreSuccess.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var memberBadge: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("MEMBER")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreSuccess)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let plan = preview.plan?.name ?? "Member"
        let discount = String(format: "%.2f", Double(preview.discountCents) / 100.0)
        let total = preview.formattedTotal
        return "\(plan) discount applied: $\(discount) off. New total: \(total)."
    }
}

// MARK: - MembershipDiscountPreviewRow (list-row variant)

/// §38 — Compact single-line discount row for use inside checkout line-item lists.
///
/// Shows: plan name · discount amount (green) · post-discount total.
/// Used inside `PosCheckoutView`'s line items section.
public struct MembershipDiscountPreviewRow: View {

    private let preview: MembershipDiscountPreview

    public init(preview: MembershipDiscountPreview) {
        self.preview = preview
    }

    public var body: some View {
        if preview.hasDiscount {
            HStack {
                Label(
                    preview.plan?.name ?? "Member Discount",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreSuccess)
                .accessibilityLabel("Member discount: \(preview.plan?.name ?? "plan")")

                Spacer()

                Text(preview.formattedDiscount)
                    .font(.brandMono(size: 14))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityLabel("Discount amount \(preview.formattedDiscount)")
            }
        }
    }
}
