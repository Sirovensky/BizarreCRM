import Foundation
@preconcurrency import MetricKit

// §32.2 MetricKit performance metrics — tenant-server upload
//
// Data-sovereignty rule: all payloads POSTed to `APIClient.baseURL`
// (tenant server only). No third-party SaaS.
//
// MetricKit delivers hourly batches. We serialize the full
// `MXMetricPayload.jsonRepresentation()` (redacted — no PII in
// MetricKit payloads by design) and upload to `POST /telemetry/metrics`.
// The upload closure is injected so AppServices can bind `APIClient.post`.

// MARK: - MetricKitManager

/// Subscribes to `MXMetricManager` and uploads hourly performance payloads
/// to the tenant server.
///
/// **Wiring:** call `MetricKitManager.shared.start()` from `AppServices`
/// at app launch, alongside `CrashReporter.shared.start()`.
///
/// **Upload closure:** inject via `MetricKitManager(upload:)` in `AppServices`,
/// binding the `APIClient` of the active session. The closure should POST to
/// `"/telemetry/metrics"` on the tenant server.
public final class MetricKitManager: @unchecked Sendable {

    // MARK: — Singleton (no-op upload until AppServices wires it up)

    public static let shared = MetricKitManager()

    // MARK: — Internals

    private let delegate: MetricKitDelegate

    // MARK: — Init

    /// - Parameter upload: Called for each serialized `MXMetricPayload` JSON.
    ///   Receives the UTF-8 JSON bytes. Should POST to `/telemetry/metrics`.
    ///   Defaults to a no-op (useful for previews / test targets).
    public init(upload: @escaping @Sendable (Data) async throws -> Void = { _ in }) {
        self.delegate = MetricKitDelegate(upload: upload)
    }

    // MARK: — Lifecycle

    /// Register with MetricKit. Call once at app launch.
    public func start() {
        MXMetricManager.shared.add(delegate)
    }

    /// Unregister from MetricKit. Called on teardown / test cleanup.
    public func stop() {
        MXMetricManager.shared.remove(delegate)
    }
}

// MARK: - MetricKitDelegate (NSObject bridge required by MXMetricManagerSubscriber)

final class MetricKitDelegate: NSObject, MXMetricManagerSubscriber {

    private let upload: @Sendable (Data) async throws -> Void

    init(upload: @escaping @Sendable (Data) async throws -> Void) {
        self.upload = upload
    }

    /// Called by MetricKit approximately once per hour while the app is active.
    ///
    /// `MXMetricPayload.jsonRepresentation()` returns an `NSData` snapshot
    /// of the payload in Apple's documented JSON format. No PII is included
    /// by design — MetricKit payloads contain only timing + resource stats.
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Serialize payload data on the calling thread (MetricKit callback).
        // MXMetricPayload is non-Sendable; capture as raw Data before crossing
        // concurrency boundaries.
        let blobs: [Data] = payloads.map { $0.jsonRepresentation() }
        let send = upload
        Task.detached(priority: .utility) {
            for blob in blobs {
                // Wrap in a lightweight envelope so the server can distinguish
                // metric payloads from crash diagnostics.
                let envelope = MetricPayloadEnvelope(
                    kind: "metric_payload",
                    platform: "iOS",
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    payloadJSON: blob
                )
                guard let data = try? JSONEncoder.metricKit.encode(envelope) else { continue }
                try? await send(data)
            }
        }
    }

    /// Diagnostic payloads (crash, hang, disk write, CPU) are handled by
    /// `CrashReporter`; this subscriber intentionally ignores them.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {}
}

// MARK: - MetricPayloadEnvelope

/// Sendable envelope wrapping the raw MetricKit JSON so the server can route it.
struct MetricPayloadEnvelope: Codable, Sendable {
    /// Always `"metric_payload"` for `MXMetricPayload` uploads.
    let kind: String
    let platform: String
    let appVersion: String
    /// Raw `MXMetricPayload.jsonRepresentation()` bytes.
    let payloadJSON: Data
}

// MARK: - JSONEncoder preset

private extension JSONEncoder {
    static let metricKit: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .sortedKeys
        return enc
    }()
}
