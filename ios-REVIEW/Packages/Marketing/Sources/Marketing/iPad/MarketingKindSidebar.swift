import SwiftUI
import DesignSystem

// MARK: - MarketingKind

/// Top-level section discriminator for the Marketing sidebar.
public enum MarketingKind: String, CaseIterable, Identifiable, Sendable, Hashable {
    case campaigns
    case coupons
    case referrals
    case reviews

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .campaigns:  return "Campaigns"
        case .coupons:    return "Coupons"
        case .referrals:  return "Referrals"
        case .reviews:    return "Reviews"
        }
    }

    public var systemImage: String {
        switch self {
        case .campaigns:  return "megaphone.fill"
        case .coupons:    return "ticket.fill"
        case .referrals:  return "person.2.fill"
        case .reviews:    return "star.fill"
        }
    }
}

// MARK: - MarketingKindSidebar

/// Left-most column of the 3-column iPad layout: a List of `MarketingKind`
/// entries styled with Liquid Glass navigation chrome.
public struct MarketingKindSidebar: View {
    @Binding var selection: MarketingKind?

    public init(selection: Binding<MarketingKind?>) {
        _selection = selection
    }

    public var body: some View {
        List(MarketingKind.allCases, selection: $selection) { kind in
            Label(kind.displayName, systemImage: kind.systemImage)
                .font(.brandBodyLarge())
                .foregroundStyle(selection == kind ? Color.bizarreOrange : Color.bizarreOnSurface)
                .accessibilityLabel(kind.displayName)
                .accessibilityIdentifier("marketing.sidebar.\(kind.rawValue)")
                #if canImport(UIKit)
                .hoverEffect(.highlight)
                #endif
        }
        .navigationTitle("Marketing")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .accessibilityLabel("Marketing sections")
    }
}
