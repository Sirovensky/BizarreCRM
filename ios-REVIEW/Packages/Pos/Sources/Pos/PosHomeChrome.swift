#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Chrome pieces that pin to the iPhone POS home screen: the attached-
/// customer banner at the top (§16.4) and the bottom cart pill.
/// Extracted from `PosView.swift` so that file stays focused on state +
/// wiring and each chrome piece has somewhere to grow independently.

/// Glass banner pinned to the top safe-area once a customer is attached.
/// Shows avatar initials (or the walk-in ghost icon) + display name +
/// primary contact, with a Change / Remove affordance. Uses `.brandGlass`
/// per CLAUDE.md — navigation-layer chrome, not content.
struct PosCustomerBanner: View {
    let customer: PosCustomer
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            avatar
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(customer.displayName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let line = subtitle {
                    Text(line)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            Button {
                BrandHaptics.tap()
                onChange()
            } label: {
                Text("Change")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pos.changeCustomer")

            Button {
                BrandHaptics.tap()
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove customer")
            .accessibilityIdentifier("pos.removeCustomer")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Customer \(customer.displayName)")
        .accessibilityIdentifier("pos.customerBanner")
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle().fill(Color.bizarreOrangeContainer)
            if customer.isWalkIn {
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.bizarreOnOrange)
            } else {
                Text(customer.initials)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnOrange)
            }
        }
    }

    private var subtitle: String? {
        if customer.isWalkIn { return "Guest checkout" }
        if let e = customer.email, !e.isEmpty { return e }
        if let p = customer.phone, !p.isEmpty { return p }
        return nil
    }
}

/// Compact cart pill anchored to the bottom-safe-area on iPhone. Only
/// surfaces when the cart has items. Shows the rolled-up item count +
/// total on the leading side and a chevron → on the trailing to signal
/// tap-to-expand. Uses brand glass so it reads as chrome floating over
/// the scrolling search results.
struct PosCartPill: View {
    let itemCount: Int
    let totalCents: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: BrandSpacing.md) {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "cart.fill")
                        .foregroundStyle(.bizarreOnOrange)
                        .accessibilityHidden(true)
                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnOrange)
                        .monospacedDigit()
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreOrange, in: Capsule())

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("Total")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(Self.format(cents: totalCents))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(itemCount) \(itemCount == 1 ? "item" : "items") in cart. Total \(Self.format(cents: totalCents)).")
        .accessibilityHint("Double tap to review and charge.")
        .accessibilityIdentifier("pos.cartPill")
    }

    static func format(cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}
#endif
