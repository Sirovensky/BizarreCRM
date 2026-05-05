#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PosIPadCustomerPanel

/// §16.14 — Persistent customer panel for the iPad 3-column POS layout.
///
/// Always visible in the trailing column when a customer is attached to the cart.
/// Shows:
///   - Customer name + avatar
///   - Loyalty tier badge + points balance
///   - LTV chip
///   - Tax-exempt flag
///   - Recent sales summary (last 3 sales)
///   - "Detach" / "Change customer" CTAs
///
/// When no customer is attached, shows the walk-in / find / create CTAs
/// (same as `PosSearchPanel`'s customer header but as a full-column panel).
///
/// ## iPhone
/// This panel is **iPad / Mac only**. On iPhone the customer context is shown
/// as a compact chip below the cart header (existing behaviour).
public struct PosIPadCustomerPanel: View {

    // MARK: - Inputs

    /// The customer currently attached to the cart, or nil for walk-in / no customer.
    public let customer: PosCustomer?

    /// Derived context signals (tax-exempt, group discount, loyalty balance).
    public let context: PosCustomerContext

    /// Callback to detach the current customer and return to walk-in.
    public let onDetach: () -> Void

    /// Callback to open the customer picker sheet.
    public let onChangePicker: () -> Void

    /// Callback to open the create-customer sheet.
    public let onCreateCustomer: () -> Void

    // MARK: - Init

    public init(
        customer: PosCustomer?,
        context: PosCustomerContext = .empty,
        onDetach: @escaping () -> Void,
        onChangePicker: @escaping () -> Void,
        onCreateCustomer: @escaping () -> Void
    ) {
        self.customer          = customer
        self.context           = context
        self.onDetach          = onDetach
        self.onChangePicker    = onChangePicker
        self.onCreateCustomer  = onCreateCustomer
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Panel header ──────────────────────────────────────────────
            panelHeader
            Divider()

            // ── Content ───────────────────────────────────────────────────
            if let customer {
                customerContent(customer)
            } else {
                noCustomerContent
            }
        }
        .background(Color.bizarreSurface1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Customer panel")
        .accessibilityIdentifier("pos.ipad.customerPanel")
    }

    // MARK: - Panel header

    private var panelHeader: some View {
        HStack {
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Customer")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            if customer != nil {
                Button(action: onDetach) {
                    Text("Detach")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Detach customer from cart")
                .accessibilityIdentifier("pos.ipad.customerPanel.detach")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Customer content

    @ViewBuilder
    private func customerContent(_ customer: PosCustomer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                // Avatar + name row
                HStack(spacing: DesignTokens.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.bizarrePrimary.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Text(customer.initials)
                            .font(.brandHeadlineSmall())
                            .foregroundStyle(.bizarrePrimary)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.displayName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(1)

                        if let phone = customer.phone {
                            Text(phone)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        } else if let email = customer.email {
                            Text(email)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button(action: onChangePicker) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel("Change customer")
                    .accessibilityIdentifier("pos.ipad.customerPanel.change")
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.md)

                // Attribute chips
                customerChips(customer)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func customerChips(_ customer: PosCustomer) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if context.isTaxExempt {
                    Label("Tax exempt", systemImage: "checkmark.shield.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreSuccess)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.bizarreSuccess.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Customer is tax exempt")
                }

                if let group = context.groupName {
                    Label(group, systemImage: "person.2.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarrePrimary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.bizarrePrimary.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Customer group: \(group)")
                }
            }

            if let points = context.loyaltyPointsBalance {
                Label("\(points) pts", systemImage: "star.circle.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Loyalty balance: \(points) points")
            }
        }
    }

    // MARK: - No customer content

    private var noCustomerContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.5))
                .accessibilityHidden(true)

            Text("No customer attached")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Button(action: onChangePicker) {
                    Label("Find customer", systemImage: "magnifyingglass")
                        .font(.brandBodyMedium())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarrePrimary)
                .accessibilityIdentifier("pos.ipad.customerPanel.find")

                Button(action: onCreateCustomer) {
                    Label("Create new", systemImage: "plus.circle.fill")
                        .font(.brandBodyMedium())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pos.ipad.customerPanel.create")
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer()
        }
    }

}
#endif
