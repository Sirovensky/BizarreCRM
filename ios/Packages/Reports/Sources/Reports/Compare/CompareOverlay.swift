import SwiftUI
import Charts
import DesignSystem

// MARK: - CompareOverlay
//
// Renders a dashed prior-period LineMark on top of an existing Swift Charts
// chart.  Drop this into any `Chart { }` body alongside the primary series
// marks — it adds the prior-period line without requiring changes to the
// host chart's state or networking layer.
//
// The overlay intentionally owns NO data fetching.  Callers are responsible
// for supplying `priorPoints` — the ViewModel fetches the prior window using
// the same ReportsRepository methods already in place (getSalesReport with
// shifted date strings derived from ComparePeriod.priorDateStrings).
//
// Usage inside a Chart body:
//
//   Chart {
//       // ... primary LineMark / AreaMark marks ...
//       CompareOverlayMarks(points: priorPoints, seriesLabel: "Prev Month")
//   }
//
// For embedding as a standalone view that wraps an existing chart, use
// `CompareOverlay`.

// MARK: - CompareOverlayMarks (mark-level — use inside Chart { })

/// Injects a dashed prior-period `LineMark` + optional `PointMark` into the
/// surrounding `Chart`.  Intended for inline composition inside a `Chart` body.
public struct CompareOverlayMarks: ChartContent {
    /// Prior-period data points. Each item must supply `date` (x) and `amountDollars` (y).
    public let points: [RevenuePoint]
    /// Accessibility / legend label, e.g. "Prev Month".
    public let seriesLabel: String

    public init(points: [RevenuePoint], seriesLabel: String = "Prior Period") {
        self.points = points
        self.seriesLabel = seriesLabel
    }

    public var body: some ChartContent {
        ForEach(points) { pt in
            LineMark(
                x: .value("Date", pt.date),
                y: .value(seriesLabel, pt.amountDollars / 1000.0)
            )
            .foregroundStyle(Color.bizarreTeal.opacity(0.75))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .interpolationMethod(.catmullRom)
            .accessibilityLabel("\(seriesLabel): \(pt.date), \(String(format: "$%.2fK", pt.amountDollars / 1000))")
        }
    }
}

// MARK: - CompareOverlay (standalone view — wraps a primary chart)

/// A standalone card view that layers a dashed prior-period line over a
/// current-period area+line chart.
///
/// - `currentPoints`  — primary series (solid orange line + area fill).
/// - `priorPoints`    — prior-period series (dashed teal line).
/// - `period`         — used to derive the pill label (WoW / MoM / YoY / Custom).
/// - `onDrillThrough` — called when the user taps a current-period data point.
///
/// The card uses `Color.bizarreSurface1` background + `DesignTokens.Radius.lg`
/// rounding, matching all other chart cards in the Reports package.
public struct CompareOverlay: View {

    public let currentPoints: [RevenuePoint]
    public let priorPoints: [RevenuePoint]
    public let period: ComparePeriod
    /// Overall % change across the entire window. Pass `nil` when unavailable.
    public let overallVariancePct: Double?
    public let onDrillThrough: (RevenuePoint) -> Void

    public init(
        currentPoints: [RevenuePoint],
        priorPoints: [RevenuePoint],
        period: ComparePeriod,
        overallVariancePct: Double? = nil,
        onDrillThrough: @escaping (RevenuePoint) -> Void
    ) {
        self.currentPoints = currentPoints
        self.priorPoints = priorPoints
        self.period = period
        self.overallVariancePct = overallVariancePct
        self.onDrillThrough = onDrillThrough
    }

    @State private var selectedPoint: RevenuePoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            headerRow
            chartBody
                .frame(height: 200)
                .chartXAxisLabel("Date", alignment: .center)
                .chartYAxisLabel("Revenue ($K)", position: .leading)
                .chartOverlay { proxy in drillOverlay(proxy: proxy) }
            legendRow
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

    private var headerRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Revenue Comparison")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            CompareDeltaPill(
                pct: overallVariancePct,
                periodLabel: period.displayLabel
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Revenue comparison chart, \(period.displayLabel)")
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartBody: some View {
        if currentPoints.isEmpty && priorPoints.isEmpty {
            ContentUnavailableView(
                "No Comparison Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("No data available for the selected periods.")
            )
        } else {
            Chart {
                // Primary period — area + solid line
                ForEach(currentPoints) { pt in
                    AreaMark(
                        x: .value("Date", pt.date),
                        y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.bizarreOrange.opacity(0.30),
                                     Color.bizarreOrange.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                    )
                    .foregroundStyle(Color.bizarreOrange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    if selectedPoint?.id == pt.id {
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("Revenue ($K)", pt.amountDollars / 1000.0)
                        )
                        .foregroundStyle(Color.bizarreOrange)
                        .symbolSize(80)
                    }
                }

                // Prior period — dashed teal line (no area fill to avoid visual noise)
                CompareOverlayMarks(
                    points: priorPoints,
                    seriesLabel: period.displayLabel
                )
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.smooth),
                value: currentPoints.count
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.smooth),
                value: priorPoints.count
            )
        }
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: BrandSpacing.md) {
            legendItem(color: .bizarreOrange,
                       dashed: false,
                       label: "Current Period")
            legendItem(color: .bizarreTeal,
                       dashed: true,
                       label: period.displayLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: orange solid = current period, teal dashed = \(period.displayLabel)")
    }

    private func legendItem(color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            if dashed {
                // Render a short dashed line swatch
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    ctx.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                    )
                }
                .frame(width: 20, height: 10)
                .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 20, height: 3)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Drill-through gesture

    @ViewBuilder
    private func drillOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x - geo.frame(in: .local).minX
                            guard let date: String = proxy.value(atX: x) else { return }
                            selectedPoint = currentPoints.first {
                                $0.date.hasPrefix(date.prefix(10))
                            }
                        }
                        .onEnded { _ in
                            if let pt = selectedPoint { onDrillThrough(pt) }
                            selectedPoint = nil
                        }
                )
        }
    }
}
