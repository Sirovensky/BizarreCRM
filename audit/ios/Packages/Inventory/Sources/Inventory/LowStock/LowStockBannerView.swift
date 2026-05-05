#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - LowStockBannerView

/// A list-header banner that summarises outstanding low-stock alerts.
///
/// Place inside a `List` `header` or above a `List` as a section header.
/// Tapping the banner calls `onTap` — the parent can navigate to a full
/// low-stock screen or present a sheet.
///
/// Usage:
/// ```swift
/// List {
///     Section(header: LowStockBannerView(alerts: alerts, onTap: { showSheet = true })) {
///         ForEach(items) { ... }
///     }
/// }
/// ```
public struct LowStockBannerView: View {

    // MARK: Input

    /// Current set of low-stock alerts to summarise.
    public let alerts: [LowStockAlert]
    /// Called when the user taps the banner.
    public let onTap: () -> Void

    // MARK: Init

    public init(alerts: [LowStockAlert], onTap: @escaping () -> Void) {
        self.alerts = alerts
        self.onTap = onTap
    }

    // MARK: Body

    public var body: some View {
        if !alerts.isEmpty {
            bannerContent
        }
    }

    // MARK: - Banner

    private var bannerContent: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(bannerIconColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if hasCritical {
                        Text(criticalSubtitleText)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }

                Spacer(minLength: BrandSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(bannerBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to view all low-stock items")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Derived helpers

    private var criticalCount: Int {
        alerts.filter { $0.severity == .critical }.count
    }

    private var hasCritical: Bool { criticalCount > 0 }

    private var headlineText: String {
        let count = alerts.count
        return count == 1
            ? "1 item below stock threshold"
            : "\(count) items below stock threshold"
    }

    private var criticalSubtitleText: String {
        criticalCount == 1
            ? "1 item critically low"
            : "\(criticalCount) items critically low"
    }

    private var bannerIconColor: Color {
        hasCritical ? .bizarreError : .bizarreWarning
    }

    private var bannerBackgroundColor: Color {
        hasCritical
            ? Color.bizarreError.opacity(0.08)
            : Color.bizarreWarning.opacity(0.08)
    }

    private var accessibilityLabel: String {
        var parts = [headlineText]
        if hasCritical { parts.append(criticalSubtitleText) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#Preview("With critical alerts") {
    let alerts: [LowStockAlert] = [
        LowStockAlert(itemId: 1, itemName: "iPhone 15 Screen", sku: "SCR-001",
                      currentQty: 0, threshold: 10, isOverrideThreshold: false),
        LowStockAlert(itemId: 2, itemName: "USB-C Cable", sku: "CBL-002",
                      currentQty: 3, threshold: 5, isOverrideThreshold: true),
        LowStockAlert(itemId: 3, itemName: "Battery Pack", sku: "BAT-003",
                      currentQty: 4, threshold: 5, isOverrideThreshold: false)
    ]
    List {
        Section(header: LowStockBannerView(alerts: alerts, onTap: {})) {
            Text("Item A")
            Text("Item B")
        }
    }
}

#Preview("Single warning alert") {
    let alerts: [LowStockAlert] = [
        LowStockAlert(itemId: 1, itemName: "Screen Protector", sku: "SP-010",
                      currentQty: 3, threshold: 5, isOverrideThreshold: false)
    ]
    List {
        Section(header: LowStockBannerView(alerts: alerts, onTap: {})) {
            Text("Item A")
        }
    }
}

#Preview("No alerts — hidden") {
    List {
        Section(header: LowStockBannerView(alerts: [], onTap: {})) {
            Text("Item A")
        }
    }
}
#endif
