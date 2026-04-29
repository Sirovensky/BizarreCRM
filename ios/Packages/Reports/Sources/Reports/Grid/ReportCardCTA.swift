import SwiftUI
import DesignSystem

// MARK: - ReportCardActionDestination  (§91.16 per-card CTAs)
//
// Canonical set of screens a report card CTA can route to.
// `ReportsView` receives one callback per destination and wires
// them to the appropriate NavigationPath push or sheet present.
//
// Destinations kept intentionally small — only the three that have
// confirmed actionable data gaps in §91.16 cards:
//   • `.pos`              — Revenue / sales zero-data cards
//   • `.inventoryCreate`  — Inventory stock/movement zero-data cards
//   • `.customerCreate`   — Top-customers zero-data cards

public enum ReportCardActionDestination: Equatable, Sendable {
    /// Navigate to Point of Sale to record a sale.
    case pos
    /// Open the "create inventory item" flow.
    case inventoryCreate
    /// Open the "create customer" flow.
    case customerCreate
}

// MARK: - ReportCardCTAView

/// A compact action button placed at the bottom of a report card's empty state.
///
/// Usage:
/// ```swift
/// ReportCardCTAView(destination: .inventoryCreate, onAction: onNavigate)
/// ```
///
/// The button label and SF Symbol are derived from `destination` so callers
/// never construct the copy — keeping all in-card prompts consistent.
public struct ReportCardCTAView: View {

    public let destination: ReportCardActionDestination
    /// Called when the user taps the button. Parent is responsible for routing.
    public let onAction: (ReportCardActionDestination) -> Void

    public init(
        destination: ReportCardActionDestination,
        onAction: @escaping (ReportCardActionDestination) -> Void
    ) {
        self.destination = destination
        self.onAction = onAction
    }

    public var body: some View {
        Button {
            onAction(destination)
        } label: {
            Label(destination.label, systemImage: destination.systemImage)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.vertical, BrandSpacing.sm)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        // Minimum tap target for a11y (§91.13)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityLabel(destination.accessibilityLabel)
        .accessibilityHint(destination.accessibilityHint)
    }
}

// MARK: - Destination metadata

private extension ReportCardActionDestination {
    var label: String {
        switch self {
        case .pos:             return "Go to Point of Sale"
        case .inventoryCreate: return "Add Inventory Item"
        case .customerCreate:  return "Add Customer"
        }
    }

    var systemImage: String {
        switch self {
        case .pos:             return "creditcard"
        case .inventoryCreate: return "shippingbox.badge.plus"
        case .customerCreate:  return "person.badge.plus"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pos:             return "Open Point of Sale"
        case .inventoryCreate: return "Create a new inventory item"
        case .customerCreate:  return "Create a new customer"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .pos:
            return "Records a sale so this chart can populate"
        case .inventoryCreate:
            return "Adds a product so stock health data can appear"
        case .customerCreate:
            return "Adds a customer so this customer chart can populate"
        }
    }
}
