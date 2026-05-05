import SwiftUI
import DesignSystem

// MARK: - TechDetailSheet

/// §15.4 — Per-technician drill-through sheet.
public struct TechDetailSheet: View {
    public let row: TechnicianPerfRow

    public init(row: TechnicianPerfRow) {
        self.row = row
    }

    private let currencyFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }()

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    stat("Tickets Assigned", value: "\(row.ticketsAssigned)")
                    stat("Tickets Closed",   value: "\(row.ticketsClosed)")
                    stat("Close Rate",       value: String(format: "%.1f%%", row.closeRate))
                }
                Section {
                    stat("Hours Worked",     value: String(format: "%.1f h", row.hoursWorked))
                    stat("Commission",       value: currencyFmt.string(from: row.commissionDollars as NSNumber) ?? "—")
                    stat("Revenue Generated", value: currencyFmt.string(from: row.revenueGenerated as NSNumber) ?? "—")
                }
            }
            .navigationTitle(row.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
    }
}
