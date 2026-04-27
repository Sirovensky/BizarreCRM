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

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !reachability.isOnline || pendingCount > 0 {
                    HStack {
                        Spacer()
                        OfflineBanner(
                            isOffline: !reachability.isOnline,
                            pendingCount: pendingCount,
                            expanded: true
                        )
                        Spacer()
                    }
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(BrandMotion.banner, value: reachability.isOnline)
                    .animation(BrandMotion.banner, value: pendingCount)
                }
            }
            .task {
                // Poll SyncManager.shared.pendingCount via observation.
                // @Observable propagates MainActor changes through AsyncStream.
                // We read the value directly since SyncManager is @MainActor + @Observable.
                pendingCount = await SyncManager.shared.pendingCount
            }
            .onChange(of: reachability.isOnline) { _, _ in
                Task { @MainActor in
                    pendingCount = SyncManager.shared.pendingCount
                }
            }
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
