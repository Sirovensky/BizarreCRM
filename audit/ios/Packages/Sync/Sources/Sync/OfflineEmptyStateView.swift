import SwiftUI
import DesignSystem
import Core

// MARK: - OfflineEmptyStateView

/// Per-list empty state shown when the device is offline and the local cache
/// is empty. Distinct from the global `OfflineBanner` (which lives in
/// `RootView`) — this appears inline where the list content would normally be.
///
/// Usage:
/// ```swift
/// if isOffline && items.isEmpty {
///     OfflineEmptyStateView(entityName: "tickets")
/// }
/// ```
///
/// Liquid Glass on the icon badge only (chrome). The message text is content.
public struct OfflineEmptyStateView: View {
    /// Human-readable plural name for the entity ("tickets", "customers", …).
    public let entityName: String

    public init(entityName: String) {
        self.entityName = entityName
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.md) {
            iconBadge
            Text("You're offline")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("No cached \(entityName) available. Connect to the internet to load data.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. No cached \(entityName) available.")
    }

    private var iconBadge: some View {
        ZStack {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
        }
        .padding(BrandSpacing.md)
        .brandGlass(.clear, tint: Color.bizarreWarning.opacity(0.12))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    OfflineEmptyStateView(entityName: "tickets")
        .background(Color.bizarreSurfaceBase)
}
#endif
