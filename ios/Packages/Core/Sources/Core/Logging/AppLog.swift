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
}
