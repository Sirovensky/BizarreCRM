import SwiftUI
import Charts

// MARK: - Brand chart axis style helpers (§91.10 Typography / §91.11 Charts)
//
// Swift Charts applies system-default font sizes to axis tick labels unless
// explicitly overridden via `.chartXAxis` / `.chartYAxis` with `AxisMarks`.
// This file provides a single `.brandChartAxisStyle()` modifier that sets
// `brandChartAxisLabel()` (12 pt Roboto Regular) on every value label in
// both axes, keeping all report charts visually consistent.
//
// §91.11 contrast fix: Y-axis labels previously rendered at ~30% opacity
// (white-30%) which failed legibility. This modifier forces full
// `bizarreOnSurface` foreground (not muted variant) for value labels so
// the text reads clearly on the dark surface.  Grid lines remain muted.

public extension View {
    /// Apply brand-standard 12 pt Roboto axis labels with full-contrast
    /// foreground to all Swift Charts within this view.
    /// Drop-in replacement: add after any `.chartXAxisLabel` or
    /// `.chartYAxisLabel` modifier.
    @ViewBuilder
    func brandChartAxisStyle() -> some View {
        self
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                        .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                    AxisTick()
                        .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                    AxisValueLabel()
                        .font(.brandChartAxisLabel())
                        // §91.11: full-opacity label color — not muted — for
                        // legibility on dark chart surfaces.
                        .foregroundStyle(Color.bizarreOnSurface)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                        .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                    AxisTick()
                        .foregroundStyle(Color.bizarreOutline.opacity(0.3))
                    AxisValueLabel()
                        .font(.brandChartAxisLabel())
                        // §91.11: full-opacity label color — not muted — for
                        // legibility on dark chart surfaces.
                        .foregroundStyle(Color.bizarreOnSurface)
                }
            }
    }
}
