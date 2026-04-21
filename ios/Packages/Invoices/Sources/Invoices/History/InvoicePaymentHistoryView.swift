#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.7 Invoice Payment History View

// MARK: - View

public struct InvoicePaymentHistoryView: View {
    public let entries: [PaymentHistoryEntry]

    public init(entries: [PaymentHistoryEntry]) {
        self.entries = entries
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Payment History")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if entries.isEmpty {
                Text("No payments recorded.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No payments recorded")
            } else {
                ForEach(entries) { entry in
                    PaymentHistoryRow(entry: entry)
                    if entry.id != entries.last?.id {
                        Divider().overlay(Color.bizarreOutline.opacity(0.3))
                    }
                }
            }
        }
        .cardBackground()
    }
}

// MARK: - Row

private struct PaymentHistoryRow: View {
    let entry: PaymentHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            kindBadge
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    if let tender = entry.tender, !tender.isEmpty {
                        Text(tender.capitalized)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    Spacer()
                    Text(formattedAmount)
                        .font(.brandBodyMedium())
                        .bold()
                        .foregroundStyle(amountColor)
                        .monospacedDigit()
                }
                HStack(spacing: BrandSpacing.xs) {
                    Text(formattedDate)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let op = entry.operatorName, !op.isEmpty {
                        Text("• \(op)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var kindBadge: some View {
        VStack {
            Image(systemName: entry.kind.systemIcon)
                .font(.system(size: 22))
                .foregroundStyle(entry.kind.badgeColor)
                .accessibilityHidden(true)
            Text(entry.kind.badgeLabel)
                .font(.brandLabelSmall())
                .foregroundStyle(entry.kind.badgeColor)
                .accessibilityHidden(true)
        }
        .frame(width: 56)
    }

    private var amountColor: Color {
        switch entry.kind {
        case .refund: return .bizarreError
        case .void:   return .bizarreOnSurfaceMuted
        case .payment: return .bizarreSuccess
        }
    }

    private var formattedAmount: String {
        let abs = Swift.abs(entry.amountCents)
        let prefix = entry.kind == .refund ? "-" : ""
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return prefix + (f.string(from: NSNumber(value: Double(abs) / 100.0)) ?? "\(abs)")
    }

    private var formattedDate: String {
        let raw = entry.timestamp
        if raw.isEmpty { return "—" }
        return String(raw.prefix(10))
    }

    private var accessibilityDescription: String {
        let amount = formattedAmount
        let date = formattedDate
        let op = entry.operatorName.map { ", by \($0)" } ?? ""
        return "\(entry.kind.badgeLabel): \(amount) on \(date)\(op)"
    }
}

// MARK: - PaymentHistoryKind display helpers

private extension PaymentHistoryKind {
    var badgeColor: Color {
        switch self {
        case .payment: return .bizarreSuccess
        case .refund:  return .bizarreWarning
        case .void:    return .bizarreError
        }
    }

    var badgeLabel: String {
        switch self {
        case .payment: return "Payment"
        case .refund:  return "Refund"
        case .void:    return "Void"
        }
    }

    var systemIcon: String {
        switch self {
        case .payment: return "checkmark.circle.fill"
        case .refund:  return "arrow.uturn.left.circle.fill"
        case .void:    return "xmark.circle.fill"
        }
    }
}

// MARK: - Helpers

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}
#endif
