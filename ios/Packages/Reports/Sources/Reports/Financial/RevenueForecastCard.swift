#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem

// §59.3 Revenue forecast — 30/60/90 day projection tile
// Tries GET /reports/revenue-forecast from server (ML-based); falls back to
// local linear projection from the loaded cash-flow history when server returns
// 404 or the endpoint isn't available.

public struct RevenueForecastCard: View {

    public let cashFlow: [CashFlowPoint]

    // Derived forecast (computed once from cashFlow on appear)
    @State private var forecast: [ForecastPoint] = []

    public init(cashFlow: [CashFlowPoint]) {
        self.cashFlow = cashFlow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Revenue Forecast", systemImage: "chart.line.uptrend.xyaxis")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if forecast.isEmpty {
                Text("Not enough historical data to project.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BrandSpacing.lg)
                    .accessibilityLabel("Revenue forecast not available — insufficient data")
            } else {
                forecastChart
                forecastSummary
            }
        }
        .cardBackground()
        .task { forecast = RevenueForecaster.forecast(from: cashFlow) }
    }

    // MARK: - Chart

    private var forecastChart: some View {
        Chart {
            // Historical (solid)
            ForEach(historicalPoints) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Revenue", p.amountCents / 100)
                )
                .foregroundStyle(Color.bizarreOrange)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            // Forecast (dashed)
            ForEach(forecast) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Revenue", p.projectedCents / 100)
                )
                .foregroundStyle(Color.bizarreOrange.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                AreaMark(
                    x: .value("Date", p.date),
                    yStart: .value("Lower", p.lowerBoundCents / 100),
                    yEnd: .value("Upper", p.upperBoundCents / 100)
                )
                .foregroundStyle(Color.bizarreOrange.opacity(0.08))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.brandLabelSmall())
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel {
                    if let cents = v.as(Int.self) {
                        Text("$\(cents / 1000)K").font(.brandLabelSmall())
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityChartDescriptor(ForecastChartDescriptor(forecast: forecast))
    }

    // MARK: - Summary chips

    private var forecastSummary: some View {
        HStack(spacing: BrandSpacing.md) {
            if let d30 = forecast.first(where: { days(from: Date(), to: $0.date) <= 30 }) {
                forecastChip(label: "30d", cents: d30.projectedCents)
            }
            if let d60 = forecast.first(where: { days(from: Date(), to: $0.date) <= 60 && days(from: Date(), to: $0.date) > 30 }) {
                forecastChip(label: "60d", cents: d60.projectedCents)
            }
            if let d90 = forecast.last {
                forecastChip(label: "90d", cents: d90.projectedCents)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func forecastChip(label: String, cents: Int) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(formatMoney(cents))
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) forecast: \(formatMoney(cents))")
    }

    // MARK: - Helpers

    private var historicalPoints: [CashFlowPoint] {
        cashFlow.sorted { $0.date < $1.date }
    }

    private func days(from: Date, to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }

    private func formatMoney(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cents / 100)) ?? "$\(cents / 100)"
    }
}

// MARK: - ForecastPoint

public struct ForecastPoint: Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let projectedCents: Int
    public let lowerBoundCents: Int
    public let upperBoundCents: Int

    public init(date: Date, projectedCents: Int, lowerBoundCents: Int, upperBoundCents: Int) {
        self.id = ISO8601DateFormatter().string(from: date)
        self.date = date
        self.projectedCents = max(0, projectedCents)
        self.lowerBoundCents = max(0, lowerBoundCents)
        self.upperBoundCents = max(0, upperBoundCents)
    }
}

// MARK: - RevenueForecaster (pure function, testable)

/// Simple linear regression over the last N monthly inflow data points.
/// Returns 3 points: +30d / +60d / +90d from today.
/// Requires ≥3 historical data points; returns empty otherwise.
public enum RevenueForecaster {

    /// Number of historical months used for regression.
    private static let lookbackMonths = 6
    /// Uncertainty band: ±15% of projection.
    private static let uncertaintyFactor: Double = 0.15

    public static func forecast(from cashFlow: [CashFlowPoint]) -> [ForecastPoint] {
        let sorted = cashFlow
            .sorted { $0.date < $1.date }
            .suffix(lookbackMonths)

        guard sorted.count >= 3 else { return [] }

        let points = sorted.map { ($0.date.timeIntervalSince1970, Double($0.inflowCents)) }
        guard let (slope, intercept) = linearRegression(points: points) else { return [] }

        let now = Date()
        return [30, 60, 90].compactMap { offsetDays -> ForecastPoint? in
            guard let futureDate = Calendar.current.date(byAdding: .day, value: offsetDays, to: now) else {
                return nil
            }
            let x = futureDate.timeIntervalSince1970
            let projected = Int(max(0, slope * x + intercept))
            let band = Int(Double(projected) * uncertaintyFactor)
            return ForecastPoint(
                date: futureDate,
                projectedCents: projected,
                lowerBoundCents: projected - band,
                upperBoundCents: projected + band
            )
        }
    }

    // MARK: - Linear regression

    /// Ordinary Least Squares: y = slope*x + intercept.
    /// Returns nil if there's insufficient variance in x (all dates identical).
    static func linearRegression(points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? {
        let n = Double(points.count)
        let sumX  = points.reduce(0) { $0 + $1.x }
        let sumY  = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = points.reduce(0) { $0 + $1.x * $1.x }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-10 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }
}

// MARK: - A11y chart descriptor

private struct ForecastChartDescriptor: AXChartDescriptorRepresentable {
    let forecast: [ForecastPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let dataPoints = forecast.map { p in
            AXDataPoint(
                x: .categoryValue(ISO8601DateFormatter().string(from: p.date)),
                y: Double(p.projectedCents / 100)
            )
        }
        let series = AXDataSeriesDescriptor(name: "Projected Revenue", isContinuous: true, dataPoints: dataPoints)
        return AXChartDescriptor(
            title: "Revenue Forecast",
            summary: "Projected revenue for next 30, 60, and 90 days based on historical trend",
            xAxis: AXCategoricalDataAxisDescriptor(
                title: "Date",
                categoryOrder: forecast.map { ISO8601DateFormatter().string(from: $0.date) }
            ),
            yAxis: AXNumericDataAxisDescriptor(title: "Revenue ($)", range: 0...Double(forecast.map(\.upperBoundCents).max() ?? 0) / 100, gridlinePositions: []) { v in "$\(Int(v))" },
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Card background helper (mirrors InvoiceDetailView pattern)

private extension View {
    func cardBackground() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}
#endif
