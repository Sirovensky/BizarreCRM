import SwiftUI
import Charts
import DesignSystem

// MARK: - TaxReportCard
//
// §15.6 — GET /reports/tax
// Shows tax collected by class / rate summary + period total for filing.

public struct TaxEntry: Decodable, Sendable, Identifiable {
    public let id: String
    public let taxClass: String
    public let rate: Double        // percentage, e.g. 8.5
    public let collected: Double   // dollars

    enum CodingKeys: String, CodingKey {
        case taxClass   = "tax_class"
        case rate, collected
    }

    public init(taxClass: String, rate: Double, collected: Double) {
        self.id = "\(taxClass)-\(rate)"
        self.taxClass = taxClass
        self.rate = rate
        self.collected = collected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taxClass  = (try? c.decode(String.self, forKey: .taxClass))  ?? "Default"
        rate      = (try? c.decode(Double.self, forKey: .rate))      ?? 0
        collected = (try? c.decode(Double.self, forKey: .collected)) ?? 0
        id        = "\(taxClass)-\(rate)"
    }
}

public struct TaxReportResponse: Decodable, Sendable {
    public let entries: [TaxEntry]
    public let periodTotal: Double

    enum CodingKeys: String, CodingKey {
        case entries = "by_class"
        case periodTotal = "period_total"
    }

    public init(entries: [TaxEntry] = [], periodTotal: Double = 0) {
        self.entries = entries
        self.periodTotal = periodTotal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries     = (try? c.decode([TaxEntry].self, forKey: .entries)) ?? []
        periodTotal = (try? c.decode(Double.self, forKey: .periodTotal)) ?? 0
    }
}

public struct TaxReportCard: View {
    public let report: TaxReportResponse?
    public let isLoading: Bool

    public init(report: TaxReportResponse?, isLoading: Bool = false) {
        self.report = report
        self.isLoading = isLoading
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Tax Collected")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let r = report {
                        Text(formatCurrency(r.periodTotal))
                            .font(.brandHeadlineMedium())
                            .foregroundStyle(.bizarreOrange)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Image(systemName: "percent")
                    .font(.system(size: 28))
                    .foregroundStyle(.bizarreOrange.opacity(0.5))
                    .accessibilityHidden(true)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading tax report")
            } else if let r = report {
                if r.entries.isEmpty {
                    emptyState
                } else {
                    taxTable(entries: r.entries)
                    filingNote(total: r.periodTotal)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - Tax by class table

    @ViewBuilder
    private func taxTable(entries: [TaxEntry]) -> some View {
        VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("Tax Class")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("Rate")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 55, alignment: .trailing)
                Text("Collected")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.bottom, BrandSpacing.xs)

            Divider().overlay(Color.bizarreOutline.opacity(0.4))

            ForEach(entries) { entry in
                HStack {
                    Text(entry.taxClass)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(String(format: "%.2f%%", entry.rate))
                        .font(.brandMono(size: 14))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 55, alignment: .trailing)
                    Text(formatCurrency(entry.collected))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, BrandSpacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(entry.taxClass): \(String(format: "%.2f", entry.rate)) percent, \(formatCurrency(entry.collected)) collected"
                )

                if entries.last?.id != entry.id {
                    Divider().overlay(Color.bizarreOutline.opacity(0.2))
                }
            }
        }
    }

    // MARK: - Filing note

    private func filingNote(total: Double) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(.bizarreInfo)
                .accessibilityHidden(true)
            Text("Total for period: \(formatCurrency(total)) — export for filing")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.top, BrandSpacing.xs)
        .accessibilityLabel("Total tax collected for period: \(formatCurrency(total)). Export to use for filing.")
    }

    // MARK: - Empty

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "percent").font(.system(size: 30))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No tax data for this period")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(.vertical, BrandSpacing.lg)
        .accessibilityLabel("No tax data for this period")
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
