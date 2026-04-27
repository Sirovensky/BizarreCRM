#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - DepositInvoicesSummary
//
// §7.2: Deposit invoices linked — nested card showing connected deposit invoices.
// The server returns associated deposit invoices via
//   GET /api/v1/invoices?deposit_parent_id=:id
// We fetch them once on appear and display them inline.

public struct DepositInvoiceSummary: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let orderId: String?
    public let total: Double?
    public let amountPaid: Double?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id, total, status
        case orderId    = "order_id"
        case amountPaid = "amount_paid"
    }
}

// MARK: - API extension

public extension APIClient {
    /// GET /api/v1/invoices?deposit_parent_id=:id
    /// Returns deposit invoices linked to the given parent invoice.
    func depositInvoices(parentId: Int64) async throws -> [DepositInvoiceSummary] {
        let query = [URLQueryItem(name: "deposit_parent_id", value: String(parentId))]
        struct ListResponse: Decodable {
            let data: [DepositInvoiceSummary]?
        }
        let resp = try await get("/api/v1/invoices", query: query, as: ListResponse.self)
        return resp.data ?? []
    }
}

// MARK: - DepositInvoicesCard

public struct DepositInvoicesCard: View {
    private let api: APIClient
    private let parentInvoiceId: Int64
    public let onTapDeposit: (Int64) -> Void

    @State private var deposits: [DepositInvoiceSummary] = []
    @State private var isLoading = false

    public init(api: APIClient,
                parentInvoiceId: Int64,
                onTapDeposit: @escaping (Int64) -> Void) {
        self.api = api
        self.parentInvoiceId = parentInvoiceId
        self.onTapDeposit = onTapDeposit
    }

    public var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView().padding(.trailing, BrandSpacing.xs)
                    Text("Loading deposits…")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
            } else if !deposits.isEmpty {
                depositsCard
            }
            // If deposits is empty after load we show nothing (no deposit invoices linked).
        }
        .task { await load() }
    }

    private var depositsCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "doc.text.below.ecg")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Deposit Invoices")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text("\(deposits.count)")
                    .font(.brandLabelSmall())
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreOrange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Deposit invoices, \(deposits.count) linked")

            ForEach(deposits) { deposit in
                Button {
                    onTapDeposit(deposit.id)
                } label: {
                    depositRow(deposit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(depositA11yLabel(deposit))
            }
        }
        .cardBackground()
    }

    private func depositRow(_ deposit: DepositInvoiceSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(deposit.orderId ?? "DEP-\(deposit.id)")
                    .font(.brandMono(size: 14))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)

                let paid   = deposit.amountPaid ?? 0
                let total  = deposit.total ?? 0
                let balance = max(0, total - paid)
                if balance > 0 {
                    Text("Balance: \(formatMoney(balance))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                } else {
                    Text("Paid")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreSuccess)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(formatMoney(deposit.total ?? 0))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                depositStatusBadge(deposit.status)
            }
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
    }

    @ViewBuilder
    private func depositStatusBadge(_ status: String?) -> some View {
        let s = (status ?? "").lowercased()
        let (bg, fg): (Color, Color) = {
            switch s {
            case "paid":    return (.bizarreSuccess, .black)
            case "partial": return (.bizarreWarning, .black)
            case "unpaid":  return (.bizarreError, .black)
            default:        return (.bizarreSurface2, .bizarreOnSurface)
            }
        }()
        Text(status?.capitalized ?? "—")
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
    }

    private func depositA11yLabel(_ deposit: DepositInvoiceSummary) -> String {
        let id = deposit.orderId ?? "DEP-\(deposit.id)"
        let total = formatMoney(deposit.total ?? 0)
        let status = deposit.status?.capitalized ?? "unknown status"
        return "Deposit invoice \(id), \(total), \(status)"
    }

    private func load() async {
        isLoading = true
        do {
            deposits = try await api.depositInvoices(parentId: parentInvoiceId)
        } catch {
            deposits = []
        }
        isLoading = false
    }
}

// MARK: - Card helper (mirrors InvoiceDetailView)

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
#endif
