#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §22 — iPad trailing inspector: totals summary + payments timeline

/// Trailing-column inspector that displays a compact totals summary and a
/// scrollable payments timeline for the selected invoice. Loaded lazily when
/// an invoice is selected in the three-column layout.
///
/// Layout:
/// ```
/// ┌─────────────────────┐
/// │  TOTALS             │   Liquid Glass header
/// │  Subtotal   $xxx    │
/// │  Tax        $xx     │
/// │  Total      $xxx    │
/// │  Paid       $xx     │
/// │  Due        $xx     │
/// ├─────────────────────┤
/// │  TIMELINE           │
/// │  ●  Payment  $xx    │
/// │  ●  Refund  -$xx    │
/// └─────────────────────┘
/// ```
public struct InvoiceInspector: View {

    // MARK: - State

    @State private var state: LoadState = .loading
    @ObservationIgnored private let invoiceId: Int64
    @ObservationIgnored private let repo: InvoiceDetailRepository

    // MARK: - Init

    public init(invoiceId: Int64, repo: InvoiceDetailRepository) {
        self.invoiceId = invoiceId
        self.repo = repo
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                switch state {
                case .loading:
                    loadingPlaceholder
                case .loaded(let inv):
                    inspectorContent(inv)
                case .failed(let msg):
                    errorView(message: msg)
                }
            }
        }
        .task(id: invoiceId) { await load() }
    }

    // MARK: - Content

    private func inspectorContent(_ inv: InvoiceDetail) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                totalsSection(inv)
                Divider()
                    .overlay(Color.bizarreOutline.opacity(0.4))
                timelineSection(inv)
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Totals section

    private func totalsSection(_ inv: InvoiceDetail) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Totals", icon: "doc.text")

            if let sub = inv.subtotal, sub != (inv.total ?? 0) {
                totalsRow("Subtotal", value: sub)
            }
            if let disc = inv.discount, disc > 0 {
                totalsRow("Discount", value: -disc, tint: .bizarreSuccess)
            }
            if let tax = inv.totalTax, tax > 0 {
                totalsRow("Tax", value: tax)
            }

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            HStack {
                Text("Total")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(inv.total ?? 0))
                    .font(.brandTitleLarge())
                    .bold()
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            if let paid = inv.amountPaid, paid > 0 {
                totalsRow("Paid", value: -paid, tint: .bizarreSuccess)
            }
            if let due = inv.amountDue, due > 0 {
                HStack {
                    Text("Due")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                    Spacer()
                    Text(formatMoney(due))
                        .font(.brandBodyMedium())
                        .bold()
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Timeline section

    private func timelineSection(_ inv: InvoiceDetail) -> some View {
        let entries = buildPaymentHistory(from: inv)
        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Timeline", icon: "clock")

            if entries.isEmpty {
                Text("No transactions yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.top, BrandSpacing.xs)
                    .accessibilityLabel("No transactions recorded")
            } else {
                ForEach(entries) { entry in
                    TimelineRow(entry: entry)
                    if entry.id != entries.last?.id {
                        Divider()
                            .overlay(Color.bizarreOutline.opacity(0.25))
                    }
                }
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.6)
        }
        .padding(.bottom, BrandSpacing.xxs)
    }

    // MARK: - Totals row helper

    private func totalsRow(_ label: String, value: Double, tint: Color = .bizarreOnSurface) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(value))
                .font(.brandBodyMedium())
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    // MARK: - Loading / error

    private var loadingPlaceholder: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView()
            Text("Loading…")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load details")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data loading

    private func load() async {
        state = .loading
        do {
            let inv = try await repo.detail(id: invoiceId)
            state = .loaded(inv)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Formatting

    private func formatMoney(_ dollars: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    // MARK: - Load state

    enum LoadState {
        case loading
        case loaded(InvoiceDetail)
        case failed(String)
    }
}

// MARK: - Timeline Row

private struct TimelineRow: View {
    let entry: PaymentHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            // Timeline dot / icon
            VStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(entry.kind.timelineLabel)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(formattedAmount)
                        .font(.brandBodyMedium())
                        .bold()
                        .foregroundStyle(amountColor)
                        .monospacedDigit()
                }
                HStack(spacing: BrandSpacing.xxs) {
                    Text(String(entry.timestamp.prefix(10)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let op = entry.operatorName, !op.isEmpty {
                        Text("· \(op)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var dotColor: Color {
        switch entry.kind {
        case .payment: return .bizarreSuccess
        case .refund:  return .bizarreWarning
        case .void:    return .bizarreError
        }
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

    private var a11yLabel: String {
        let date = String(entry.timestamp.prefix(10))
        let op = entry.operatorName.map { ", by \($0)" } ?? ""
        return "\(entry.kind.timelineLabel): \(formattedAmount) on \(date)\(op)"
    }
}

private extension PaymentHistoryKind {
    var timelineLabel: String {
        switch self {
        case .payment: return "Payment"
        case .refund:  return "Refund"
        case .void:    return "Voided"
        }
    }
}
#endif
