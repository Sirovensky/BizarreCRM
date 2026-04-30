import SwiftUI

/// Connectivity / sync-queue chip. Two visual modes:
///
/// - **Expanded**: full glass chip with icon + text. Used the first time the
///   state transitions (grabs attention for a few seconds).
/// - **Compact**: icon-only circular glass pill. Tucks into the top-trailing
///   corner so it doesn't steal real-estate from navigation chrome.
///
/// States:
///
/// - offline → orange "Offline — changes will sync when connected"
/// - online + pendingCount > 0 → teal "Syncing N change(s)…"
/// - online + pendingCount = 0 → nothing (the happy path is silent)
///
/// Caller passes the live values so this view remains a pure visual.
public struct OfflineBanner: View {
    let isOffline: Bool
    let pendingCount: Int
    let expanded: Bool

    public init(isOffline: Bool, pendingCount: Int = 0, expanded: Bool = true) {
        self.isOffline = isOffline
        self.pendingCount = pendingCount
        self.expanded = expanded
    }

    public var body: some View {
        if isOffline {
            chip(
                icon: "wifi.slash",
                text: "Offline — changes will sync when connected",
                tint: .bizarreWarning,
                fg: .bizarreOnOrange
            )
            .accessibilityLabel("Offline. \(pendingCount) pending change\(pendingCount == 1 ? "" : "s").")
        } else if pendingCount > 0 {
            chip(
                icon: "arrow.triangle.2.circlepath",
                text: "Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s")…",
                tint: .bizarreTeal,
                fg: .bizarreOnSurface
            )
            .accessibilityLabel("Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s").")
        }
    }

    @ViewBuilder
    private func chip(icon: String, text: String, tint: Color, fg: Color) -> some View {
        if expanded {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.brandLabelLarge())
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .brandGlass(.regular, tint: tint)
            .transition(.move(edge: .top).combined(with: .opacity))
            // §26.3 — `brandSpring` reads `\.accessibilityReduceMotion` and
            // swaps the bouncy banner spring for a 0.15s cross-fade when the
            // user has Reduce Motion enabled.
            .brandSpring(BrandMotion.offlineBanner, value: isOffline)
            .brandSpring(BrandMotion.offlineBanner, value: pendingCount)
        } else {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(fg)
                .frame(width: 28, height: 28)
                .brandGlass(.regular, tint: tint)
                .clipShape(Circle())
                .transition(.scale.combined(with: .opacity))
                // §26.3 — same OS-flag-aware spring/cross-fade swap.
                .brandSpring(BrandMotion.offlineBanner, value: isOffline)
                .brandSpring(BrandMotion.offlineBanner, value: pendingCount)
        }
    }
}
