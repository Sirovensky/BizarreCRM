import SwiftUI

// MARK: - §26.6 Differentiate Without Color — chart dashed / dotted patterns
//
// When the user has enabled "Differentiate Without Color" at the OS level,
// chart series should also vary in **stroke pattern** so they remain
// distinguishable in monochrome / color-blind preview / printed contexts.
// Default = solid stroke; we only apply the patterned dash array when the
// flag is set.
//
// Usage with Swift Charts:
// ```swift
// @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
//
// Chart {
//     ForEach(series.indices, id: \.self) { i in
//         LineMark(x: .value("Day", series[i].day),
//                  y: .value("Sales", series[i].sales))
//             .foregroundStyle(by: .value("Series", series[i].name))
//             .lineStyle(ChartDifferentiateStrokeStyle.style(forIndex: i,
//                                                          differentiate: differentiate))
//     }
// }
// ```

public enum ChartDifferentiateStrokeStyle: Sendable {

    /// Six rotated dash patterns. Index `% 6` so any series count works.
    /// Each pattern keeps a 2-pt line width for visual parity with the solid
    /// default. Patterns chosen for high distinguishability at chart scale:
    ///   0: solid
    ///   1: long-dash
    ///   2: short-dash
    ///   3: dotted
    ///   4: dash-dot
    ///   5: long-dash gap
    private static let patterns: [[CGFloat]] = [
        [],                 // solid
        [10, 4],            // long-dash
        [4, 3],             // short-dash
        [1, 3],             // dotted
        [6, 3, 1, 3],       // dash-dot
        [12, 6],            // long-dash gap
    ]

    /// Returns a `StrokeStyle` for series `index`. When `differentiate` is
    /// `false`, returns a plain solid 2-pt stroke (default chart look).
    /// When `true`, returns a 2-pt stroke with the patterned dash array
    /// keyed off `index % 6`, with `lineCap: .round` so dotted patterns
    /// look like dots rather than micro-rectangles.
    public static func style(forIndex index: Int, differentiate: Bool) -> StrokeStyle {
        guard differentiate else {
            return StrokeStyle(lineWidth: 2)
        }
        let dash = patterns[abs(index) % patterns.count]
        return StrokeStyle(
            lineWidth: 2,
            lineCap: .round,
            lineJoin: .round,
            dash: dash
        )
    }
}

extension View {
    /// Reads `accessibilityDifferentiateWithoutColor` from the environment and
    /// passes it into a builder closure that returns the styled view. Use this
    /// when the chart-style branch is so trivial you'd rather not declare an
    /// `@Environment` property on the host view.
    ///
    /// ```swift
    /// .a11yChartStroke { differentiate in
    ///     ChartDifferentiateStrokeStyle.style(forIndex: i, differentiate: differentiate)
    /// }
    /// ```
    @ViewBuilder
    public func a11yChartStrokeContext<T>(
        _ resolve: @escaping (Bool) -> T,
        apply: @escaping (T) -> AnyView
    ) -> some View {
        ChartDifferentiateContext(resolve: resolve, apply: apply, content: self)
    }
}

private struct ChartDifferentiateContext<T, Content: View>: View {
    let resolve: (Bool) -> T
    let apply: (T) -> AnyView
    let content: Content

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        apply(resolve(differentiate))
    }
}
