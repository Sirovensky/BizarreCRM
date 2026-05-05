import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - DashboardKpiTileGrid
//
// §22 iPad polish — adaptive KPI tile grid.
//
// Column count is driven by the rendered container width:
//   width < 480 pt  → 3 columns  (iPad split-view, narrow sidebar)
//   480..639 pt     → 4 columns  (iPad split-view, half-width)
//   640+ pt         → 6 columns  (full-screen iPad, landscape)
//
// Width is read via `GeometryReader` so the grid self-configures without
// any trait-collection plumbing at the call site. That also makes it safe
// inside iPad multi-column layouts where the column can be narrower than
// the screen.
//
// Each tile uses `DashboardHoverHighlight` for interactive feedback on iPad
// pointer / keyboard focus, and exposes `.textSelection(.enabled)` on the
// numeric value so iPadOS power users can copy KPI numbers.
//
// Immutability: this struct is value-typed; grid column arrays are derived
// fresh from `containerWidth` — no stored mutable state.

/// Adaptive 3/4/6-column KPI tile grid driven by container width.
public struct DashboardKpiTileGrid: View {
    public let summary: DashboardSummary

    public init(summary: DashboardSummary) {
        self.summary = summary
    }

    public var body: some View {
        GeometryReader { geo in
            let cols = kpiColumnCount(for: geo.size.width)
            let items = kpiItems(from: summary)
            let gridCols = Array(
                repeating: GridItem(.flexible(), spacing: BrandSpacing.sm),
                count: cols
            )

            ScrollView {
                LazyVGrid(columns: gridCols, spacing: BrandSpacing.sm) {
                    ForEach(items) { tile in
                        KpiTile(tile: tile)
                    }
                }
                .padding(.horizontal, BrandSpacing.xs)
                .padding(.bottom, BrandSpacing.sm)
            }
            .scrollDisabled(true)
        }
    }
}

// MARK: - Tile view

private struct KpiTile: View {
    let tile: KpiTileItem

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Image(systemName: tile.icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Text(tile.value)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // §22 — power users can copy numeric values
                .textSelection(.enabled)

            Text(tile.label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        // §22 hover highlight for iPad pointer
        .brandHover()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(tile.value)
    }
}

// MARK: - Item model

/// View-model for a single KPI tile.
public struct KpiTileItem: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let value: String
    public let icon: String

    public init(label: String, value: String, icon: String) {
        self.label = label
        self.value = value
        self.icon = icon
    }
}

// MARK: - Layout helpers (internal for testability)

/// Returns the KPI grid column count for the given container width.
///
/// Thresholds selected for iPad split-view widths (pts):
/// - < 480  — narrow column in a 3-column split → 3 tiles across
/// - 480–639 — half-width iPad or portrait narrow pane → 4 tiles
/// - ≥ 640  — full-width or landscape → 6 tiles
///
/// This function is `internal` so `DashboardKpiTileGridTests` can call
/// it directly via `@testable import Dashboard`.
func kpiColumnCount(for containerWidth: CGFloat) -> Int {
    switch containerWidth {
    case ..<480:   return 3
    case 480..<640: return 4
    default:        return 6
    }
}

/// Assembles the ordered list of `KpiTileItem` values from a `DashboardSummary`.
/// Extracted from the view so tests can validate labels, values, and ordering
/// without running any SwiftUI rendering.
func kpiItems(from summary: DashboardSummary) -> [KpiTileItem] {
    let money = kpiMoneyFormatter()
    return [
        KpiTileItem(label: "Open tickets",    value: "\(summary.openTickets)",             icon: "wrench.and.screwdriver"),
        KpiTileItem(label: "Revenue today",   value: money.string(from: NSNumber(value: summary.revenueToday)) ?? "$0", icon: "dollarsign.circle"),
        KpiTileItem(label: "Closed today",    value: "\(summary.closedToday)",             icon: "checkmark.seal"),
        KpiTileItem(label: "New today",       value: "\(summary.ticketsCreatedToday)",     icon: "plus.circle"),
        KpiTileItem(label: "Appointments",    value: "\(summary.appointmentsToday)",       icon: "calendar"),
        KpiTileItem(label: "Inventory value", value: money.string(from: NSNumber(value: summary.inventoryValue)) ?? "$0", icon: "shippingbox"),
    ]
}

/// Returns a reusable currency formatter (USD, no cents).
/// Isolated here so both `kpiItems(from:)` and tests use the same instance.
func kpiMoneyFormatter() -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f
}
