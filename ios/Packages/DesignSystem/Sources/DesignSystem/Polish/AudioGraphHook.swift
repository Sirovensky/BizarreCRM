import SwiftUI

// §26.6 / §26.1 — AudioGraphHook
// VoiceOver users can explore charts by sound via the iOS Audio Graph feature
// (introduced iOS 15). Enabling it requires:
//   1. `.accessibilityChartDescriptor(descriptor)` on the chart view.
//   2. A type conforming to `AXChartDescriptorRepresentable` that returns an
//      `AXChartDescriptor` built from the chart's data series.
//
// This file ships:
//   • `BrandAudioGraphSeries`   — a lightweight value type describing one data series.
//   • `BrandAudioGraphDescriptor` — builds an `AXChartDescriptor` from series data.
//   • `.brandAudioGraph(_:)` view modifier — attaches the descriptor to any view.
//
// Callers never interact with UIKit accessibility types directly; they only
// supply `[BrandAudioGraphSeries]` and the modifier wires everything up.

// MARK: - BrandAudioGraphSeries

/// A single data series for an audio-graph descriptor.
///
/// **Usage:**
/// ```swift
/// let series = BrandAudioGraphSeries(
///     label: "Revenue",
///     dataPoints: zip(xLabels, yValues).map { ($0, $1) }
/// )
/// ```
public struct BrandAudioGraphSeries: Sendable {
    /// Human-readable label spoken by VoiceOver (e.g. "Revenue this month").
    public let label: String
    /// Ordered data points: `(xLabel, yValue)`.
    /// `xLabel` is read as the axis label; `yValue` drives the audio pitch.
    public let dataPoints: [(x: String, y: Double)]

    public init(label: String, dataPoints: [(x: String, y: Double)]) {
        self.label = label
        self.dataPoints = dataPoints
    }
}

// MARK: - BrandAudioGraphDescriptor

/// Builds an `AXChartDescriptor` from one or more `BrandAudioGraphSeries`.
///
/// The descriptor is used by VoiceOver's Audio Graph feature so users can
/// "hear" chart data without reading every individual value.
public struct BrandAudioGraphDescriptor: AXChartDescriptorRepresentable {

    public let title: String
    public let series: [BrandAudioGraphSeries]

    public init(title: String, series: [BrandAudioGraphSeries]) {
        self.title = title
        self.series = series
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        // Build a shared numeric Y-axis across all series so relative pitch
        // is consistent when the user switches between them.
        let allY = series.flatMap { $0.dataPoints.map(\.y) }
        let yMin = allY.min() ?? 0
        let yMax = allY.max() ?? 1

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Value",
            range: yMin ... Swift.max(yMax, yMin + 1), // prevent zero-range
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                // Spoken value label — round to 2 decimal places.
                String(format: "%.2f", value)
            }
        )

        let axSeries: [AXDataSeriesDescriptor] = series.map { s in
            let dataPoints = s.dataPoints.map { point in
                AXDataPoint(
                    x: point.x,
                    y: point.y,
                    label: nil
                )
            }
            return AXDataSeriesDescriptor(
                name: s.label,
                isContinuous: true,
                dataPoints: dataPoints
            )
        }

        return AXChartDescriptor(
            title: title,
            summary: nil,
            xAxis: AXCategoricalDataAxisDescriptor(
                title: "Category",
                categoryOrder: series.first?.dataPoints.map(\.x) ?? []
            ),
            yAxis: yAxis,
            additionalAxes: [],
            series: axSeries
        )
    }
}

// MARK: - View extension

public extension View {

    /// Attaches a VoiceOver Audio Graph descriptor to this chart view.
    ///
    /// When VoiceOver is active, users can activate the Audio Graph rotor item
    /// to hear the chart data as a continuous tone that rises and falls with
    /// data values.
    ///
    /// **Usage:**
    /// ```swift
    /// RevenueLineChart(data: viewModel.revenuePoints)
    ///     .brandAudioGraph(
    ///         title: "Revenue — last 30 days",
    ///         series: [
    ///             BrandAudioGraphSeries(
    ///                 label: "Net revenue",
    ///                 dataPoints: viewModel.revenuePoints.map { ($0.dateLabel, $0.amount) }
    ///             )
    ///         ]
    ///     )
    /// ```
    func brandAudioGraph(
        title: String,
        series: [BrandAudioGraphSeries]
    ) -> some View {
        self.accessibilityChartDescriptor(
            BrandAudioGraphDescriptor(title: title, series: series)
        )
    }
}
