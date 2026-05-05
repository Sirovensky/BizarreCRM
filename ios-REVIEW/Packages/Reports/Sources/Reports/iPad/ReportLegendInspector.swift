import SwiftUI
import DesignSystem

// MARK: - ReportLegendInspector

/// iPad-only trailing inspector showing a breakdown legend for the active report category.
///
/// Mounted in the NavigationSplitView detail column when the user toggles
/// "Show Legend" via toolbar button or ⌘L context menu.
///
/// Liquid Glass only on the inspector header chrome — never on data rows.
public struct ReportLegendInspector: View {

    // MARK: - Dependencies

    public let category: ReportCategory
    public let vm: ReportsViewModel

    public init(category: ReportCategory, vm: ReportsViewModel) {
        self.category = category
        self.vm = vm
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                inspectorHeader
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        legendRows
                    }
                    .padding(BrandSpacing.base)
                }
            }
        }
        .navigationTitle("Legend")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header (Liquid Glass on chrome only)

    private var inspectorHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: category.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(category.accentColor)
                .accessibilityHidden(true)
            Text(category.displayName)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.regular, in: Rectangle())
    }

    // MARK: - Legend rows (dispatched per category)

    @ViewBuilder
    private var legendRows: some View {
        switch category {
        case .revenue:
            revenueLegendRows
        case .expenses:
            expensesLegendRows
        case .inventory:
            inventoryLegendRows
        case .ownerPL:
            ownerPLLegendRows
        }
    }

    // MARK: - Revenue legend

    @ViewBuilder
    private var revenueLegendRows: some View {
        legendSectionHeader("Payment Methods")
        if vm.revenueByMethod.isEmpty {
            legendEmptyNote("No payment breakdown available")
        } else {
            ForEach(vm.revenueByMethod) { method in
                LegendRow(
                    label: method.method.capitalized,
                    value: String(format: "$%.2f", method.revenue),
                    count: "\(method.count) transactions",
                    accentColor: .bizarreSuccess
                )
            }
        }

        legendSectionHeader("Period Summary")
        LegendRow(
            label: "Total Revenue",
            value: String(format: "$%.2f", vm.revenueTotalDollars),
            count: nil,
            accentColor: category.accentColor
        )
        if let atv = vm.avgTicketValue {
            LegendRow(
                label: "Avg Ticket Value",
                value: String(format: "$%.2f", atv.currentDollars),
                count: String(format: "%.1f%% trend", atv.trendPct),
                accentColor: atv.trendPct >= 0 ? .bizarreSuccess : .bizarreError
            )
        }
    }

    // MARK: - Expenses legend

    @ViewBuilder
    private var expensesLegendRows: some View {
        legendSectionHeader("Expenses Overview")
        if let exp = vm.expensesReport {
            LegendRow(
                label: "Total Expenses",
                value: String(format: "$%.2f", exp.totalDollars),
                count: nil,
                accentColor: .bizarreError
            )
            LegendRow(
                label: "Revenue",
                value: String(format: "$%.2f", exp.revenueDollars),
                count: nil,
                accentColor: .bizarreSuccess
            )
            LegendRow(
                label: "Gross Profit",
                value: String(format: "$%.2f", exp.grossProfitDollars),
                count: exp.marginPct.map { String(format: "%.1f%% margin", $0) },
                accentColor: exp.grossProfitDollars >= 0 ? .bizarreSuccess : .bizarreError
            )
        } else {
            legendEmptyNote("Expenses data not loaded")
        }
    }

    // MARK: - Inventory legend

    @ViewBuilder
    private var inventoryLegendRows: some View {
        if let inv = vm.inventoryReport {
            legendSectionHeader("Stock Health")
            LegendRow(
                label: "Out of Stock",
                value: "\(inv.outOfStockCount) SKUs",
                count: nil,
                accentColor: .bizarreError
            )
            LegendRow(
                label: "Low Stock",
                value: "\(inv.lowStockCount) SKUs",
                count: nil,
                accentColor: .bizarreWarning
            )

            if !inv.valueSummary.isEmpty {
                legendSectionHeader("Inventory Value")
                ForEach(inv.valueSummary) { entry in
                    LegendRow(
                        label: entry.itemType.capitalized,
                        value: String(format: "$%.2f retail", entry.totalRetailValue),
                        count: "\(entry.totalUnits) units",
                        accentColor: .bizarreTeal
                    )
                }
            }
        } else {
            legendEmptyNote("Inventory data not loaded")
        }

        if !vm.inventoryTurnover.isEmpty {
            legendSectionHeader("Turnover Rates")
            ForEach(vm.inventoryTurnover.prefix(8)) { row in
                LegendRow(
                    label: row.name,
                    value: String(format: "%.1f turns/90d", row.turnoverRate),
                    count: String(format: "%.0f days on hand", row.daysOnHand),
                    accentColor: turnoverColor(row)
                )
            }
        }
    }

    // MARK: - Owner P&L legend

    @ViewBuilder
    private var ownerPLLegendRows: some View {
        legendSectionHeader("Top Performers")
        if vm.employeePerf.isEmpty {
            legendEmptyNote("Employee data not loaded")
        } else {
            ForEach(vm.employeePerf.prefix(10)) { emp in
                LegendRow(
                    label: emp.employeeName,
                    value: String(format: "$%.0f", emp.revenueDollars),
                    count: "\(emp.ticketsClosed) tickets closed",
                    accentColor: .bizarreOrange
                )
            }
        }
    }

    // MARK: - Helpers

    private func legendSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .textCase(.uppercase)
            .padding(.top, BrandSpacing.md)
            .padding(.bottom, BrandSpacing.xs)
    }

    private func legendEmptyNote(_ message: String) -> some View {
        Text(message)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.vertical, BrandSpacing.sm)
    }

    private func turnoverColor(_ row: InventoryTurnoverRow) -> Color {
        switch row.status {
        case "healthy":   return .bizarreSuccess
        case "slow":      return .bizarreWarning
        case "stagnant":  return .bizarreError
        default:
            return row.turnoverRate >= 2.0 ? .bizarreSuccess : .bizarreWarning
        }
    }
}

// MARK: - LegendRow

/// A single row in the legend inspector. No glass — data surface.
private struct LegendRow: View {
    let label: String
    let value: String
    let count: String?
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(accentColor)
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(label)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let count {
                    Text(count)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(count.map { ", \($0)" } ?? "")")
    }
}
