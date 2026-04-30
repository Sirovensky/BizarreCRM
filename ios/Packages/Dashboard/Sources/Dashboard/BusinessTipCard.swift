import SwiftUI
import DesignSystem

// MARK: - §3 Business Tip of the Day
//
// Rotating daily business tip for repair shop owners / managers.
// Tips are seeded locally (no network needed) — cycled by day-of-year so
// the same tip appears for the whole UTC calendar day across devices.
// Dismissed per-day via UserDefaults; reappears next day automatically.

private let businessTips: [String] = [
    "Follow up with customers 48 hours after pickup — a quick \u{201C}How\u{2019}s the device?\u{201D} drives repeat visits and 5-star reviews.",
    "Batch-print repair labels at the start of each shift to cut search time and keep the bench organised.",
    "A low-stock alert on your three best-selling parts can prevent turning away same-day repairs.",
    "Offer a diagnostic fee that converts to a repair credit — it sets expectations and improves close rates.",
    "Text customers when their device is ready: reply rates outperform email by 5×.",
    "Review your average repair hours weekly. A rising average often signals a parts-sourcing bottleneck.",
    "Bundle screen protector installation with screen repairs — it adds margin and reduces warranty claims.",
    "Post your busiest hours on Google Business Profile so walk-in customers plan around your team.",
    "A closed ticket that's gone unpicked for 7 days becomes dead inventory. Set a follow-up reminder.",
    "Training techs to cross-sell a battery check during any screen repair increases average order value.",
    "Keep a laminated quick-reference for top 10 device models. New techs ramp up faster with it.",
    "Seasonal surges (back-to-school, holidays) need parts ordered 6 weeks in advance.",
    "Offer a small discount for reviews collected while the customer is still in the shop.",
    "A daily cash-drawer reconciliation prevents end-of-month surprises.",
    "Photos of every device at intake protect you from pre-existing damage disputes.",
    "Recurring monthly check-ups (battery health, cleaning) build a loyal customer base.",
    "Churn starts with silence. If a customer hasn't returned in 90 days, a check-in SMS can re-engage them.",
    "Commission structures tied to CSAT scores align tech incentives with customer satisfaction.",
    "A 'no fix, no fee' policy converts browsers into first-time customers and builds trust fast.",
    "Categorise your parts by velocity (fast / slow / dead) and reorder only fast movers automatically.",
]

private func todaysTipIndex() -> Int {
    let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    return (dayOfYear - 1) % businessTips.count
}

private func dismissedKey() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return "dashboard.businessTip.dismissed.\(df.string(from: Date()))"
}

// MARK: - View

public struct BusinessTipCard: View {
    @State private var isDismissed: Bool = false

    public init() {}

    public var body: some View {
        if !isDismissed {
            TipContent(
                tip: businessTips[todaysTipIndex()],
                onDismiss: {
                    UserDefaults.standard.set(true, forKey: dismissedKey())
                    withAnimation(.easeOut(duration: 0.18)) {
                        isDismissed = true
                    }
                }
            )
            .onAppear {
                isDismissed = UserDefaults.standard.bool(forKey: dismissedKey())
            }
        }
    }
}

private struct TipContent: View {
    let tip: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chrome header
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Tip of the Day")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.5)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss tip for today")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .brandGlass(.regular, in: UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 14
            ))

            // Tip body
            Text(tip)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Business tip: \(tip)")
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }
}
