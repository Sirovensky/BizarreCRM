import Foundation

// §32.0 — Self-hosted telemetry endpoints
//
// Single source of truth for the five tenant-server telemetry paths listed in
// §32.0. Every telemetry / metrics / crash / diagnostics / heartbeat call site
// must reference one of these constants instead of hard-coding a path so the
// server-side route registry and the client stay in sync.
//
// Sovereignty: these are paths only — the host is always
// `APIClient.baseURL` / `com.bizarrecrm.apiBaseURL`. No third-party domain.

/// §32.0 — Canonical relative paths for the tenant-server telemetry surface.
///
/// All values are relative paths intended to be appended to `APIClient.baseURL`.
/// They include a leading slash so they can be joined directly via
/// `URL(string: path, relativeTo: baseURL)`.
public enum TelemetryEndpoints: String, Sendable, CaseIterable {

    // MARK: — Endpoint paths

    /// `POST /telemetry/events` — first-party analytics event batches.
    case events       = "/telemetry/events"

    /// `POST /telemetry/metrics` — MetricKit `MXMetricPayload` envelopes.
    case metrics      = "/telemetry/metrics"

    /// `POST /telemetry/crashes` — `MXCrashDiagnostic` payloads (own pipeline).
    case crashes      = "/telemetry/crashes"

    /// `POST /telemetry/diagnostics` — hitch + CPU exception diagnostics, sysdiagnose-style bundles.
    case diagnostics  = "/telemetry/diagnostics"

    /// `POST /telemetry/heartbeat` — liveness ping every 5 min while foregrounded.
    case heartbeat    = "/telemetry/heartbeat"

    // MARK: — Convenience

    /// The HTTP method used for every telemetry endpoint (`POST`).
    public var httpMethod: String { "POST" }

    /// The relative path string (alias of `rawValue`) for use with URL builders.
    public var path: String { rawValue }

    /// Resolve the absolute `URL` for this endpoint against a tenant-server base URL.
    ///
    /// - Parameter baseURL: The tenant-server base URL (e.g. `https://acme.bizarrecrm.com`).
    public func url(relativeTo baseURL: URL) -> URL? {
        URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}
