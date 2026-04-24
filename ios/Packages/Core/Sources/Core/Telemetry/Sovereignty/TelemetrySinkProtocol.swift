import Foundation

// §32 Telemetry Sovereignty Guardrails — sink abstraction
// Core never touches the network; the app-shell wires an APIClient-backed impl.

// MARK: - TelemetryFlusher

/// Protocol that the app-shell implements, backed by `APIClient`.
///
/// `Core` defines this protocol but **never imports `Networking`** or any
/// third-party SDK. The concrete implementation lives outside `Core` and is
/// injected at startup via the DI container.
///
/// Sovereignty guarantee: conforming types must POST exclusively to the
/// tenant's own server via `APIClient`. No third-party analytics SDKs are
/// permitted.
///
/// ## Contract
///
/// - `flush(_:)` is called by `TelemetryBuffer` when the buffer is full or a
///   timed interval fires. Implementations must be idempotent — the same batch
///   may be delivered twice only on a crash between flush and acknowledgement.
/// - Implementations should be `actor`-isolated or otherwise thread-safe.
/// - On network failure, implementations MAY retry internally but MUST NOT
///   re-enqueue events into the originating `TelemetryBuffer`.
///
/// ```swift
/// // App-shell (outside Core):
/// struct APITelemetryFlusher: TelemetryFlusher {
///     let client: APIClient
///     func flush(_ events: [TelemetryRecord]) async throws {
///         try await client.post("/telemetry/events", body: events)
///     }
/// }
/// ```
public protocol TelemetryFlusher: Sendable {

    /// Transmit a batch of already-redacted telemetry records.
    ///
    /// - Parameter events: Non-empty array of `TelemetryRecord` values.
    ///   Values have already been scrubbed through `TelemetryRedactor`.
    /// - Throws: Any transport-level error. `TelemetryBuffer` catches this
    ///   and re-queues the batch for the next flush cycle.
    func flush(_ events: [TelemetryRecord]) async throws
}
