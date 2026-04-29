import Foundation
import OSLog

// §32 Logging strategy
// Phase 0 foundation — moved from Core/AppLog.swift into Core/Logging/AppLog.swift.
// Public API is IDENTICAL to the original file; all callers continue to compile unchanged.

public enum AppLog {
    private static let subsystem = "com.bizarrecrm"

    // MARK: — Per-category loggers (existing public API — do not rename)

    public static let app         = Logger(subsystem: subsystem, category: "app")
    public static let auth        = Logger(subsystem: subsystem, category: "auth")
    public static let networking  = Logger(subsystem: subsystem, category: "networking")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let sync        = Logger(subsystem: subsystem, category: "sync")
    public static let ws          = Logger(subsystem: subsystem, category: "websocket")
    public static let pos         = Logger(subsystem: subsystem, category: "pos")
    public static let hardware    = Logger(subsystem: subsystem, category: "hardware")
    public static let ui          = Logger(subsystem: subsystem, category: "ui")
    public static let perf        = Logger(subsystem: subsystem, category: "performance")
    public static let telemetry      = Logger(subsystem: subsystem, category: "telemetry")
    /// §32 Background-task category (`bg`).
    public static let bg             = Logger(subsystem: subsystem, category: "bg")
    /// §32 Database category (`db`).
    public static let db             = Logger(subsystem: subsystem, category: "db")
    /// §91.1 §91.14 — SMS / Communications decode + pipeline errors.
    public static let communications = Logger(subsystem: subsystem, category: "communications")
    /// §32.1 — Reports generation, chart-data fetch, export pipeline.
    public static let reports        = Logger(subsystem: subsystem, category: "reports")
    /// §32.1 — Push + in-app notification delivery and permission state.
    public static let notifications  = Logger(subsystem: subsystem, category: "notifications")
    /// §32.1 — Inbound/outbound SMS routing distinct from full communications pipeline.
    public static let sms            = Logger(subsystem: subsystem, category: "sms")
    /// §4.4 — Audit-trail events: save, reassign, archive, transition.
    /// These entries mirror what the server writes to the audit log; the local
    /// category lets us correlate client-initiated changes with server timeline
    /// events when debugging sync gaps.
    public static let audit          = Logger(subsystem: subsystem, category: "audit")
    /// §32 — Payment processing: card-present, card-not-present, refunds, voids.
    public static let payments       = Logger(subsystem: subsystem, category: "payments")
    /// §32 / §57 — Field-service GPS location tracking pipeline.
    public static let location       = Logger(subsystem: subsystem, category: "location")

    // MARK: — §32.6 PII redaction helper (new)

    /// Return a copy of `input` with PII patterns replaced before logging.
    ///
    /// Usage:
    /// ```swift
    /// AppLog.networking.info("\(AppLog.redacted(rawUrl), privacy: .public)")
    /// ```
    public static func redacted(_ input: String) -> String {
        LogRedactor.redact(input)
    }

    // MARK: — §32.1 OSSignposter helpers

    /// OSSignposter for sync cycles — wire to Instruments Time Profiler.
    ///
    /// Usage:
    /// ```swift
    /// let id = AppLog.Signpost.sync.begin("sync_cycle")
    /// defer { AppLog.Signpost.sync.end("sync_cycle", id) }
    /// ```
    public enum Signpost {
        public static let sync        = OSSignposter(subsystem: subsystem, category: "sync")
        public static let api         = OSSignposter(subsystem: subsystem, category: "networking")
        public static let listRender  = OSSignposter(subsystem: subsystem, category: "ui")
        public static let dbWrite     = OSSignposter(subsystem: subsystem, category: "db")
        public static let imageLoad   = OSSignposter(subsystem: subsystem, category: "ui")
    }
}
