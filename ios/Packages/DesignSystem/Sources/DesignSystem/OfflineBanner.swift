import SwiftUI

/// Connectivity / sync-queue chip. Rendered as a safe-area overlay at the top
/// of the main shell so it shows regardless of which tab is active. Three
/// states:
///
/// - offline → orange glass "Offline — changes will sync when connected"
/// - online + pendingCount > 0 → teal glass "Syncing 3 changes…"
/// - online + pendingCount = 0 → nothing (the happy path is silent)
///
/// Caller passes the live values so this view remains a pure visual.
public struct OfflineBanner: View {
    let isOffline: Bool
    let pendingCount: Int

    public init(isOffline: Bool, pendingCount: Int = 0) {
        self.isOffline = isOffline
        self.pendingCount = pendingCount
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

    private func chip(icon: String, text: String, tint: Color, fg: Color) -> some View {
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
        .animation(BrandMotion.offlineBanner, value: isOffline)
        .animation(BrandMotion.offlineBanner, value: pendingCount)
    }
}
