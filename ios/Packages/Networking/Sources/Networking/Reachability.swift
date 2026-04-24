import Foundation
import Network
import Observation

/// NWPathMonitor-backed reachability. `start()` is deliberately separate from
/// `init()` so the monitor doesn't warm up the network stack before the app's
/// first view is on screen. `SessionBootstrapper` kicks it off from a detached
/// task after the initial phase is resolved.
@MainActor
@Observable
public final class Reachability {
    public static let shared = Reachability()

    public private(set) var isOnline: Bool = true
    public private(set) var isExpensive: Bool = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.bizarrecrm.reachability")
    @ObservationIgnored private var started = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Treat `.requiresConnection` as online too — on iPads tethered
            // via USB/AirPlay or on wifi networks without an immediate
            // upstream probe, NWPathMonitor sometimes reports
            // `.requiresConnection` even though the app can reach the server.
            // Only `.unsatisfied` means definitively offline.
            let online = path.status != .unsatisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isOnline = online
                self?.isExpensive = expensive
            }
        }
    }

    public func start() {
        guard !started else { return }
        started = true
        monitor.start(queue: queue)
    }

    /// Idempotent alias — callable from any view that needs to make sure the
    /// monitor has been warmed up. Safe to call many times.
    public func startIfNeeded() {
        start()
    }

    public func stop() {
        monitor.cancel()
        started = false
    }
}
