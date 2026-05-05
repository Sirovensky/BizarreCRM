import SwiftUI
import Core
import DesignSystem
import Networking

// §8 — Side-by-side diff of two estimate versions.
//
// iPhone: vertical scroll with "v-n" section above "v-n+1" section;
//         diff chips highlight adds, removes, price changes.
// iPad:   two-column HStack (left = older, right = newer) with change
//         markers in a centre connector strip.
//
// Rules:
// - Added line items: green "+" badge
// - Removed line items: red "−" badge (strikethrough)
// - Price-changed items: amber "Δ" badge showing old → new
// - Unchanged items: no badge
//
// Usage: sheet from EstimateVersionsView when tapping "Compare" on a version row.

// MARK: - Diff model

public struct EstimateVersionDiff: Sendable {
    public enum LineChange: Sendable {
        case unchanged(item: EstimateLineItem)
        case added(item: EstimateLineItem)
        case removed(item: EstimateLineItem)
        case priceChanged(item: EstimateLineItem, oldPrice: Double, newPrice: Double)
    }

    public let olderVersion: Int
    public let newerVersion: Int
    public let changes: [LineChange]
    public let oldTotal: Double
    public let newTotal: Double
    public let totalChanged: Bool

    // MARK: - Builder

    /// Diffs `older` and `newer` estimate line items by description match.
    public static func compute(older: Estimate, newer: Estimate) -> EstimateVersionDiff {
        let oldItems = older.lineItems ?? []
        let newItems = newer.lineItems ?? []

        var changes: [LineChange] = []

        // Build a name→item map for quick lookup
        var oldMap: [String: EstimateLineItem] = [:]
        for item in oldItems {
            let key = itemKey(item)
            oldMap[key] = item
        }
        var newMap: [String: EstimateLineItem] = [:]
        for item in newItems {
            let key = itemKey(item)
            newMap[key] = item
        }

        // Pass 1: items in older version
        for item in oldItems {
            let key = itemKey(item)
            if let newItem = newMap[key] {
                let oldP = item.unitPrice ?? item.total ?? 0
                let newP = newItem.unitPrice ?? newItem.total ?? 0
                if abs(oldP - newP) < 0.001 {
                    changes.append(.unchanged(item: item))
                } else {
                    changes.append(.priceChanged(item: newItem, oldPrice: oldP, newPrice: newP))
                }
            } else {
                changes.append(.removed(item: item))
            }
        }

        // Pass 2: items only in newer version (added)
        for item in newItems {
            let key = itemKey(item)
            if oldMap[key] == nil {
                changes.append(.added(item: item))
            }
        }

        let oldTotal = older.total ?? oldItems.reduce(0) { $0 + ($1.total ?? 0) }
        let newTotal = newer.total ?? newItems.reduce(0) { $0 + ($1.total ?? 0) }

        return EstimateVersionDiff(
            olderVersion: older.versionNumber ?? 0,
            newerVersion: newer.versionNumber ?? 0,
            changes: changes,
            oldTotal: oldTotal,
            newTotal: newTotal,
            totalChanged: abs(oldTotal - newTotal) > 0.001
        )
    }

    private static func itemKey(_ item: EstimateLineItem) -> String {
        item.description ?? "\(item.id)"
    }
}

// MARK: - View

public struct EstimateVersionDiffView: View {
    let diff: EstimateVersionDiff

    public init(diff: EstimateVersionDiff) {
        self.diff = diff
    }

    public var body: some View {
        if Platform.isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - iPhone (vertical)

    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                diffHeader
                changeList
                totalSummary
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Changes v\(diff.olderVersion) → v\(diff.newerVersion)")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - iPad (two-column)

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.base) {
            // Older column
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Version \(diff.olderVersion)")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                olderItemsList
                totalRow(diff.oldTotal, label: "v\(diff.olderVersion) Total")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Newer column
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Version \(diff.newerVersion)")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                newerItemsList
                totalRow(diff.newTotal, label: "v\(diff.newerVersion) Total",
                         highlight: diff.totalChanged ? (diff.newTotal > diff.oldTotal ? .bizarreError : .bizarreSuccess) : nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Compare v\(diff.olderVersion) ↔ v\(diff.newerVersion)")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Shared components

    private var diffHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            versionPill("v\(diff.olderVersion)", color: .bizarreOnSurfaceMuted)
            Image(systemName: "arrow.right")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            versionPill("v\(diff.newerVersion)", color: .bizarreOrange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Comparing version \(diff.olderVersion) to version \(diff.newerVersion)")
    }

    private func versionPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.brandBodyMedium().bold())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Line Items")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            ForEach(diff.changes.indices, id: \.self) { idx in
                ChangeRow(change: diff.changes[idx])
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var totalSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Total change")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                let delta = diff.newTotal - diff.oldTotal
                Text("\(delta >= 0 ? "+" : "")\(formatMoney(delta))")
                    .font(.brandTitleMedium())
                    .foregroundStyle(delta > 0 ? .bizarreError : delta < 0 ? .bizarreSuccess : .bizarreOnSurface)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text("\(formatMoney(diff.oldTotal)) → \(formatMoney(diff.newTotal))")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total changed from \(formatMoney(diff.oldTotal)) to \(formatMoney(diff.newTotal))")
    }

