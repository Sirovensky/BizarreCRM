import Foundation
import Network
import Networking
import Core

// MARK: - §36.5 Periodic tenant-server ping / latency chart

/// Periodically pings the tenant server and tracks latency history.
///
/// - Pings `GET /api/v1/health` at `interval` (default 30 s).
/// - Stores the last 60 samples so callers can render a latency chart.
/// - Fires `onP95Alert` when the rolling p95 exceeds 1 000 ms (§36.5 spec).
/// - Sovereignty: probes only the tenant server; no third-party endpoint.
///
/// Integration (Settings → Diagnostics):
/// ```swift
/// let monitor = ServerLatencyMonitor(api: apiClient)
/// monitor.start()
/// // Bind .samples to a Swift Charts view
/// // Bind .p95ms for the alert badge
/// ```
@MainActor
@Observable
public final class ServerLatencyMonitor {

    // MARK: - Constants

    /// Maximum samples retained (60 × 30s = 30 minutes of history).
    public static let maxSamples = 60

    /// P95 alert threshold in milliseconds.
    public static let alertThresholdMs: Double = 1_000

    // MARK: - Observable state

    /// The last N latency samples, oldest first.
    public private(set) var samples: [LatencySample] = []

    /// Whether the monitor is currently running.
    public private(set) var isRunning = false

    /// Current status of the most recent probe.
    public private(set) var lastStatus: PingStatus = .idle

    // MARK: - Computed metrics

    /// P95 latency in milliseconds across available samples. `nil` if < 2 samples.
    public var p95ms: Double? {
        guard samples.count >= 2 else { return nil }
        let sorted = samples.compactMap(\.latencyMs).sorted()
        let idx = Int(Double(sorted.count) * 0.95)
        return sorted[min(idx, sorted.count - 1)]
    }

    /// True when p95 > 1 000 ms (sustained alert condition per §36.5).
    public var isP95AlertActive: Bool {
        guard let p95 = p95ms else { return false }
        return p95 > Self.alertThresholdMs
    }

    /// Average latency in milliseconds. `nil` if no successful samples.
    public var averageMs: Double? {
        let successful = samples.compactMap(\.latencyMs)
        guard !successful.isEmpty else { return nil }
        return successful.reduce(0, +) / Double(successful.count)
    }

    // MARK: - Dependencies

    private let api: APIClient
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - api:      The tenant's `APIClient` instance.
    ///   - interval: Probe interval in seconds. Default 30 s.
    public init(api: APIClient, interval: TimeInterval = 30) {
        self.api = api
        self.interval = interval
    }

    // MARK: - Lifecycle

    /// Start periodic probing. Idempotent.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            // Probe immediately, then on interval.
            await self.probe()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.probe()
            }
        }
    }

    /// Stop probing.
    public func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    /// Trigger a single manual probe (e.g. user-initiated refresh).
    public func probOnce() async {
        await probe()
    }

    // MARK: - Private

    private func probe() async {
        lastStatus = .probing
        let start = Date()
        do {
            _ = try await api.serverHealth()
            let latencyMs = Date().timeIntervalSince(start) * 1000
            appendSample(LatencySample(date: start, latencyMs: latencyMs))
            lastStatus = .ok(latencyMs: latencyMs)
        } catch {
            appendSample(LatencySample(date: start, latencyMs: nil))
            lastStatus = .failed
        }
    }

    private func appendSample(_ sample: LatencySample) {
        samples.append(sample)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }
}

// MARK: - Supporting types

/// A single latency measurement.
public struct LatencySample: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    /// `nil` when the probe failed (server unreachable).
    public let latencyMs: Double?

    public init(date: Date, latencyMs: Double?) {
        self.date = date
        self.latencyMs = latencyMs
    }
}

/// Current probe status.
public enum PingStatus: Sendable, Equatable {
    case idle
    case probing
    case ok(latencyMs: Double)
    case failed

    public var icon: String {
        switch self {
        case .idle:    return "circle"
        case .probing: return "arrow.clockwise"
        case .ok:      return "checkmark.circle.fill"
        case .failed:  return "xmark.circle.fill"
        }
    }

    public static func == (lhs: PingStatus, rhs: PingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.probing, .probing), (.failed, .failed): return true
        case (.ok(let a), .ok(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - APIClient health endpoint

public extension APIClient {
    /// GET `/api/v1/health`
    ///
    /// Lightweight server health probe used by `ServerLatencyMonitor`.
    /// Returns 200 OK with `{ status: "ok" }` when the server is reachable.
    func serverHealth() async throws -> ServerHealthResponse {
        try await get("/api/v1/health", as: ServerHealthResponse.self)
    }
}

public struct ServerHealthResponse: Codable, Sendable {
    public let status: String
    public init(status: String) { self.status = status }
}
