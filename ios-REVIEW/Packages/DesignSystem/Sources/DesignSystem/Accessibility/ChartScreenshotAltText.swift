import SwiftUI

// MARK: - ChartScreenshotAltText
// §91.13 — Alt-text for chart screenshots / rendered chart images.
//
// When a chart view is captured as a UIImage (e.g. for PDF export or share
// sheets) VoiceOver reads nothing because the image has no accessibility label.
// This modifier writes a structured alt-text string onto the view so that:
//   1. VoiceOver reads a meaningful summary when the chart is focused.
//   2. When the view is snapshotted via `ImageRenderer`, the rendered CGImage
//      carries the alt-text string as the `accessibilityLabel` on the
//      resulting `Image(uiImage:)` wrapper (host app must forward the label).
//
// **Usage:**
// ```swift
// RevenueChartCard(points: vm.revenue, …)
//     .chartScreenshotAltText("Revenue chart. 30-day trend, peak $4,210 on Mar 15.")
// ```
//
// The label should be a complete sentence describing: chart type, time range,
// key insight (peak / trough / trend direction).  Keep it under 200 characters
// so VoiceOver reads it in a single breath.

// MARK: - Modifier

public struct ChartScreenshotAltTextModifier: ViewModifier {
    /// Human-readable description of the chart for VoiceOver + image export.
    public let altText: String

    public init(_ altText: String) {
        self.altText = altText
    }

    public func body(content: Content) -> some View {
        content
            // Primary VoiceOver label — overrides any child labels on the
            // snapshot container so screenreaders get the summary, not noise.
            .accessibilityLabel(altText)
            // Mark the chart container as an image so assistive technologies
            // treat it like a static picture rather than an interactive group.
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - View extension

public extension View {
    /// Attaches alt-text to a chart view for VoiceOver and image-export contexts.
    ///
    /// - Parameter altText: A short descriptive sentence (≤ 200 characters) that
    ///   captures the chart type, time range, and key data insight.
    func chartScreenshotAltText(_ altText: String) -> some View {
        modifier(ChartScreenshotAltTextModifier(altText))
    }
}
