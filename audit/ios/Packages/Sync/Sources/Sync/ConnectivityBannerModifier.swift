import SwiftUI
import DesignSystem
import Networking

// §20.6 Connectivity detection — offline banner glass chip
//
// Drop-in modifier that attaches the branded `OfflineBanner` to any
// navigation-stack-root screen. It observes `Reachability.shared` so the
// banner appears / disappears reactively as the device goes on/offline and
// also surfaces the number of pending sync writes.
//
// Usage:
//
//   var body: some View {
//       TicketListView()
//           .connectivityBanner()
//   }
//
// The modifier pins the chip to the top of the safe area using a `safeAreaInset`
// so it never occludes navigation title or list rows underneath.

// MARK: - ConnectivityBannerModifier

public struct ConnectivityBannerModifier: ViewModifier {
    @Environment(Reachability.self) private var reachability
    @State private var pendingCount: Int = 0

    public init() {}

    // §20.6: derive copy variant so the banner text is always accurate.
    private var bannerCopy: OfflineBannerCopy {
        OfflineBannerCopy.resolve(reachability: reachability)
    }

    /// Show the banner when offline, on cellular with pending writes, or
    /// any limited-connectivity state that isn't fully online.
    private var shouldShowBanner: Bool {
        switch bannerCopy.kind {
        case .online:          return pendingCount > 0   // pending badge only
        case .noSignal:        return true
        case .cellular:        return true
        case .constrainedWifi: return true
        }
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldShowBanner {
                    HStack {
                        Spacer()
                        if bannerCopy.kind == .online {
                            // Online + pending: use existing OfflineBanner (shows "Syncing N…").
                            OfflineBanner(
                                isOffline: false,
                                pendingCount: pendingCount,
                                expanded: true
                            )
                        } else {
                            // Offline / cellular / constrained: show copy-variant chip.
                            ConnectivityCopyChip(copy: bannerCopy, pendingCount: pendingCount)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(BrandMotion.banner, value: reachability.isOnline)
                    .animation(BrandMotion.banner, value: reachability.isExpensive)
                    .animation(BrandMotion.banner, value: pendingCount)
                }
            }
            .task {
                // Poll SyncManager.shared.pendingCount via observation.
                // @Observable propagates MainActor changes through AsyncStream.
                // We read the value directly since SyncManager is @MainActor + @Observable.
                pendingCount = SyncManager.shared.pendingCount
            }
            .onChange(of: reachability.isOnline) { _, _ in
                Task { @MainActor in
                    pendingCount = SyncManager.shared.pendingCount
                }
            }
    }
}

// MARK: - ConnectivityCopyChip

/// Internal chip that renders copy-variant text for non-online states.
/// Mirrors the visual design of `OfflineBanner` but accepts arbitrary
/// copy from `OfflineBannerCopy` so each connectivity state has its own
/// headline/subline (e.g. "No internet connection" vs "Using cellular data").
struct ConnectivityCopyChip: View {

    let copy: OfflineBannerCopy
    let pendingCount: Int

    private var tint: Color {
        switch copy.kind {
        case .noSignal:        return .bizarreWarning
        case .cellular:        return .bizarreTeal
        case .constrainedWifi: return .bizarreWarning
        case .online:          return .bizarreTeal
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: copy.iconName)
                    .accessibilityHidden(true)
                Text(copy.headline)
                    .font(.brandLabelLarge())
                    .lineLimit(1)
            }
            if !copy.subline.isEmpty {
                Text(copy.subline)
                    .font(.brandLabelSmall())
                    .lineLimit(1)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Color.bizarreOnSurface)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.accessibilityLabel)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(BrandMotion.offlineBanner, value: copy.kind)
    }
}

// MARK: - View extension

public extension View {
    /// Attach the §20.6 connectivity banner to this screen.
    ///
    /// Requires `Reachability` in the environment (injected once at app root
    /// via `.environment(Reachability.shared)`).
    func connectivityBanner() -> some View {
        modifier(ConnectivityBannerModifier())
    }
}
