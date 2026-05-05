import SwiftUI
import DesignSystem

// MARK: - ReportCardCTA  (§91.16 item 4)
//
// Per-card CTA surfaces when a report card has no data ("zero" or "offline" state).
// Each card supplies its own `ReportCardCTASpec` — the label and action that guides
// the user toward the one thing that will make data appear.
//
// Usage (inside a card view):
//
//   if rows.isEmpty {
//       ReportCardCTA(spec: .inventoryHealth)
//   }

// MARK: - Spec

/// Describes the suggested action to show inside an empty report card.
public struct ReportCardCTASpec: Sendable {
    public let icon: String
    public let title: String
    public let buttonLabel: String
    /// Closure invoked when the user taps the button.
    ///
    /// `nil` when the card doesn't know how to navigate directly
    /// (e.g. it needs a parent coordinator). The button is still rendered
    /// but does nothing — callers should prefer always providing an action.
    public let action: (@Sendable () -> Void)?

    public init(icon: String, title: String, buttonLabel: String,
                action: (@Sendable () -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.buttonLabel = buttonLabel
        self.action = action
    }
}

// MARK: - Pre-defined specs (one per report card category)

extension ReportCardCTASpec {

    /// Inventory Health / Turnover card.
    public static func inventoryHealth(action: (@Sendable () -> Void)? = nil) -> ReportCardCTASpec {
        ReportCardCTASpec(
            icon: "shippingbox",
            title: "Add inventory items to enable stock health",
            buttonLabel: "Go to Inventory",
            action: action
        )
    }

    /// Employee Performance card.
    public static func employeePerformance(action: (@Sendable () -> Void)? = nil) -> ReportCardCTASpec {
        ReportCardCTASpec(
            icon: "person.2",
            title: "Add staff members to see performance data",
            buttonLabel: "Manage Employees",
            action: action
        )
    }

    /// CSAT / NPS card.
    public static func customerSatisfaction(action: (@Sendable () -> Void)? = nil) -> ReportCardCTASpec {
        ReportCardCTASpec(
            icon: "star.bubble",
            title: "Enable review requests to see satisfaction scores",
            buttonLabel: "Open Settings",
            action: action
        )
    }

    /// Expenses card.
    public static func expenses(action: (@Sendable () -> Void)? = nil) -> ReportCardCTASpec {
        ReportCardCTASpec(
            icon: "dollarsign.arrow.circlepath",
            title: "Log an expense to see spending analytics",
            buttonLabel: "Add Expense",
            action: action
        )
    }

    /// Revenue card (catch-all / first sale).
    public static func revenue(action: (@Sendable () -> Void)? = nil) -> ReportCardCTASpec {
        ReportCardCTASpec(
            icon: "cart",
            title: "Complete a sale to see revenue charts",
            buttonLabel: "Go to POS",
            action: action
        )
    }

    /// Tickets / Repair card.
    public static func tickets(action: (@Sendable () -> Void)? = nil) -> ReportCardCTASpec {
        ReportCardCTASpec(
            icon: "wrench.and.screwdriver",
            title: "Create a ticket to track repair performance",
            buttonLabel: "New Ticket",
            action: action
        )
    }
}

// MARK: - ReportCardCTA View

public struct ReportCardCTA: View {

    public let spec: ReportCardCTASpec

    public init(spec: ReportCardCTASpec) {
        self.spec = spec
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.md) {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: spec.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.bizarreOrange.opacity(0.7))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(spec.title)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if spec.action != nil {
                Button {
                    spec.action?()
                } label: {
                    Text(spec.buttonLabel)
                        .font(.brandLabelLarge())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.xs)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityLabel(spec.buttonLabel)
            }
        }
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreOrange.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOrange.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spec.title). \(spec.buttonLabel).")
    }
}
