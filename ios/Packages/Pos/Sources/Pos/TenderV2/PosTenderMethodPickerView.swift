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
/// 1. Due-amount hero (57 pt Barlow Condensed — `brandDisplayLarge`).
///    iPad variant adds "Split tender / ⊕ Add method" flush-right.
/// 2. Member-benefit banner (gradient card + savings chip + savings line).
/// 3. Section label "Choose payment method".
/// 4. 2×2 (iPhone) or 4×1 (iPad) `LazyVGrid` of method tiles.
/// 5. Split-tender hint dashed row.
/// 6. Bottom action bar slot (disabled "Select a payment method" CTA injected
///    by parent until a method is chosen).
public struct PosTenderMethodPickerView: View {

    @Bindable public var coordinator: PosTenderCoordinator

    /// Loyalty tier label (e.g. "GOLD") — nil hides the member banner.
    /// Agent H owns full loyalty wiring; we accept a ready-to-render struct.
    public let loyaltyTierLabel: String?

    /// Loyalty earning & savings info lines shown in the banner.
    /// Format: "Earning 55 pts · $10 saved this sale"
    public let loyaltySubtitle: String?

    /// Human-readable savings chip label — e.g. "SAVED $10".
    public let loyaltySavingsChip: String?

    /// Available store-credit balance in cents for the current customer.
    /// Nil means "unknown / not a member" → tile shows generic "Avail. balance".
    public let storeCreditCents: Int?

