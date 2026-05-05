// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// This view MUST render ONLY inside the post-sale receipt screen.
// DO NOT render on: Cart, Catalog, Customer gate, Inspector, Tender method
// picker, or any screen prior to the completed transaction.
// See LoyaltyTier.swift for the full restriction note.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// Post-sale receipt row that celebrates the tier + shows progress toward the
/// next tier with an animated progress bar.
///
/// Visual target: iPhone frame 6 and iPad frame 5 in the mockups.
/// Label format: "GOLD · 285 / 500 · 215 to PLATINUM"
///
/// Color tokens: cream primary in dark mode, deep orange in light.
/// TODO: replace primary with `@Environment(\.posTheme).primary` once Agent A lands.
public struct MembershipTierProgressView: View {

    @Bindable var vm: MembershipViewModel

    /// Points earned during the just-completed sale.
    let pointsEarned: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var animatedProgress: Double = 0

    public init(vm: MembershipViewModel, pointsEarned: Int) {
        self.vm = vm
        self.pointsEarned = pointsEarned
    }

    public var body: some View {
        if let account = vm.account, account.isMember {
            celebrationRow(account: account)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(account: account))
        }
    }

    // MARK: - Main row

    @ViewBuilder
    private func celebrationRow(account: LoyaltyAccount) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Star glyph
            Text("★")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(account.tier.color)
                .shadow(
                    color: account.tier.color.opacity(reduceTransparency ? 0 : 0.30),
                    radius: 8, x: 0, y: 0
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Earned + tier label
                earnedLabel(account: account)

                // Points summary
                pointsSummaryLabel(account: account)

                // Progress bar
                if account.tier != .platinum {
                    progressBar(account: account)
                    progressRangeLabels(account: account)
                }
            }
        }
        .padding(16)
        .background(celebrationBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: shadowColor,
            radius: reduceTransparency ? 0 : 10,
            x: 0, y: 4
        )
        .padding(.horizontal, 0)
        .onAppear {
            let target = account.progressToNextTier
            if reduceMotion {
                animatedProgress = target
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.3)) {
                    animatedProgress = target
                }
            }
        }
    }

    // MARK: - Sub-views

    private func earnedLabel(account: LoyaltyAccount) -> some View {
        let earned = pointsEarned > 0 ? "+\(pointsEarned) pts earned · " : ""
        let tierLabel = "\(account.tier.displayName.uppercased()) tier held"
        return Text(earned + tierLabel)
            .font(.brandLabelLarge().bold())
            .foregroundStyle(primaryColor)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func pointsSummaryLabel(account: LoyaltyAccount) -> some View {
        let total = account.pointsThisYear
        if let next = account.tier.next {
            let needed = account.tier.pointsNeeded(currentPoints: total)
            let nextName = next.displayName.uppercased()
            return Text("\(total) pts total · ")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            +
            Text("\(needed) to ")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            +
            Text(nextName)
                .fontWeight(.bold)
                .foregroundStyle(primaryColor)
        } else {
            return Text("\(total) pts total · ")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            +
            Text("Top tier reached")
                .fontWeight(.bold)
                .foregroundStyle(account.tier.color)
            +
            Text("")
                .foregroundStyle(.clear)
        }
    }

    private func progressBar(account: LoyaltyAccount) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.bizarreOnSurface.opacity(reduceTransparency ? 0.18 : 0.10))
                    .frame(height: 5)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [primaryColor, primaryColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * animatedProgress, height: 5)
            }
        }
        .frame(height: 5)
        .padding(.top, 7)
    }

    private func progressRangeLabels(account: LoyaltyAccount) -> some View {
        HStack {
            Text("\(account.tier.displayName.uppercased()) \(account.tier.minimumPoints) pts")
                .font(.system(size: 9.5))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            if let next = account.tier.next {
                Text("\(next.displayName.uppercased()) \(next.minimumPoints) pts")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.top, 3)
    }

    // MARK: - Colors

    private var primaryColor: Color {
        colorScheme == .dark
            ? Color.bizarreOrange  // #fdeed0 cream
            : .bizarreOrange
    }

    private var celebrationBackground: some View {
        Group {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.bizarreOrange.opacity(
                                    reduceTransparency ? 0.14 : 0.08
                                ),
                                Color.bizarreOrange.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.bizarreOrange.opacity(
                                    reduceTransparency ? 0.32 : 0.30
                                ),
                                Color.bizarreOrange.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.bizarreOrange.opacity(0.40)
            : Color.bizarreOrange.opacity(0.70)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.bizarreOrange.opacity(0.08)
            : Color.bizarreOrange.opacity(0.18)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(account: LoyaltyAccount) -> String {
        var parts: [String] = []
        if pointsEarned > 0 {
            parts.append("Earned \(pointsEarned) points this sale.")
        }
        parts.append("\(account.tier.displayName) tier.")
        parts.append("\(account.pointsThisYear) points total.")
        if let next = account.tier.next {
            let needed = account.tier.pointsNeeded(currentPoints: account.pointsThisYear)
            parts.append("\(needed) points to reach \(next.displayName).")
        } else {
            parts.append("Platinum tier reached.")
        }
        return parts.joined(separator: " ")
    }
}
#endif
