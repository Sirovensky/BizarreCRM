import Foundation
#if canImport(Network)
import Network
#endif

// §29.3 Image prefetch — gate prefetch decisions on network conditions.
//
// Prefetching the next 10 rows of thumbnails is a free win on Wi-Fi and a
// disaster on metered cellular with Low Data Mode on. This actor centralises
// the "is it safe to prefetch right now?" check so callers (Nuke prefetch
// scheduler, list scroll handlers) don't each re-implement the same guard.
//
// Decision tree:
//   • Low Power Mode on  → never prefetch (preserve battery).
//   • Path constrained   → never prefetch (Low Data Mode).
//   • Path expensive +
//     `cellularAllowed = false` → never prefetch.
//   • Otherwise          → prefetch up to `windowSize` rows ahead.

/// Decision point for whether to prefetch off-screen images.
///
/// `@MainActor` because it reads `LowPowerModeObserver.shared` which is
/// main-actor-isolated. Cheap to call — the underlying `NWPathMonitor` is
/// started once and updates a cached path snapshot.
@MainActor
public final class ImagePrefetchGate {

    public static let shared = ImagePrefetchGate()

    /// Number of rows ahead/behind to prefetch when the gate allows it.
    public var windowSize: Int = 10

    /// Whether prefetching is permitted on cellular when the OS doesn't flag
    /// the path as constrained. Default `true` — most tenants are fine with
    /// thumbnail prefetch on LTE; opt out via Settings.
    public var cellularAllowed: Bool = true

    private init() {
        #if canImport(Network)
        startMonitor()
        #endif
    }

    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private var currentPath: NWPath?

    private func startMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.currentPath = path
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bizarrecrm.prefetch-gate"))
    }
    #endif

    /// `true` if the gate currently allows prefetch. Returns `false` on Low
    /// Power Mode, constrained network (Low Data Mode), or expensive path
    /// when cellular prefetch is disabled.
    public var isAllowed: Bool {
        if LowPowerModeObserver.shared.isEnabled { return false }
        #if canImport(Network)
        guard let path = currentPath else { return true }
        if path.status != .satisfied { return false }
        if path.isConstrained { return false }
        if path.isExpensive && !cellularAllowed { return false }
        #endif
        return true
    }

    /// Effective prefetch window — `windowSize` when allowed, `0` when blocked.
    /// Use this so callers compute one value and never branch on `isAllowed`
    /// twice (avoids subtle TOCTOU bugs across the same scroll tick).
    public var effectiveWindow: Int { isAllowed ? windowSize : 0 }
}