    /// Bottom action bar injected by the parent (typically `PosTenderAmountBar`).
    public let bottomBar: AnyView

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.posTheme) private var theme

    public init(
        coordinator: PosTenderCoordinator,
        loyaltyTierLabel: String? = nil,
        loyaltySubtitle: String? = nil,
        loyaltySavingsChip: String? = nil,
        storeCreditCents: Int? = nil,
        bottomBar: AnyView = AnyView(EmptyView())
    ) {
        self.coordinator = coordinator
        self.loyaltyTierLabel = loyaltyTierLabel
        self.loyaltySubtitle = loyaltySubtitle
        self.loyaltySavingsChip = loyaltySavingsChip
        self.storeCreditCents = storeCreditCents
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
                // 1. Due-amount hero
                totalHeader
                    .padding(.top, BrandSpacing.lg)
                    .padding(.horizontal, BrandSpacing.base)

                // 2. Member-benefit banner
                if let tier = loyaltyTierLabel {
                    memberBenefitBanner(tier: tier)
                        .padding(.horizontal, BrandSpacing.base)
                }

                // 3. Section label
                sectionLabel("Choose payment method")
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.xs)

                // 4. Method tile grid
                methodGrid
                    .padding(.horizontal, BrandSpacing.base)

                // 5. Split-tender dashed hint
                splitHintRow
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.lg)
            }
        }
    }

    // MARK: - Due-amount hero

    private var totalHeader: some View {
        let isWide = sizeClass == .regular
        return Group {
            if isWide {
                ipadHeroHeader
            } else {
                iphoneHeroHeader
            }
        }
    }

    /// iPhone: centered stack — "Due now" label + giant amount + customer line.
    private var iphoneHeroHeader: some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(coordinator.isSplit ? "Remaining" : "Due now")
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted)
                .tracking(1.4)
                .textCase(.uppercase)
            Text(CartMath.formatCents(coordinator.remaining))
                .font(.brandDisplayLarge())  // 57pt BarlowCondensed-SemiBold
                .foregroundStyle(theme.on)
                .monospacedDigit()
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityIdentifier("pos.tenderV2.remaining")
            if let line = coordinator.customerLine {
                Text(line)
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .padding(.top, BrandSpacing.xxs)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// iPad: flush-left amount + flush-right "Split tender / ⊕ Add method".
    private var ipadHeroHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(coordinator.isSplit ? "Remaining" : "Due now")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                    .tracking(1.4)
                    .textCase(.uppercase)
                Text(CartMath.formatCents(coordinator.remaining))
                    .font(.custom("BarlowCondensed-SemiBold", size: 68, relativeTo: .largeTitle))
                    .foregroundStyle(theme.on)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityIdentifier("pos.tenderV2.remaining")
                if let line = coordinator.customerLine {
                    Text(line)
                        .font(.brandLabelSmall())
                        .foregroundStyle(theme.muted)
                        .padding(.top, BrandSpacing.xxs)
                }
            }
            Spacer(minLength: BrandSpacing.lg)
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text("Split tender")
                    .font(.brandLabelSmall())
                    .foregroundStyle(theme.muted)
                Button {
                    // No-op at step 1 — label is informational;
                    // tap on a method tile enters step 2 for split.
                } label: {
                    Label("Add method", systemImage: "plus.circle")
                        .font(.brandLabelLarge().weight(.bold))
                        .foregroundStyle(theme.teal)
                        .tracking(0.5)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.appliedTenders.isEmpty)
            }
            .padding(.top, BrandSpacing.xs)
        }
    }

    // MARK: - Member-benefit banner

    private func memberBenefitBanner(tier: String) -> some View {
        let isWide = sizeClass == .regular
        return HStack(spacing: isWide ? BrandSpacing.md : BrandSpacing.sm) {
            // Star badge with gradient fill
            ZStack {
                RoundedRectangle(cornerRadius: isWide ? 12 : 10)
                    .fill(
                        LinearGradient(
                            colors: [theme.primaryBright, theme.primary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: isWide ? 42 : 38, height: isWide ? 42 : 38)
                    .shadow(color: theme.primary.opacity(0.3), radius: isWide ? 8 : 6, y: isWide ? 6 : 4)
                Image(systemName: "star.fill")
                    .font(.system(size: isWide ? 22 : 18, weight: .bold))
                    .foregroundStyle(theme.onPrimary)
            }
            .accessibilityHidden(true)

            // Label stack
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("\(tier) member · benefits applied")
                    .font(isWide ? .brandTitleSmall() : .brandLabelLarge())
                    .foregroundStyle(theme.primary)
                if let sub = loyaltySubtitle {
                    Text(sub)
                        .font(.brandLabelSmall())
                        .foregroundStyle(theme.muted)
                } else {
                    Text("Member discount applied · earning loyalty points")
                        .font(.brandLabelSmall())
                        .foregroundStyle(theme.muted)
                }
            }
            Spacer(minLength: 0)

            // Savings chip
            if let chip = loyaltySavingsChip {
                Text(chip)
                    .font(.custom("BarlowCondensed-SemiBold",
                                  size: isWide ? 14 : 12,
                                  relativeTo: .caption))
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, isWide ? BrandSpacing.md : BrandSpacing.sm)
                    .padding(.vertical, isWide ? BrandSpacing.xs : BrandSpacing.xxs)
                    .background(theme.primarySoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.primary.opacity(0.35), lineWidth: 0.5))
            }
        }
        .padding(.vertical, isWide ? BrandSpacing.md : BrandSpacing.sm)
        .padding(.horizontal, isWide ? BrandSpacing.lg : BrandSpacing.md)
        .background(
            // Gold gradient wash over surfaceSolid — matches mockup gradient
            RoundedRectangle(cornerRadius: isWide ? 16 : 14)
                .fill(theme.surfaceSolid)
                .overlay(
                    RoundedRectangle(cornerRadius: isWide ? 16 : 14)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: theme.primary.opacity(0.12), location: 0),
                                    .init(color: theme.primary.opacity(0.02), location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: isWide ? 16 : 14)
                .strokeBorder(theme.primary.opacity(0.38), lineWidth: 1)
        )
        .shadow(color: theme.primary.opacity(0.06), radius: isWide ? 9 : 7, y: isWide ? 6 : 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier) member. \(loyaltySubtitle ?? "Benefits applied at checkout.")")
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted2)
                .tracking(1.6)
                .textCase(.uppercase)
            Spacer()
        }
    }

    // MARK: - Method tile grid

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
                    storeCreditCents: storeCreditCents,
                    theme: theme,
                    onTap: { coordinator.selectMethod(method) }
                )
            }
        }
    }

    // MARK: - Split-tender dashed hint row

    private var splitHintRow: some View {
        let isWide = sizeClass == .regular
        let text = coordinator.isSplit
            ? "Split tender — pick another method for the remainder. Balances update automatically."
            : "Split tender — pick method, enter partial, then pick another"
        return HStack(spacing: isWide ? BrandSpacing.md : BrandSpacing.sm) {
            Text("⊕")
                .font(.system(size: isWide ? 18 : 15))
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandLabelSmall())
                .foregroundStyle(theme.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, isWide ? BrandSpacing.md : BrandSpacing.sm)
        .background(theme.surfaceElev.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(theme.outline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(coordinator.isSplit
            ? "Split tender in progress — \(coordinator.appliedTenders.count) leg(s) applied."
            : "Split tender hint")
    }
}

// MARK: - PosTenderCoordinator + customerLine

extension PosTenderCoordinator {
    /// One-liner shown below the due-amount hero (injected from session context).
    /// The session's view model populates this via the `customerName` and `itemCount`.
    /// Default is nil — hero shows only the amount.
    public var customerLine: String? {
        // Coordinator carries only financials; the session view model should
        // set this before presenting the picker. For now returns nil; the
        // caller populates `PosTenderMethodPickerView` with a ready label via
        // `customerLineSuffix` or similar once Agent H wires the session model.
        nil
    }
}

// MARK: - MethodTile

private struct MethodTile: View {
    let method: TenderMethod
    let isSelected: Bool
    let storeCreditCents: Int?
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
                // Always show the display subtitle — never the "coming soon" hint
                // in the visible label (accessibility hint carries the caveat).
                Text(subtitleText)
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
        .accessibilityHint(method.isReady
            ? "Double tap to select"
            : (method.notReadyHint ?? "Unavailable"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pos.tenderV2.method.\(method.rawValue)")
    }

    /// Subtitle text: store credit gets the live balance when available.
    private var subtitleText: String {
        if method == .storeCredit, let cents = storeCreditCents {
            return "\(CartMath.formatCents(cents)) avail."
        }
        return method.tileSubtitle
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isSelected {
            theme.primarySoft
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
