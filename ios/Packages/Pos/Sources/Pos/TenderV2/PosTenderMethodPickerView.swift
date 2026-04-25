#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §D — Step 1 of the v2 tender flow: method selection.
///
/// iPhone: full-screen inside a `NavigationStack`.
/// iPad:   replaces the items column while the cart column stays locked.
///
/// Layout (top → bottom):
/// 1. Split-tender hint row (visible once `isSplit` is true).
/// 2. Member-benefit banner (when customer is a loyalty member — Agent H
///    wires `LoyaltyAccount`; stubbed here so this view compiles without it).
/// 3. 2×2 `LazyVGrid` of method tiles.
/// 4. Amount bar injected from outside via `bottomBar` slot.
public struct PosTenderMethodPickerView: View {

    @Bindable public var coordinator: PosTenderCoordinator

    /// Optional loyalty tier label from the customer record.
    /// Agent H (`MembershipBenefitBanner`) will own the full loyalty view;
    /// this view just receives a ready-to-show flag + tier name.
    public let loyaltyTierLabel: String?

    /// Bottom action bar injected by the parent (typically `PosTenderAmountBar`).
    public let bottomBar: AnyView

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.posTheme) private var theme

    public init(
        coordinator: PosTenderCoordinator,
        loyaltyTierLabel: String? = nil,
        bottomBar: AnyView = AnyView(EmptyView())
    ) {
        self.coordinator = coordinator
        self.loyaltyTierLabel = loyaltyTierLabel
        self.bottomBar = bottomBar
    }

    public var body: some View {
        VStack(spacing: 0) {
            scrollContent
            bottomBar
        }
        .background(theme.bg.ignoresSafeArea())
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.md) {
                // Total due header
                totalHeader
                    .padding(.top, BrandSpacing.lg)
                    .padding(.horizontal, BrandSpacing.base)

                // Split hint — always visible (mockup spec)
                splitHintRow
                    .padding(.horizontal, BrandSpacing.base)

                // Member-benefit banner (stub — Agent H wires real data)
                if let tier = loyaltyTierLabel {
                    memberBenefitBanner(tier: tier)
                        .padding(.horizontal, BrandSpacing.base)
                }

                // Method tiles
                methodGrid
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.lg)
            }
        }
    }

    // MARK: - Total header

    private var totalHeader: some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(coordinator.isSplit ? "Remaining" : "Due now")
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted)
                .tracking(1.4)
                .textCase(.uppercase)
            Text(CartMath.formatCents(coordinator.remaining))
                .font(.brandDisplayLarge())
                .foregroundStyle(theme.on)
                .monospacedDigit()
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityIdentifier("pos.tenderV2.remaining")
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Split hint row (always visible — matches mockup 5a/4a)

    private var splitHintRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text("⊕")
                .font(.system(size: 15))
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
            Text(coordinator.isSplit
                 ? "Split tender — pick another method for the remainder"
                 : "Split tender — pick method, enter partial, then pick another")
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted)
            if coordinator.isSplit {
                Spacer()
                Text("\(coordinator.appliedTenders.count) applied")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.onPrimary)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(theme.primary, in: Capsule())
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(theme.surfaceElev.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                .foregroundStyle(theme.outline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(coordinator.isSplit
            ? "Split tender in progress. \(coordinator.appliedTenders.count) leg(s) applied. Remaining: \(CartMath.formatCents(coordinator.remaining))."
            : "Split tender hint")
    }

    // MARK: - Member benefit banner

    private func memberBenefitBanner(tier: String) -> some View {
        // Stub layout — Agent H replaces this with `MembershipBenefitBanner`.
        HStack(spacing: BrandSpacing.sm) {
            // Star badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [theme.primaryBright, theme.primary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: theme.primary.opacity(0.3), radius: 6, y: 4)
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.onPrimary)
            }
            .accessibilityHidden(true)
            // Labels
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("\(tier) member · benefits applied")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.primary)
                Text("Member discount applied · earning loyalty points")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BrandSpacing.sm)
        .padding(.horizontal, BrandSpacing.md)
        .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.primary.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier) member. Benefits applied at checkout.")
    }

    // MARK: - Method grid

    private var methodGrid: some View {
        let isWide = sizeClass == .regular
        let cols: [GridItem] = isWide
            ? [GridItem(.flexible()), GridItem(.flexible()),
               GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: cols, spacing: BrandSpacing.md) {
            ForEach(TenderMethod.allCases) { method in
                MethodTile(
                    method: method,
                    isSelected: coordinator.method == method,
                    theme: theme,
                    onTap: { coordinator.selectMethod(method) }
                )
            }
        }
    }
}

// MARK: - MethodTile

private struct MethodTile: View {
    let method: TenderMethod
    let isSelected: Bool
    let theme: POSThemeTokens
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: method.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text(method.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                // Always show subtitle (mockup 5a/4a)
                let subtitle = method.isReady ? method.tileSubtitle : (method.notReadyHint ?? method.tileSubtitle)
                Text(subtitle)
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.lg)
            .background(tileBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(method.isReady ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(method.displayName)
        .accessibilityHint(method.isReady ? "Double tap to select" : (method.notReadyHint ?? "Unavailable"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pos.tenderV2.method.\(method.rawValue)")
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isSelected {
            // Light mode: orange fill; dark mode: cream fill.
            if colorScheme == .dark {
                Color(red: 253/255, green: 238/255, blue: 208/255, opacity: 0.18)
            } else {
                Color(red: 194/255, green: 65/255, blue: 12/255, opacity: 0.12)
            }
        } else {
            theme.surfaceElev
        }
    }

    private var borderColor: Color {
        isSelected ? theme.primary : theme.outline
    }

    private var iconColor: Color {
        isSelected ? theme.primary : theme.muted
    }

    private var labelColor: Color {
        isSelected ? theme.on : theme.muted
    }
}

#endif
