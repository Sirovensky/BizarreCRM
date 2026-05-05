#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.1 — Customer-preview popover.
// Tap the customer avatar/name on a ticket list row → small glass card showing
// recent-tickets count + quick-actions (Call, SMS, Open customer detail).
//
// Presented via `.popover` on iPad and `.sheet(.height(280))` on iPhone.

public struct TicketCustomerPreviewPopover: View {
    let customer: TicketSummary.Customer
    let recentTicketCount: Int?
    let onCall: (() -> Void)?
    let onSMS: (() -> Void)?

    public init(
        customer: TicketSummary.Customer,
        recentTicketCount: Int? = nil,
        onCall: (() -> Void)? = nil,
        onSMS: (() -> Void)? = nil
    ) {
        self.customer = customer
        self.recentTicketCount = recentTicketCount
        self.onCall = onCall
        self.onSMS = onSMS
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.md) {
            // Avatar + name
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.bizarreOrange.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Text(initials)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(customer.displayName)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    if let count = recentTicketCount {
                        Text("\(count) ticket\(count == 1 ? "" : "s")")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Customer: \(customer.displayName)")

            Divider()

            // Quick actions
            HStack(spacing: BrandSpacing.md) {
                if let call = onCall {
                    quickActionButton(icon: "phone.fill", label: "Call", action: call)
                }
                if let sms = onSMS {
                    quickActionButton(icon: "message.fill", label: "SMS", action: sms)
                }
            }
        }
        .padding(BrandSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .frame(maxWidth: 280)
    }

    private var initials: String {
        let parts = customer.displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.brandLabelLarge())
            }
            .foregroundStyle(.bizarreOrange)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreOrange.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .hoverEffect(.highlight)
    }
}

// MARK: - View modifier for attaching the popover

extension View {
    /// Attaches a customer-preview popover that triggers on a tap. iPad shows a
    /// native `.popover`; iPhone shows a bottom sheet at 280pt height.
    public func ticketCustomerPreviewPopover(
        isPresented: Binding<Bool>,
        customer: TicketSummary.Customer?,
        recentTicketCount: Int? = nil,
        onCall: (() -> Void)? = nil,
        onSMS: (() -> Void)? = nil
    ) -> some View {
        self.modifier(
            TicketCustomerPreviewModifier(
                isPresented: isPresented,
                customer: customer,
                recentTicketCount: recentTicketCount,
                onCall: onCall,
                onSMS: onSMS
            )
        )
    }
}

private struct TicketCustomerPreviewModifier: ViewModifier {
    @Binding var isPresented: Bool
    let customer: TicketSummary.Customer?
    let recentTicketCount: Int?
    let onCall: (() -> Void)?
    let onSMS: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let customer {
                    TicketCustomerPreviewPopover(
                        customer: customer,
                        recentTicketCount: recentTicketCount,
                        onCall: onCall,
                        onSMS: onSMS
                    )
                    .presentationDetents([.height(200)])
                    .presentationDragIndicator(.visible)
                }
            }
    }
}
#endif
