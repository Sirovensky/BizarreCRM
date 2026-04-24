import SwiftUI
import DesignSystem

// MARK: - TierSidebarItem

/// Data for one row in the tier sidebar.
public struct TierSidebarItem: Identifiable, Equatable, Sendable {
    public let id: LoyaltyTier
    /// Total members at this tier (displayed as a badge).
    public let memberCount: Int

    public init(tier: LoyaltyTier, memberCount: Int = 0) {
        self.id = tier
        self.memberCount = memberCount
    }
}

// MARK: - LoyaltyTierSidebar

/// §22 — First column of the iPad 3-col loyalty layout.
///
/// Displays Bronze / Silver / Gold / Platinum tiers as selectable rows.
/// The selection drives `LoyaltyThreeColumnView`'s member-list column.
///
/// Design:
/// • Glass toolbar header.
/// • `.hoverEffect(.highlight)` on each row (iPad/Mac pointer UX).
/// • `.isSelected` accessibility trait on the active row.
/// • Member-count badge per row.
public struct LoyaltyTierSidebar: View {

    // Binding propagates selection up to the three-column coordinator.
    @Binding private var selectedTier: LoyaltyTier?
    private let items: [TierSidebarItem]
    private let onRefresh: (() async -> Void)?

    /// Convenience initialiser that builds items from a tier→memberCount map.
    public init(
        selectedTier: Binding<LoyaltyTier?>,
        memberCounts: [LoyaltyTier: Int] = [:],
        onRefresh: (() async -> Void)? = nil
    ) {
        _selectedTier = selectedTier
        items = LoyaltyTier.allCases.map { tier in
            TierSidebarItem(tier: tier, memberCount: memberCounts[tier] ?? 0)
        }
        self.onRefresh = onRefresh
    }

    public var body: some View {
        List(items, selection: $selectedTier) { item in
            TierSidebarRow(item: item, isSelected: selectedTier == item.id)
                .tag(item.id)
                #if canImport(UIKit)
                .hoverEffect(.highlight)
                #endif
        }
        .listStyle(.sidebar)
        .navigationTitle("Tiers")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if let refresh = onRefresh {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .accessibilityLabel("Refresh tier list")
                }
            }
        }
    }
}

// MARK: - TierSidebarRow

private struct TierSidebarRow: View {
    let item: TierSidebarItem
    let isSelected: Bool

    private var tier: LoyaltyTier { item.id }

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            // Tier icon
            Image(systemName: tier.systemSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tier.displayColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            // Name + perks subtitle
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(tier.displayName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(tier.perksDescription)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }

            Spacer()

            // Member count badge
            if item.memberCount > 0 {
                Text(item.memberCount.formatted(.number))
                    .font(.brandLabelSmall())
                    .foregroundStyle(isSelected ? tier.displayColor : .bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(
                        Capsule()
                            .fill(isSelected
                                  ? tier.displayColor.opacity(0.15)
                                  : Color.bizarreSurface2)
                    )
                    .accessibilityLabel("\(item.memberCount) members")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.displayName) tier. \(tier.perksDescription).")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
