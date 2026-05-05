import Foundation

// §32.0 Multi-tenant telemetry routing
//
// When the user switches tenants, in-flight analytics events must be flushed
// to the OLD tenant's server before any new events are routed to the NEW
// tenant's server. Without this, events for tenant A leak into tenant B's
// analytics pipeline.
//
// Backpressure (§32.0):
//   - If the flusher returns HTTP 429, the router backs off and re-tries once
//     after `retryAfter` seconds (parsed from the response header if present,
//     otherwise `defaultBackoffSeconds`).
//   - If the buffer size exceeds `hardCapEvents`, the oldest events are dropped
//     silently (preference for freshness over completeness in analytics).
//
// Usage (wired in AppServices at session-switch time):
//   await TelemetryTenantRouter.shared.switchTenant(
//       newSlug: "acme-repair",
//       newFlusher: APITelemetryFlusher(client: apiClient)
//   )

// MARK: - TelemetryTenantRouter

/// Actor that owns the active `TelemetryBuffer` and coordinates tenant switches.
///
/// On `switchTenant(newSlug:newFlusher:)`:
/// 1. Captures the current buffer.
/// 2. Drains it to the OLD flusher (fire-and-forget, 5-second deadline).
/// 3. Replaces the active flusher + buffer with a new pair.
/// 4. New events from this point route to the new tenant.
public actor TelemetryTenantRouter {

    // MARK: - Singleton

    public static let shared = TelemetryTenantRouter()

    // MARK: - Configuration

    /// Maximum events held in the buffer before oldest are dropped.
    public static let hardCapEvents = 10_000

    /// Default back-off seconds when 429 Retry-After header is absent.
    public static let defaultBackoffSeconds: TimeInterval = 30

    /// Deadline for draining the old buffer during a tenant switch.
    private static let drainDeadlineSeconds: TimeInterval = 5

    // MARK: - State

    private var activeFlusher: (any TelemetryFlusher)?
    private var currentSlug:   String = ""
    private var buffer:        [TelemetryRecord] = []

    // MARK: - Init (private — use `.shared`)

    private init() {}

    // MARK: - Public API

    /// Enqueue an event for the current tenant.
    ///
    /// - If the buffer is at `hardCapEvents`, the oldest event is dropped
    ///   and `event` is appended (prefer freshness).
    /// - If no flusher is registered yet (before first login), the event is
    ///   silently discarded.
    public func enqueue(_ event: TelemetryRecord) async {
        guard activeFlusher != nil else { return }
        if buffer.count >= Self.hardCapEvents {
            buffer.removeFirst()   // Drop oldest — backpressure
        }
        buffer.append(event)
    }

    /// Flush all buffered events for the current tenant immediately.
    ///
    /// Handles 429 back-off: if `flusher.flush(_:)` throws a
    /// `TelemetryFlushError.rateLimited(retryAfter:)`, the router sleeps for
    /// the indicated interval then retries once. On second failure, events are
    /// re-queued (standard buffer retry semantics).
    public func flush() async {
        guard let flusher = activeFlusher, !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        await _flush(batch, using: flusher)
    }

    /// Switch the active tenant.
    ///
    /// The call blocks until the old buffer is drained (with a 5s hard timeout)
    /// before activating the new flusher. After the switch, new `enqueue(_:)`
    /// calls route to the new tenant's server exclusively.
    ///
    /// - Parameters:
    ///   - newSlug:    Stable server-issued slug for the incoming tenant.
    ///   - newFlusher: Concrete flusher pointing at the new tenant's server.
    public func switchTenant(newSlug: String, newFlusher: any TelemetryFlusher) async {
        // 1. Drain old buffer to old flusher within deadline.
        if let oldFlusher = activeFlusher, !buffer.isEmpty {
            let oldBatch = buffer
            buffer = []
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await oldFlusher.flush(oldBatch) }
                group.addTask {
                    try await Task.sleep(
                        nanoseconds: UInt64(Self.drainDeadlineSeconds * 1_000_000_000)
                    )
                    throw CancellationError()
                }
                // Take whichever finishes first; ignore errors (best-effort drain).
                _ = try? await group.next()
                group.cancelAll()
            }
        }

        // 2. Activate new tenant.
        currentSlug   = newSlug
        activeFlusher = newFlusher
        buffer        = []
    }

    /// Register the initial flusher on first login. No drain needed (buffer is empty).
    public func setInitialFlusher(_ flusher: any TelemetryFlusher, slug: String) {
        guard activeFlusher == nil else { return }
        activeFlusher = flusher
        currentSlug   = slug
    }

    /// The slug of the currently active tenant.
    public var slug: String { currentSlug }

    // MARK: - Private helpers

    private func _flush(_ batch: [TelemetryRecord], using flusher: any TelemetryFlusher) async {
        do {
            try await flusher.flush(batch)
        } catch TelemetryFlushError.rateLimited(let retryAfter) {
            // §32.0 backpressure: 429 — wait then retry once.
            let delay = retryAfter ?? Self.defaultBackoffSeconds
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // Retry once; on second failure re-queue.
            do {
                try await flusher.flush(batch)
            } catch {
                // Re-queue at front; cap at hardCapEvents.
                buffer.insert(contentsOf: batch, at: 0)
                if buffer.count > Self.hardCapEvents {
                    buffer.removeFirst(buffer.count - Self.hardCapEvents)
                }
            }
        } catch {
            // Transport failure — re-queue.
            buffer.insert(contentsOf: batch, at: 0)
            if buffer.count > Self.hardCapEvents {
                buffer.removeFirst(buffer.count - Self.hardCapEvents)
            }
        }
    }
}

// MARK: - TelemetryFlushError

/// Errors that `TelemetryFlusher` implementations may throw.
public enum TelemetryFlushError: Error, Sendable {
    /// HTTP 429 received. Associated value is parsed from `Retry-After` header (seconds).
    case rateLimited(retryAfter: TimeInterval?)
    /// Generic transport failure.
    case transport(underlying: any Error)
}
