import Foundation

// §32.5 Crash recovery pipeline — Breadcrumbs
// Phase 11

/// A single breadcrumb event recorded before a potential crash.
/// All messages are pre-redacted; no PII is stored.
public struct Breadcrumb: Codable, Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    /// Already redacted via `LogRedactor` before storage.
    public let message: String
    public let metadata: [String: String]?

    public init(
        timestamp: Date,
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: String]?
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}

/// Thread-safe ring buffer of the last 100 breadcrumbs.
///
/// All pushed messages are run through `LogRedactor` before storage.
/// Wire into `AppLog.log()` so every log line auto-pushes a crumb.
public actor BreadcrumbStore {

    // MARK: — Singleton

    public static let shared = BreadcrumbStore()

    // MARK: — State

    private var buffer: [Breadcrumb] = []
    private let capacity: Int

    // MARK: — Init

    public init(capacity: Int = 100) {
        self.capacity = capacity
    }

    // MARK: — Public API

    /// Append a redacted breadcrumb. Oldest entry is dropped when capacity is exceeded.
    public func push(_ crumb: Breadcrumb) async {
        let redactedMessage = LogRedactor.redact(crumb.message)
        let safe = Breadcrumb(
            timestamp: crumb.timestamp,
            level: crumb.level,
            category: crumb.category,
            message: redactedMessage,
            metadata: crumb.metadata
        )
        if buffer.count >= capacity {
            buffer.removeFirst()
        }
        buffer.append(safe)
    }

    /// Return the most recent `count` breadcrumbs (oldest first).
    public func recent(_ count: Int = 100) async -> [Breadcrumb] {
        let slice = buffer.suffix(count)
        return Array(slice)
    }

    /// Clear all stored breadcrumbs.
    public func clear() async {
        buffer.removeAll()
    }
}
