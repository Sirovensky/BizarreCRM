#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosOutageBannerView (§16.12 offline outage banner)

/// §16.12 — Sticky amber banner shown at the top of the POS chrome when the
/// device is offline and one or more sales are queued for later sync.
///
/// **Spec (§16.12):**
/// > UI: outage banner "Offline mode — N sales queued"; dashboard tile tracks
/// > queue depth.
///
/// **Placement:** Use `.safeAreaInset(edge: .top)` in `PosView` below the
/// navigation bar. The banner uses `.brandGlass` with a warning tint — it is
/// a sticky chrome element per `CLAUDE.md` glass-usage rules.
///
/// **States:**
/// - Hidden when `queuedSaleCount == 0` or `isOnline == true`.
/// - Visible + expandable when offline AND `queuedSaleCount > 0`.
/// - Expanded: shows `PosOfflineAuditService.mostRecentOutageSummary`.
///
/// **Accessibility:** The banner announces itself via VoiceOver as a status
/// update when it first appears. Reduce Motion: the slide-in animation is
/// replaced with a fade.
///
/// **Usage:**
/// ```swift
/// PosView()
///     .safeAreaInset(edge: .top) {
///         PosOutageBannerView(
///             isOnline: networkMonitor.isOnline,
///             queuedSaleCount: syncManager.pendingCount,
///             onTapBanner: { showOfflineQueue = true }
///         )
///     }
/// ```
public struct PosOutageBannerView: View {

    public let isOnline: Bool
    public let queuedSaleCount: Int
    public let onTapBanner: (() -> Void)?

    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        !isOnline && queuedSaleCount > 0
    }

    public init(
        isOnline: Bool,
        queuedSaleCount: Int,
        onTapBanner: (() -> Void)? = nil
    ) {
        self.isOnline       = isOnline
        self.queuedSaleCount = queuedSaleCount
        self.onTapBanner    = onTapBanner
    }

    public var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // Main banner row
                Button {
                    withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bizarreWarning)
                            .accessibilityHidden(true)

                        Text(bannerLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.bizarreWarning)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.bizarreWarning.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bannerAccessibilityLabel)
                .accessibilityHint(isExpanded ? "Double tap to collapse details" : "Double tap to expand details")
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("pos.outageBanner.header")

                // Expanded detail row
                if isExpanded {
                    Divider()
                        .background(Color.bizarreWarning.opacity(0.25))

                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        if let summary = PosOfflineAuditService.shared.mostRecentOutageSummary {
                            Text(summary)
                                .font(.brandLabelMedium())
                                .foregroundStyle(Color.bizarreOnSurface)
                        }

                        HStack(spacing: BrandSpacing.sm) {
                            Text("Sales will sync automatically when connection is restored.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let onTap = onTapBanner {
                                Button("Review") {
                                    onTap()
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.bizarreOrange)
                                .accessibilityIdentifier("pos.outageBanner.review")
                            }
                        }
                    }
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier("pos.outageBanner.detail")
                }
            }
            .background(
                Color.bizarreWarning.opacity(0.10)
                    .overlay(
                        Rectangle()
                            .brandGlass(.clear, in: Rectangle(), tint: .bizarreWarning)
                    )
            )
            .overlay(alignment: .bottom) {
                Divider()
                    .background(Color.bizarreWarning.opacity(0.20))
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .top))
            )
            .accessibilityIdentifier("pos.outageBanner")
            .onAppear {
                // VoiceOver status announcement when the banner first appears.
                UIAccessibility.post(
                    notification: .announcement,
                    argument: bannerAccessibilityLabel
                )
            }
        }
    }

    // MARK: - Labels

    private var bannerLabel: String {
        let s = queuedSaleCount == 1 ? "sale" : "sales"
        return "Offline mode — \(queuedSaleCount) \(s) queued"
    }

    private var bannerAccessibilityLabel: String {
        let s = queuedSaleCount == 1 ? "sale" : "sales"
        return "Offline mode. \(queuedSaleCount) \(s) queued for sync when connection is restored."
    }
}

// MARK: - ViewModifier convenience

extension View {
    /// Attach the offline outage banner as a top safe-area inset.
    /// Pass `isOnline` from your network monitor and `queuedSaleCount`
    /// from `SyncManager.pendingCount`.
    public func posOutageBanner(
        isOnline: Bool,
        queuedSaleCount: Int,
        onTapBanner: (() -> Void)? = nil
    ) -> some View {
        self.safeAreaInset(edge: .top, spacing: 0) {
            PosOutageBannerView(
                isOnline: isOnline,
                queuedSaleCount: queuedSaleCount,
                onTapBanner: onTapBanner
            )
        }
    }
}
#endif
