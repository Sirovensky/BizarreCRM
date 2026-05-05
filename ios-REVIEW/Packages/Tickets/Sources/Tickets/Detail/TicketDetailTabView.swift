#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.2 — Tab layout for TicketDetailView.
// Tabs: Actions / Devices / Notes / Payments
//
// iPhone: segmented control picker at top of detail; selected tab's content
//         shown inline below.
// iPad/Mac: tab picker in toolbar or sidebar column; content fills remainder.
//
// Usage: embed inside TicketDetailView below the header cards.

// MARK: - Tab enum

public enum TicketDetailTab: String, CaseIterable, Identifiable {
    case actions   = "Actions"
    case devices   = "Devices"
    case notes     = "Notes"
    case payments  = "Payments"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .actions:  return "bolt.fill"
        case .devices:  return "iphone.gen3"
        case .notes:    return "note.text"
        case .payments: return "creditcard.fill"
        }
    }
}

// MARK: - Tab picker (segmented on iPhone, inline Picker on iPad)

public struct TicketDetailTabPicker: View {
    @Binding var selection: TicketDetailTab

    public init(selection: Binding<TicketDetailTab>) {
        self._selection = selection
    }

    public var body: some View {
        if Platform.isCompact {
            // iPhone: segmented control
            Picker("Tab", selection: $selection) {
                ForEach(TicketDetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)
            .accessibilityLabel("Ticket detail tab")
        } else {
            // iPad / Mac: horizontal scrolling tabs with icons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(TicketDetailTab.allCases) { tab in
                        Button {
                            selection = tab
                        } label: {
                            HStack(spacing: BrandSpacing.xs) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 12, weight: .medium))
                                    .accessibilityHidden(true)
                                Text(tab.rawValue)
                                    .font(.brandBodyMedium())
                            }
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.xs)
                            .foregroundStyle(selection == tab ? Color.white : Color.bizarreOnSurface)
                            .background(
                                selection == tab ? Color.bizarreOrange : Color.clear,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.rawValue)
                        .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
                        .hoverEffect(.highlight)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.xs)
            }
            .background(Color.bizarreSurface1)
        }
    }
}

// MARK: - Payments tab content

/// §4.2 — Shows the payments associated with this ticket's invoice.
/// Each row: method · amount · date.
public struct TicketPaymentsTabView: View {
    public let payments: [TicketDetail.TicketPayment]

    public init(payments: [TicketDetail.TicketPayment]) {
        self.payments = payments
    }

    public var body: some View {
        if payments.isEmpty {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "creditcard")
                    .font(.system(size: 28))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No payments recorded")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.lg)
        } else {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Payments")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                ForEach(payments) { payment in
                    PaymentRow(payment: payment)
                }
                Divider().overlay(Color.bizarreOutline.opacity(0.4))
                HStack {
                    Text("Paid")
                        .font(.brandBodyMedium().bold())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(formatMoney(payments.reduce(0.0) { $0 + $1.amount }))
                        .font(.brandBodyMedium().bold())
                        .foregroundStyle(.bizarreSuccess)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total paid: \(formatMoney(payments.reduce(0.0) { $0 + $1.amount }))")
            }
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

private struct PaymentRow: View {
    let payment: TicketDetail.TicketPayment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.methodDisplay)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let date = payment.createdAt {
                    Text(formatDate(date))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            Text(formatMoney(payment.amount))
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreSuccess)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(payment.methodDisplay), \(formatMoney(payment.amount))")
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return iso
    }
}
#endif
