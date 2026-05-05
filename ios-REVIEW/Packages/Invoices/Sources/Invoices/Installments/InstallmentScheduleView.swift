#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.9 InstallmentScheduleView — visualize upcoming installments on InvoiceDetailView

/// Embeddable card that shows the installment schedule for an invoice.
/// Designed to be placed inside `InvoiceDetailView`'s scroll content.
public struct InstallmentScheduleView: View {
    public let plan: InstallmentPlan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(plan: InstallmentPlan) {
        self.plan = plan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            ForEach(plan.installments.sorted { $0.dueDate < $1.dueDate }) { item in
                InstallmentRow(item: item, reduceMotion: reduceMotion)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rowLabel(for: item))
            }
            summaryRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Payment Plan")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if plan.autopay {
                Label("Autopay", systemImage: "bolt.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityLabel("Autopay enabled")
            }
        }
    }

    private var summaryRow: some View {
        HStack {
            Text("Remaining")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(plan.remainingCents))
                .font(.brandTitleMedium())
                .foregroundStyle(plan.remainingCents > 0 ? .bizarreError : .bizarreSuccess)
                .monospacedDigit()
        }
        .padding(.top, BrandSpacing.xs)
    }

    private func rowLabel(for item: InstallmentItem) -> String {
        let date = shortDate(item.dueDate)
        let amount = formatMoney(item.amountCents)
        let status = item.isPaid ? "Paid" : "Due \(date)"
        return "\(amount). \(status)."
    }
}

// MARK: - Row

private struct InstallmentRow: View {
    let item: InstallmentItem
    let reduceMotion: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            statusIcon
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(Self.dateFormatter.string(from: item.dueDate))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if let paidAt = item.paidAt {
                    Text("Paid \(Self.dateFormatter.string(from: paidAt))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreSuccess)
                }
            }
            Spacer()
            Text(formatMoney(item.amountCents))
                .font(.brandBodyMedium())
                .foregroundStyle(item.isPaid ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .monospacedDigit()
                .strikethrough(item.isPaid)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .contentShape(Rectangle())
    }

    private var statusIcon: some View {
        Image(systemName: item.isPaid ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(item.isPaid ? Color.bizarreSuccess : Color.bizarreOnSurfaceMuted)
            .imageScale(.medium)
            .animation(reduceMotion ? nil : .spring, value: item.isPaid)
    }
}

// MARK: - Helpers

private func shortDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f.string(from: date)
}

private func formatMoney(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
