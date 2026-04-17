import Foundation
import Network
import Observation

@MainActor
@Observable
public final class Reachability {
    public static let shared = Reachability()

    public private(set) var isOnline: Bool = true
    public private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.bizarreelectronics.reachability")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isOnline = online
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
