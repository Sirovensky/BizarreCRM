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

                // Split hint (shown once a leg has been applied)
                if coordinator.isSplit {
                    splitHintRow
                        .padding(.horizontal, BrandSpacing.base)
                }

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
            if coordinator.isSplit {
                Text("Remaining")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.muted)
            } else {
                Text("Select payment method")
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.muted)
            }
            Text(CartMath.formatCents(coordinator.remaining))
                .font(.brandDisplayMedium())
                .foregroundStyle(theme.on)
                .monospacedDigit()
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityIdentifier("pos.tenderV2.remaining")
        }
    }

    // MARK: - Split hint row

    private var splitHintRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.teal)
                .accessibilityHidden(true)
            Text("Split tender — add another payment")
                .font(.brandBodyMedium())
                .foregroundStyle(theme.muted)
            Spacer()
            // Applied tenders count chip
            Text("\(coordinator.appliedTenders.count) applied")
                .font(.brandLabelSmall())
                .foregroundStyle(theme.onPrimary)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(theme.primary, in: Capsule())
        }
        .padding(BrandSpacing.sm)
        .background(theme.surfaceElev.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.outline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Split tender in progress. \(coordinator.appliedTenders.count) leg(s) applied. Remaining: \(CartMath.formatCents(coordinator.remaining)).")
    }

    // MARK: - Member benefit banner

    private func memberBenefitBanner(tier: String) -> some View {
        // Stub layout — Agent H replaces this with `MembershipBenefitBanner`.
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(theme.warning)
                .font(.system(size: 18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(tier)
                    .font(.brandLabelLarge())
                    .foregroundStyle(theme.on)
                Text("Member benefits available")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.primary.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier) member. Benefits available at checkout.")
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
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: method.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text(method.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                if !method.isReady, let hint = method.notReadyHint {
                    Text(hint)
                        .font(.brandLabelSmall())
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }
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
