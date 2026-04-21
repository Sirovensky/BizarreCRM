import SwiftUI
import DesignSystem

// MARK: - InventoryTurnoverCard

/// Sorted table — top 10 slowest movers (highest daysOnHand).
public struct InventoryTurnoverCard: View {
    public let rows: [InventoryTurnoverRow]
    public let maxRows: Int

    public init(rows: [InventoryTurnoverRow], maxRows: Int = 10) {
        self.rows = rows
        self.maxRows = maxRows
    }

    private var slowestMovers: [InventoryTurnoverRow] {
        Array(rows.sorted { $0.daysOnHand > $1.daysOnHand }.prefix(maxRows))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if slowestMovers.isEmpty {
                ContentUnavailableView("No Inventory Data",
                                       systemImage: "shippingbox",
                                       description: Text("No inventory turnover data for this period."))
            } else {
                tableHeader
                ForEach(slowestMovers) { row in
                    tableRow(row)
                    Divider()
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var cardHeader: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Inventory Turnover")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text("Slowest 10")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var tableHeader: some View {
        HStack {
            Text("SKU / Name")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Rate")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 48, alignment: .trailing)
            Text("Days")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    private func tableRow(_ row: InventoryTurnoverRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(row.sku)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(row.name)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f", row.turnoverRate))
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(width: 48, alignment: .trailing)

            Text(String(format: "%.0f", row.daysOnHand))
                .font(.brandLabelLarge())
                .foregroundStyle(row.daysOnHand > 60 ? Color.bizarreError : Color.bizarreOnSurface)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(row.name), SKU \(row.sku). Turnover rate \(String(format: "%.1f", row.turnoverRate)). Days on hand \(String(format: "%.0f", row.daysOnHand))."
        )
    }
}