    // iPad column helpers

    private var olderItemsList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(diff.changes.indices, id: \.self) { idx in
                oldColumnRow(diff.changes[idx])
            }
        }
    }

    private var newerItemsList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(diff.changes.indices, id: \.self) { idx in
                newColumnRow(diff.changes[idx])
            }
        }
    }

    @ViewBuilder
    private func oldColumnRow(_ change: EstimateVersionDiff.LineChange) -> some View {
        switch change {
        case .unchanged(let item), .priceChanged(let item, _, _):
            lineRow(item: item, badge: nil)
        case .removed(let item):
            lineRow(item: item, badge: "−", badgeColor: .bizarreError, strikethrough: true)
        case .added:
            Color.clear.frame(height: 36)  // placeholder to keep alignment
        }
    }

    @ViewBuilder
    private func newColumnRow(_ change: EstimateVersionDiff.LineChange) -> some View {
        switch change {
        case .unchanged(let item):
            lineRow(item: item, badge: nil)
        case .added(let item):
            lineRow(item: item, badge: "+", badgeColor: .bizarreSuccess)
        case .removed:
            Color.clear.frame(height: 36)  // placeholder
        case .priceChanged(let item, _, let newPrice):
            lineRow(item: item, badge: "Δ", badgeColor: .orange, overridePrice: newPrice)
        }
    }

    @ViewBuilder
    private func lineRow(item: EstimateLineItem, badge: String?, badgeColor: Color = .clear, strikethrough: Bool = false, overridePrice: Double? = nil) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            if let b = badge {
                Text(b)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(badgeColor, in: Circle())
                    .accessibilityLabel(badgeLabel(b))
            }
            Text(item.description ?? "Item")
                .font(.brandBodyMedium())
                .foregroundStyle(strikethrough ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .strikethrough(strikethrough, color: .bizarreOnSurfaceMuted)
                .lineLimit(2)
            Spacer()
            Text(formatMoney(overridePrice ?? item.unitPrice ?? item.total ?? 0))
                .font(.brandBodyMedium())
                .foregroundStyle(strikethrough ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .monospacedDigit()
                .strikethrough(strikethrough, color: .bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func totalRow(_ amount: Double, label: String, highlight: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(amount))
                .font(.brandBodyMedium().bold())
                .foregroundStyle(highlight ?? .bizarreOnSurface)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .padding(.top, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(formatMoney(amount))")
    }

    private func badgeLabel(_ b: String) -> String {
        switch b {
        case "+": return "Added"
        case "−": return "Removed"
        case "Δ": return "Price changed"
        default:  return b
        }
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Change row (compact layout)

private struct ChangeRow: View {
    let change: EstimateVersionDiff.LineChange

    var body: some View {
        switch change {
        case .unchanged(let item):
            rowContent(item: item, badge: nil, badgeColor: .clear)

        case .added(let item):
            rowContent(item: item, badge: "+", badgeColor: .bizarreSuccess)
                .accessibilityLabel("Added: \(label(item))")

        case .removed(let item):
            rowContent(item: item, badge: "−", badgeColor: .bizarreError, strikethrough: true)
                .accessibilityLabel("Removed: \(label(item))")

        case .priceChanged(let item, let oldPrice, let newPrice):
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                rowContent(item: item, badge: "Δ", badgeColor: .orange)
                Text("\(formatMoney(oldPrice)) → \(formatMoney(newPrice))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .padding(.leading, 26)
                    .accessibilityLabel("Price changed from \(formatMoney(oldPrice)) to \(formatMoney(newPrice))")
            }
        }
    }

    private func rowContent(item: EstimateLineItem, badge: String?, badgeColor: Color, strikethrough: Bool = false) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            if let b = badge {
                Text(b)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(badgeColor, in: Circle())
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(Color.bizarreOutline.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }

            Text(item.description ?? "Item")
                .font(.brandBodyMedium())
                .foregroundStyle(strikethrough ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .strikethrough(strikethrough, color: .bizarreOnSurfaceMuted)
                .lineLimit(2)

            Spacer()

            Text(formatMoney(item.unitPrice ?? item.total ?? 0))
                .font(.brandBodyMedium())
                .foregroundStyle(strikethrough ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .monospacedDigit()
                .strikethrough(strikethrough, color: .bizarreOnSurfaceMuted)
        }
    }

    private func label(_ item: EstimateLineItem) -> String {
        item.description ?? "Item"
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
