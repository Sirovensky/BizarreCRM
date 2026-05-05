import SwiftUI
import Charts

// MARK: - Brand chart axis style helpers (§91.10 Typography — axis label sizing)
//
// Swift Charts applies system-default font sizes to axis tick labels unless
// explicitly overridden via `.chartXAxis` / `.chartYAxis` with `AxisMarks`.
// This file provides a single `.brandChartAxisStyle()` modifier that sets
// `brandChartAxisLabel()` (11 pt Roboto Regular) on every value label in
// both axes, keeping all report charts visually consistent.

public extension View {
    /// Apply brand-standard 11 pt Roboto axis labels to all Swift Charts
    /// within this view.  Drop-in replacement: add after any `.chartXAxisLabel`
    /// or `.chartYAxisLabel` modifier.
    @ViewBuilder
    func brandChartAxisStyle() -> some View {
        self
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                        .font(.brandChartAxisLabel())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                        .font(.brandChartAxisLabel())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }
    }
}
