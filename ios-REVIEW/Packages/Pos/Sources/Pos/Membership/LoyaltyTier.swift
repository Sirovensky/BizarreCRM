// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// This module MUST NOT be imported by, or rendered inside:
//   • Cart / PosCartPanel / PosCartAdjustmentSheets
//   • Catalog / PosSearchPanel / PosCatalogGrid
//   • Customer gate / PosGateView / PosCustomerPickerSheet
//   • Ticket inspector / any Inspector-pane view
//
// Correct placement: PosTenderMethodPickerView (banner) and PosReceiptView /
// PosPostSaleView (tier-progress row). If you are reading this file from any
// other view, stop and re-read the §Agent-H rule above.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

/// The four loyalty tiers recognised by BizarreCRM.
///
/// Raw values match the lowercase tier-name strings returned by
/// `GET /api/v1/membership/customer/:id` (field `tier_name` from
/// `CustomerSubscriptionDTO.tierName`), and the `autoTierName` helper in
/// `LoyaltyEndpoints.swift`.
///
/// `none` is the sentinel for customers who have no membership record —
/// UI components must hide themselves when `tier == .none`.
public enum LoyaltyTier: String, Sendable, Equatable, CaseIterable {
    case none      = "none"
    case silver    = "silver"
    case gold      = "gold"
    case platinum  = "platinum"

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .none:     return "No tier"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .platinum: return "Platinum"
        }
    }

    // MARK: - Points thresholds

    /// Minimum cumulative points to hold this tier.
    /// Mirrors the `autoTierName` logic in `LoyaltyEndpoints.swift`
    /// (spend-based) but expressed as points for the POS redemption layer.
    public var minimumPoints: Int {
        switch self {
        case .none:     return 0
        case .silver:   return 100
        case .gold:     return 250
        case .platinum: return 500
        }
    }

    /// The tier that follows this one (nil for `.platinum` and `.none`).
    public var next: LoyaltyTier? {
        switch self {
        case .none:     return nil
        case .silver:   return .gold
        case .gold:     return .platinum
        case .platinum: return nil
        }
    }

    // MARK: - Theming

    /// Brand color for tier badges. Falls back to `.bizarreOnSurfaceMuted`
    /// for `.none` so hidden-state callers that accidentally render still
    /// produce a legible-enough no-op indicator rather than a crash.
    public var color: Color {
        switch self {
        case .none:     return .bizarreOnSurfaceMuted
        case .silver:   return Color(red: 0.73, green: 0.73, blue: 0.78)  // cool silver
        case .gold:     return Color(red: 1.0,  green: 0.80, blue: 0.22)  // brand gold
        case .platinum: return Color(red: 0.74, green: 0.90, blue: 1.0)   // icy platinum
        }
    }

    // MARK: - Progress helper

    /// Fraction (0…1) representing how far `currentPoints` is between this
    /// tier's minimum and the next tier's minimum. Always returns 0 for
    /// `.none` and 1 for `.platinum` (already at the top).
    ///
    /// - Parameter currentPoints: The customer's current points balance.
    public func progressTo(next nextTier: LoyaltyTier, currentPoints: Int) -> Double {
        guard let next = self.next, next == nextTier else { return 1.0 }
        let span = next.minimumPoints - self.minimumPoints
        guard span > 0 else { return 1.0 }
        let earned = currentPoints - self.minimumPoints
        return max(0.0, min(1.0, Double(earned) / Double(span)))
    }

    /// Points still needed to reach the next tier. 0 for `.platinum`.
    public func pointsNeeded(currentPoints: Int) -> Int {
        guard let next = self.next else { return 0 }
        return max(0, next.minimumPoints - currentPoints)
    }

    // MARK: - Init from raw server string

    /// Failable initialiser from the lowercase server tier name.
    /// Unknown / nil strings map to `.none`.
    public static func from(serverName: String?) -> LoyaltyTier {
        guard let name = serverName else { return .none }
        return LoyaltyTier(rawValue: name.lowercased()) ?? .none
    }
}
