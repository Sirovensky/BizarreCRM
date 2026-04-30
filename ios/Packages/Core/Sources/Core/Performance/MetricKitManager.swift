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
/// and diagnostic payloads to the tenant server.
///
/// **Wiring:** call `MetricKitManager.shared.start()` from `AppServices`
/// at app launch, alongside `CrashReporter.shared.start()`.
///
/// **Upload closure:** inject via `MetricKitManager(upload:uploadDiagnostic:)` in
/// `AppServices`, binding the `APIClient` of the active session. Metric payloads
/// POST to `"/telemetry/metrics"`; diagnostic payloads POST to
/// `"/diagnostics/report"` (same endpoint used by `CrashReporter`).
public final class MetricKitManager: @unchecked Sendable {

    // MARK: — Singleton (no-op upload until AppServices wires it up)

    public static let shared = MetricKitManager()

    // MARK: — Internals

    private let delegate: MetricKitDelegate

    // MARK: — Init

    /// - Parameters:
    ///   - upload: Called for each serialized `MXMetricPayload` JSON.
    ///     Receives the UTF-8 JSON bytes. Should POST to `/telemetry/metrics`.
    ///     Defaults to a no-op (useful for previews / test targets).
    ///   - uploadDiagnostic: Called for each `MXDiagnosticPayload` JSON envelope.
    ///     Should POST to `/diagnostics/report`. Defaults to a no-op.
    public init(
        upload: @escaping @Sendable (Data) async throws -> Void = { _ in },
        uploadDiagnostic: @escaping @Sendable (Data) async throws -> Void = { _ in }
    ) {
        self.delegate = MetricKitDelegate(upload: upload, uploadDiagnostic: uploadDiagnostic)
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
    private let uploadDiagnostic: @Sendable (Data) async throws -> Void

    init(
        upload: @escaping @Sendable (Data) async throws -> Void,
        uploadDiagnostic: @escaping @Sendable (Data) async throws -> Void
    ) {
        self.upload = upload
        self.uploadDiagnostic = uploadDiagnostic
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

    /// §32.2 — Receive hitch-rate and CPU-exception diagnostic payloads from MetricKit.
    ///
    /// MetricKit delivers `MXDiagnosticPayload` on the next app launch after an
    /// anomaly (hang, hitch, CPU exception, disk write exception). We upload the
    /// full JSON representation to `POST /diagnostics/report` on the tenant server
    /// (same endpoint used by `CrashReporter` for `MXCrashDiagnostic`).
    ///
    /// **Data-sovereignty rule:** payloads go to `APIClient.baseURL` only — no
    /// third-party crash SaaS. `MXDiagnosticPayload` contains stack frames and
    /// timing data; no heap snapshots or user-facing strings are included by Apple.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let blobs: [Data] = payloads.map { $0.jsonRepresentation() }
        let send = uploadDiagnostic
        Task.detached(priority: .utility) {
            for blob in blobs {
                let envelope = MetricPayloadEnvelope(
                    kind: "diagnostic_payload",
                    platform: "iOS",
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    payloadJSON: blob
                )
                guard let data = try? JSONEncoder.metricKit.encode(envelope) else { continue }
                try? await send(data)
            }
        }
    }
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
