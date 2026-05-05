import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - DashboardWideLayout
//
// §22 iPad polish — 3-column wide layout orchestrator.
//
// Column layout (regular-width only):
//   [Primary KPIs]  |  [Trends Chart]  |  [Attention Card]
//
// All three columns are peers in an HStack with fixed flex ratios:
//   left   2.0  — KPI tile grid (most information density)
//   center 3.0  — trends chart strip (visual weight, primary narrative)
//   right  1.5  — attention card (actionable, secondary weight)
//
// Liquid Glass: NOT applied to content columns (per ios/CLAUDE.md). Glass
// is reserved for navigation chrome.
//
// This view is gated at the call site via `Platform.isCompact`:
// when compact, DashboardView renders its phone layout instead.

/// 3-column iPad wide layout for the Dashboard loaded state.
///
/// Expects a `DashboardSnapshot` already available (i.e. called only from
/// the `.loaded` branch of `DashboardView`). All layout logic lives here
/// so that `DashboardView` stays thin.
public struct DashboardWideLayout: View {
    public let snapshot: DashboardSnapshot

    public init(snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.lg) {
            // Column 1 — KPI tile grid (adaptive 3/4/6 columns based on width)
            DashboardKpiTileGrid(summary: snapshot.summary)
                .frame(maxWidth: .infinity)
                .layoutPriority(2)

            Divider()
                .frame(maxHeight: .infinity)
                .overlay(Color.bizarreOutline.opacity(0.25))

            // Column 2 — Trends chart strip
            DashboardTrendsChartStrip(summary: snapshot.summary)
                .frame(maxWidth: .infinity)
                .layoutPriority(3)

            Divider()
                .frame(maxHeight: .infinity)
                .overlay(Color.bizarreOutline.opacity(0.25))

            // Column 3 — Attention card
            wideAttentionColumn
                .frame(maxWidth: .infinity)
                .layoutPriority(1.5)
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.md)
    }

    // MARK: - Private

    @ViewBuilder
    private var wideAttentionColumn: some View {
        let items = attentionItemsForWide(from: snapshot.attention)
        let total = items.reduce(0) { $0 + $1.count }

        if total > 0 {
            WideAttentionPanel(items: items)
        } else {
            WideAttentionEmptyPanel()
        }
    }
}

// MARK: - Wide attention panel

private struct WideAttentionPanel: View {
    let items: [WideAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Needs attention")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(.bottom, BrandSpacing.xs)

            // Rows
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    WideAttentionRow(item: item)
                    if idx < items.count - 1 {
                        Divider()
                            .overlay(Color.bizarreOutline.opacity(0.2))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }
}

private struct WideAttentionEmptyPanel: View {
    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("All clear")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Text("No items need attention")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Needs attention: no items")
    }
}

// MARK: - Wide attention item model (internal for testability)

/// View-model for a single row in the wide attention panel.
/// `internal` (not private) so tests can call `attentionItemsForWide(from:)`.
struct WideAttentionItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let icon: String
    /// When true the badge renders in `.bizarreError` (red) instead of
    /// `.bizarreWarning` (amber). Set for low-stock: out-of-parts blocks repairs.
    var accentIsError: Bool = false
}

// MARK: - Attention row

private struct WideAttentionRow: View {
    let item: WideAttentionItem

    /// Badge color: error (red) for low-stock, warning (amber) for everything else.
    private var badgeColor: Color {
        guard item.count > 0 else { return .bizarreOnSurfaceMuted }
        return item.accentIsError ? .bizarreError : .bizarreWarning
    }

    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(item.label)
                .font(.brandBodyMedium())
                .foregroundStyle(item.count > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                .lineLimit(1)
            Spacer(minLength: BrandSpacing.xs)
            Text("\(item.count)")
                .font(.brandTitleSmall())
                .foregroundStyle(badgeColor)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .brandHover()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue("\(item.count)")
    }
}

// MARK: - Helper (internal for testability)

/// Maps `NeedsAttention` to the icon-annotated rows used by `WideAttentionPanel`.
/// `internal` so iPad layout tests can reach it via `@testable import Dashboard`.
func attentionItemsForWide(from attention: NeedsAttention) -> [WideAttentionItem] {
    [
        .init(label: "Stale tickets",    count: attention.staleTickets.count,    icon: "clock.badge.exclamationmark"),
        .init(label: "Overdue invoices", count: attention.overdueInvoices.count, icon: "doc.badge.exclamationmark"),
        .init(label: "Missing parts",    count: attention.missingPartsCount,     icon: "shippingbox.badge.clock"),
        // §3.1 — low-stock badge is error-red (not warning-amber): parts shortage blocks repairs.
        .init(label: "Low stock",        count: attention.lowStockCount,         icon: "exclamationmark.triangle", accentIsError: true),
    ]
}
