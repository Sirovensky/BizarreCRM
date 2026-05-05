import Foundation
@preconcurrency import MetricKit

// §32.5 Crash recovery pipeline — CrashReporter
// Phase 11
//
// Data sovereignty: Apple MetricKit only. No Crashlytics/Sentry/Bugsnag/DataDog.

/// Apple MetricKit-backed crash and diagnostic reporter.
///
/// Subscribes to `MXMetricManager` and receives:
/// - `MXCrashDiagnostic`         — symbolicated call stack after a crash
/// - `MXHangDiagnostic`          — main-thread hang exceeding 250ms
/// - `MXDiskWriteExceptionDiagnostic` — excessive disk writes
/// - `MXCPUExceptionDiagnostic`  — CPU overuse
///
/// All diagnostics are redacted via `LogRedactor` before network transmission.
/// Raw call stacks are never logged. POST goes to `/diagnostics/report`.
///
/// **Wiring**: call `CrashReporter.shared.start()` from `AppServices.swift`
/// at app launch. See wiring snippet at the bottom of this file.
///
/// Implementation note: `MXMetricManagerSubscriber` requires `NSObject` inheritance.
/// We use a thin `NSObject` bridge (`CrashReporterDelegate`) that forwards to the
/// `actor` (`CrashReporterProcessor`) for safe async mutation.
public final class CrashReporter: @unchecked Sendable {

    // MARK: — Singleton

    public static let shared = CrashReporter()

    // MARK: — Internals

    private let processor: CrashReporterProcessor
    private let delegate: CrashReporterDelegate

    // MARK: — Init

    public init(
        apiClient: DiagnosticsAPIClientProtocol = LiveDiagnosticsAPIClient(),
        recovery: CrashRecovery = .shared
    ) {
        let proc = CrashReporterProcessor(apiClient: apiClient, recovery: recovery)
        self.processor = proc
        self.delegate = CrashReporterDelegate(processor: proc)
    }

    // MARK: — Lifecycle

    /// Register with MetricKit. Call once at app launch from `AppServices`.
    public func start() {
        MXMetricManager.shared.add(delegate)
    }

    /// Unregister from MetricKit. Called on deinit / test teardown.
    public func stop() {
        MXMetricManager.shared.remove(delegate)
    }
}

// MARK: — NSObject bridge (required by MXMetricManagerSubscriber)

/// `NSObject` wrapper that forwards MetricKit callbacks to `CrashReporterProcessor`.
final class CrashReporterDelegate: NSObject, MXMetricManagerSubscriber {

    private let processor: CrashReporterProcessor

    init(processor: CrashReporterProcessor) {
        self.processor = processor
    }

    /// Performance metrics payload — not used for crash reporting; ignored.
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Performance metrics are not part of the crash pipeline.
    }

    /// Diagnostic payloads (crash, hang, disk write, CPU).
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Serialize to Sendable value types synchronously on the calling thread
        // so we don't pass non-Sendable MXDiagnosticPayload across concurrency domains.
        var reports: [SerializedDiagnostic] = []
        var hasCrash = false
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                hasCrash = true
                reports.append(SerializedDiagnostic(type: "crash", rawJSON: Self.extractJSON(crash)))
            }
            for hang in payload.hangDiagnostics ?? [] {
                reports.append(SerializedDiagnostic(type: "hang", rawJSON: Self.extractJSON(hang)))
            }
            for dw in payload.diskWriteExceptionDiagnostics ?? [] {
                reports.append(SerializedDiagnostic(type: "disk_write_exception", rawJSON: Self.extractJSON(dw)))
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                reports.append(SerializedDiagnostic(type: "cpu_exception", rawJSON: Self.extractJSON(cpu)))
            }
        }
        let captured = reports
        let didCrash = hasCrash
        let proc = processor
        Task {
            await proc.process(captured, hasCrash: didCrash)
        }
    }

    private static func extractJSON(_ diagnostic: MXDiagnostic) -> String {
        (try? JSONSerialization.data(
            withJSONObject: diagnostic.dictionaryRepresentation(),
            options: []
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

// MARK: — Serialized intermediate (Sendable bridge)

/// A Sendable intermediate extracted on the MetricKit callback thread
/// before crossing into the actor.
struct SerializedDiagnostic: Sendable {
    let type: String
    let rawJSON: String
}

// MARK: — Processing actor

/// Actor responsible for processing serialized diagnostics and submitting reports.
actor CrashReporterProcessor {

    private var apiClient: DiagnosticsAPIClientProtocol
    private let recovery: CrashRecovery

    init(apiClient: DiagnosticsAPIClientProtocol, recovery: CrashRecovery) {
        self.apiClient = apiClient
        self.recovery = recovery
    }

    func process(_ diagnostics: [SerializedDiagnostic], hasCrash: Bool) async {
        if hasCrash {
            recovery.markCrashed()
        }
        for d in diagnostics {
            let report = DiagnosticReport(
                type: d.type,
                timestamp: Date(),
                payload: LogRedactor.redact(d.rawJSON)
            )
            await submit(report)
        }
    }

    private func submit(_ report: DiagnosticReport) async {
        do {
            try await apiClient.submitDiagnostic(report)
        } catch {
            AppLog.app.debug("CrashReporter: failed to submit diagnostic: \(error.localizedDescription)")
        }
    }
}

// MARK: — Supporting types

/// A redacted diagnostic report ready to POST to `/diagnostics/report`.
public struct DiagnosticReport: Codable, Sendable {
    public let type: String
    public let timestamp: Date
    /// Redacted JSON payload from `MXDiagnostic.dictionaryRepresentation()`.
    public let payload: String
}

/// Abstraction for the network call, enabling test substitution.
public protocol DiagnosticsAPIClientProtocol: Sendable {
    func submitDiagnostic(_ report: DiagnosticReport) async throws
}

/// Live implementation. Posts to the tenant's own server (data sovereignty preserved).
public struct LiveDiagnosticsAPIClient: DiagnosticsAPIClientProtocol {

    public init() {}

    public func submitDiagnostic(_ report: DiagnosticReport) async throws {
        let optedIn = UserDefaults.standard.bool(forKey: CrashReportingDefaults.enabledKey)
        guard optedIn else { return }

        guard let baseURLString = UserDefaults.standard.string(forKey: "com.bizarrecrm.apiBaseURL"),
              let baseURL = URL(string: baseURLString) else {
            return
        }
        let url = baseURL.appendingPathComponent("diagnostics/report")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(report)

        _ = try await URLSession.shared.data(for: request)
    }
}

// MARK: — AppServices wiring (DO NOT modify AppServices.swift directly)
//
// Add the following to `AppServices.swift` inside the `configure()` method:
//
//   // §32.5 Crash reporter — registers MetricKit subscriber
//   CrashReporter.shared.start()
//
// Then check the recovery flag after MetricKit has had a chance to deliver
// (e.g. in the root view's `.task`):
//
//   if CrashRecovery.shared.willRestartAfterCrash {
//       showCrashRecoverySheet = true
//       // CrashRecoverySheet calls clearCrashFlag() on dismiss
//   }
