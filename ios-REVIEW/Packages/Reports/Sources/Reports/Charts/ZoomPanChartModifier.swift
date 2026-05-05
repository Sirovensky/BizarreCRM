import SwiftUI
import Charts
import DesignSystem

// MARK: - ZoomPanChartState
//
// Shared observable that tracks the current visible x-window as an index range
// into a data series. Callers bind this to a `@State` and pass it into
// `ZoomPanChartModifier`.

@Observable
public final class ZoomPanChartState: @unchecked Sendable {
    /// Visible index range within the source data series.
    public var visibleRange: ClosedRange<Int>

    /// Total number of data points (read-only after init; updated by modifier).
    public private(set) var totalCount: Int

    public init(totalCount: Int) {
        self.totalCount = totalCount
        self.visibleRange = 0 ... max(0, totalCount - 1)
    }

    /// Zoom in to the centre, halving the visible window (minimum 3 points).
    public func zoomIn() {
        let mid = (visibleRange.lowerBound + visibleRange.upperBound) / 2
        let half = max(1, (visibleRange.upperBound - visibleRange.lowerBound) / 4)
        let lo = max(0, mid - half)
        let hi = min(totalCount - 1, mid + half)
        if hi - lo >= 2 { visibleRange = lo ... hi }
    }

    /// Zoom out, doubling the visible window.
    public func zoomOut() {
        let lo = visibleRange.lowerBound
        let hi = visibleRange.upperBound
        let span = hi - lo
        let newLo = max(0, lo - span / 2)
        let newHi = min(totalCount - 1, hi + span / 2)
        visibleRange = newLo ... newHi
    }

    /// Pan left by 25 % of visible span.
    public func panLeft() {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        let step = max(1, span / 4)
        let newLo = max(0, visibleRange.lowerBound - step)
        let newHi = newLo + span
        if newHi <= totalCount - 1 { visibleRange = newLo ... newHi }
    }

    /// Pan right by 25 % of visible span.
    public func panRight() {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        let step = max(1, span / 4)
        let newHi = min(totalCount - 1, visibleRange.upperBound + step)
        let newLo = newHi - span
        if newLo >= 0 { visibleRange = newLo ... newHi }
    }

    /// Reset to show all data.
    public func resetZoom() {
        visibleRange = 0 ... max(0, totalCount - 1)
    }

    /// Update total and reset when the underlying data series changes length.
    public func sync(to count: Int) {
        guard count != totalCount else { return }
        totalCount = count
        visibleRange = 0 ... max(0, count - 1)
    }

    /// Returns the visible sub-slice of `points`.
    public func visible<T>(from points: [T]) -> [T] {
        guard !points.isEmpty else { return [] }
        let lo = min(visibleRange.lowerBound, points.count - 1)
        let hi = min(visibleRange.upperBound, points.count - 1)
        return Array(points[lo ... hi])
    }
}

// MARK: - ZoomPanControlsView
//
// Compact zoom + pan control bar rendered below a chart card.
// Wire `state` from the parent's `@State var zoomPanState: ZoomPanChartState`.

public struct ZoomPanControlsView: View {
    @Bindable public var state: ZoomPanChartState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: ZoomPanChartState) {
        self.state = state
    }

    private var isAtFullZoom: Bool {
        state.visibleRange.lowerBound == 0 && state.visibleRange.upperBound == state.totalCount - 1
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Pan left
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.quick)) {
                    state.panLeft()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .imageScale(.small)
            }
            .disabled(state.visibleRange.lowerBound == 0)
            .accessibilityLabel("Pan chart left")

            Spacer()

            // Zoom out
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.quick)) {
                    state.zoomOut()
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .imageScale(.small)
            }
            .disabled(isAtFullZoom)
            .accessibilityLabel("Zoom out chart")

            // Reset zoom
            if !isAtFullZoom {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.quick)) {
                        state.resetZoom()
                    }
                } label: {
                    Text("Reset")
                        .font(.brandLabelSmall())
                }
                .accessibilityLabel("Reset chart zoom to full range")
                .transition(.opacity)
            }

            // Zoom in
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.quick)) {
                    state.zoomIn()
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .imageScale(.small)
            }
            .disabled(state.visibleRange.upperBound - state.visibleRange.lowerBound < 3)
            .accessibilityLabel("Zoom in chart")

            Spacer()

            // Pan right
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.quick)) {
                    state.panRight()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
            }
            .disabled(state.visibleRange.upperBound == state.totalCount - 1)
            .accessibilityLabel("Pan chart right")
        }
        .foregroundStyle(.bizarreOnSurfaceMuted)
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - ZoomableRevenueChartCard
//
// Wraps RevenueChartCard with zoom/pan controls and an optional compare-periods overlay.
// §15.9: Swift Charts with zoom / pan / compare periods.

public struct ZoomableRevenueChartCard: View {
    public let currentPoints: [RevenuePoint]
    /// Prior-period points for the compare overlay. Pass [] to disable.
    public let priorPoints: [RevenuePoint]
    public let comparePeriod: ComparePeriod?
    public let overallVariancePct: Double?
    public let onDrillThrough: (RevenuePoint) -> Void

    @State private var zoomState: ZoomPanChartState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        currentPoints: [RevenuePoint],
        priorPoints: [RevenuePoint] = [],
        comparePeriod: ComparePeriod? = nil,
        overallVariancePct: Double? = nil,
        onDrillThrough: @escaping (RevenuePoint) -> Void
    ) {
        self.currentPoints = currentPoints
        self.priorPoints = priorPoints
        self.comparePeriod = comparePeriod
        self.overallVariancePct = overallVariancePct
        self.onDrillThrough = onDrillThrough
        _zoomState = State(wrappedValue: ZoomPanChartState(totalCount: currentPoints.count))
    }

    private var visibleCurrent: [RevenuePoint] { zoomState.visible(from: currentPoints) }
    private var visiblePrior: [RevenuePoint] { zoomState.visible(from: priorPoints) }
    private var showCompare: Bool { !priorPoints.isEmpty && comparePeriod != nil }

    public var body: some View {
        VStack(spacing: 0) {
            if showCompare, let period = comparePeriod {
                CompareOverlay(
                    currentPoints: visibleCurrent,
                    priorPoints: visiblePrior,
                    period: period,
                    overallVariancePct: overallVariancePct,
                    onDrillThrough: onDrillThrough
                )
            } else {
                RevenueChartCard(
                    points: visibleCurrent,
                    periodChangePct: overallVariancePct,
                    onDrillThrough: onDrillThrough
                )
            }
            // Zoom + pan controls below the chart card
            ZoomPanControlsView(state: zoomState)
                .background(Color.bizarreSurface1)
                .cornerRadius(DesignTokens.Radius.xs, corners: [.bottomLeft, .bottomRight])
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .onChange(of: currentPoints.count) { _, newCount in
            zoomState.sync(to: newCount)
        }
    }
}

// MARK: - Corner radius helper (avoids importing UIKit here)

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

private struct RectCorner: OptionSet, Sendable {
    public let rawValue: Int
    public static let topLeft     = RectCorner(rawValue: 1 << 0)
    public static let topRight    = RectCorner(rawValue: 1 << 1)
    public static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    public static let bottomRight = RectCorner(rawValue: 1 << 3)
    public static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

private struct RoundedCornerShape: Shape {
    let radius: CGFloat
    let corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
