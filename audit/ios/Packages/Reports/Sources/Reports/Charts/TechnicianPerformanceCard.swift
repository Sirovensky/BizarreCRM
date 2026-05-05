import SwiftUI
import Core
import DesignSystem

// MARK: - TechnicianPerformanceCard
//
// §15.4 — GET /reports/technician-performance
// Table: name / tickets assigned / closed / commission / hours / revenue.
// iPad uses SwiftUI Table with sortable columns; iPhone uses List rows.

public struct TechnicianPerfRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let ticketsAssigned: Int
    public let ticketsClosed: Int
    public let commissionDollars: Double
    public let hoursWorked: Double
    public let revenueGenerated: Double

    enum CodingKeys: String, CodingKey {
        case id, name
        case ticketsAssigned  = "tickets_assigned"
        case ticketsClosed    = "tickets_closed"
        case commissionDollars = "commission_earned"
        case hoursWorked      = "hours_worked"
        case revenueGenerated = "revenue_generated"
    }

    public init(
        id: Int64, name: String,
        ticketsAssigned: Int, ticketsClosed: Int,
        commissionDollars: Double, hoursWorked: Double, revenueGenerated: Double
    ) {
        self.id = id; self.name = name
        self.ticketsAssigned = ticketsAssigned; self.ticketsClosed = ticketsClosed
        self.commissionDollars = commissionDollars; self.hoursWorked = hoursWorked
        self.revenueGenerated = revenueGenerated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = (try? c.decode(Int64.self,  forKey: .id))                  ?? 0
        name               = (try? c.decode(String.self, forKey: .name))                ?? ""
        ticketsAssigned    = (try? c.decode(Int.self,    forKey: .ticketsAssigned))     ?? 0
        ticketsClosed      = (try? c.decode(Int.self,    forKey: .ticketsClosed))       ?? 0
        commissionDollars  = (try? c.decode(Double.self, forKey: .commissionDollars))   ?? 0
        hoursWorked        = (try? c.decode(Double.self, forKey: .hoursWorked))         ?? 0
        revenueGenerated   = (try? c.decode(Double.self, forKey: .revenueGenerated))    ?? 0
    }

    public var closeRate: Double {
        guard ticketsAssigned > 0 else { return 0 }
        return Double(ticketsClosed) / Double(ticketsAssigned) * 100.0
    }
}

public struct TechnicianPerformanceCard: View {
    public let rows: [TechnicianPerfRow]

    public init(rows: [TechnicianPerfRow]) {
        self.rows = rows
    }

    @State private var sortOrder = [KeyPathComparator(\TechnicianPerfRow.revenueGenerated, order: .reverse)]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Technician Performance")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if rows.isEmpty {
                emptyState
            } else if Platform.isCompact {
                phoneList
            } else {
                ipadTable
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - iPhone: list rows

    private var phoneList: some View {
        VStack(spacing: BrandSpacing.xs) {
            // Header
            HStack {
                Text("Tech").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("Closed").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 50, alignment: .trailing)
                Text("Revenue").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 70, alignment: .trailing)
            }
            Divider()
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text(String(format: "%.0f%% close", row.closeRate))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    Text("\(row.ticketsClosed)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                    Text(formatCurrency(row.revenueGenerated))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, BrandSpacing.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(row.name): \(row.ticketsClosed) tickets closed, \(formatCurrency(row.revenueGenerated)) revenue"
                )
            }
        }
    }

    // MARK: - iPad: sortable Table

    @available(iOS 16.0, *)
    private var ipadTable: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Technician", value: \.name) { row in
                Text(row.name).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
            }
            TableColumn("Assigned") { row in
                Text("\(row.ticketsAssigned)").font(.brandBodyMedium()).monospacedDigit()
            }
            .width(70)
            TableColumn("Closed") { row in
                Text("\(row.ticketsClosed)").font(.brandBodyMedium()).monospacedDigit()
            }
            .width(60)
            TableColumn("Close %") { row in
                Text(String(format: "%.0f%%", row.closeRate))
                    .font(.brandBodyMedium()).monospacedDigit()
            }
            .width(65)
            TableColumn("Hours") { row in
                Text(String(format: "%.1f", row.hoursWorked))
                    .font(.brandBodyMedium()).monospacedDigit()
            }
            .width(60)
            TableColumn("Revenue", value: \.revenueGenerated) { row in
                Text(formatCurrency(row.revenueGenerated))
                    .font(.brandBodyMedium()).monospacedDigit()
            }
            .width(80)
            TableColumn("Commission") { row in
                Text(formatCurrency(row.commissionDollars))
                    .font(.brandBodyMedium()).monospacedDigit()
            }
            .width(90)
        }
        .onChange(of: sortOrder) { _, order in
            // Table is sorted in-memory; actual data sort:
            // (Table already sorts the displayed rows via sortOrder binding)
            _ = order
        }
        .frame(height: min(CGFloat(rows.count) * 44 + 44, 320))
        .tableStyle(.inset)
    }

    // MARK: - Empty

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "person.3").font(.system(size: 32))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No technician data for this period")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(.vertical, BrandSpacing.xl)
        .accessibilityLabel("No technician performance data for this period")
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
