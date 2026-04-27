import SwiftUI
import DesignSystem

// MARK: - BusyHourCell
//
// §15.3 — Busy-hours heatmap.
// Derived from GET /api/v1/reports/tickets with hour_of_day breakdown.
// Server shape: { data: { busy_hours: [{ day_of_week: 0-6, hour: 0-23, ticket_count: N }] } }

public struct BusyHourCell: Codable, Sendable {
    public let dayOfWeek: Int   // 0 = Sunday
    public let hour: Int        // 0–23 (24h)
    public let ticketCount: Int

    enum CodingKeys: String, CodingKey {
        case dayOfWeek   = "day_of_week"
        case hour
        case ticketCount = "ticket_count"
    }

    public init(dayOfWeek: Int, hour: Int, ticketCount: Int) {
        self.dayOfWeek = dayOfWeek
        self.hour = hour
        self.ticketCount = ticketCount
    }
}

// MARK: - BusyHoursHeatmapCard

public struct BusyHoursHeatmapCard: View {
    public let cells: [BusyHourCell]

    public init(cells: [BusyHourCell]) {
        self.cells = cells
    }

    // Build a lookup: [day][hour] -> count
    private var grid: [[Int]] {
        var g = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for cell in cells {
            guard cell.dayOfWeek >= 0, cell.dayOfWeek < 7,
                  cell.hour >= 0, cell.hour < 24 else { continue }
            g[cell.dayOfWeek][cell.hour] += cell.ticketCount
        }
        return g
    }

    private var maxCount: Int {
        cells.map(\.ticketCount).max() ?? 1
    }

    private static let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    // Show every 4 hours to reduce clutter
    private static let hourLabels: [String] = (0..<24).filter { $0 % 4 == 0 }.map {
        $0 == 0 ? "12am" : $0 < 12 ? "\($0)am" : $0 == 12 ? "12pm" : "\($0 - 12)pm"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if cells.isEmpty {
                emptyState
            } else {
                heatmapContent
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Busy Hours Heatmap")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Heatmap

    private var heatmapContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Hour labels (top)
            hourLabelRow
            // Day rows
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: 2) {
                    Text(Self.dayLabels[day])
                        .font(.brandMono(size: 10))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 28, alignment: .trailing)
                    ForEach(0..<24, id: \.self) { hour in
                        let count = grid[day][hour]
                        let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(intensity: intensity))
                            .frame(height: 14)
                            .accessibilityLabel(
                                "\(Self.dayLabels[day]) \(hourString(hour)): \(count) tickets"
                            )
                    }
                }
            }
            // Color scale legend
            colorScaleLegend
        }
        .accessibilityElement(children: .contain)
    }

    private var hourLabelRow: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 28)
            ForEach(0..<24, id: \.self) { hour in
                if hour % 4 == 0 {
                    Text(hourString(hour))
                        .font(.brandMono(size: 8))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
            }
        }
    }

    private var colorScaleLegend: some View {
        HStack(spacing: BrandSpacing.xs) {
            Text("Low")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            LinearGradient(
                colors: [Color.bizarreOrange.opacity(0.1), Color.bizarreOrange],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 8)
            .cornerRadius(4)
            Text("High")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private func cellColor(intensity: Double) -> Color {
        Color.bizarreOrange.opacity(0.1 + intensity * 0.9)
    }

    private func hourString(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Hour Data",
            systemImage: "calendar.badge.clock",
            description: Text("No hourly breakdown data for this period.")
        )
    }
}
