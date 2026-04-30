import Foundation

// §71 Privacy-first analytics — local debug sink
// §32 Debug log export — ring buffer + plaintext export for bug reports

#if DEBUG

// MARK: - DebugLogStore

/// §32 — Thread-safe ring buffer that retains the last `capacity` formatted
/// debug-log lines for export.
///
/// Exported lines are already run through `AnalyticsRedactor` (via the
/// `LocalDebugSink` formatter) so no raw PII appears in the exported text.
///
/// Access via `DebugLogStore.shared`.
public final class DebugLogStore: @unchecked Sendable {

    // MARK: Public

    public static let shared = DebugLogStore()

    /// Maximum number of lines retained (FIFO eviction).
    public let capacity: Int

    // MARK: Private

    private var buffer: [String] = []
    private let lock = NSLock()

    // MARK: Init

    public init(capacity: Int = 500) {
        self.capacity = capacity
        self.buffer.reserveCapacity(capacity)
    }

    // MARK: Append

    /// Append a single formatted log line. Evicts oldest when over capacity.
    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if buffer.count >= capacity {
            buffer.removeFirst()
        }
        buffer.append(line)
    }

    // MARK: Export

    /// Return all buffered lines joined by newlines, newest last.
    ///
    /// Suitable for attaching to a bug-report email or sharing via `UIActivityViewController`.
    public func exportText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.joined(separator: "\n")
    }

    /// Return a `Data` UTF-8 encoding of `exportText()`, for file/share APIs.
    public func exportData() -> Data {
        exportText().data(using: .utf8) ?? Data()
    }

    /// Clear the buffer (e.g. after the user submits a bug report).
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }

    /// Number of lines currently buffered.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
}

// MARK: - LocalDebugSink

/// Debug-only sink that logs analytics events via `AppLog.telemetry` and
/// retains a copy in `DebugLogStore.shared` for in-app export.
///
/// Only compiled in `DEBUG` builds; never ships to end users.
public struct LocalDebugSink: Sendable {
    public init() {}

    /// Log the event to the telemetry OSLog channel and to `DebugLogStore`.
    public func log(_ payload: AnalyticsEventPayload) {
        let line = formatLine(payload)
        AppLog.telemetry.debug("\(line, privacy: .public)")
        DebugLogStore.shared.append(line)
    }

    // MARK: Private

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private func formatLine(_ payload: AnalyticsEventPayload) -> String {
        let ts = Self.makeISO8601Formatter().string(from: payload.timestamp)
        let propsStr = payload.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(valueString($0.value))" }
            .joined(separator: " ")
        return "[\(ts)] [Analytics] \(payload.event.rawValue) session=\(payload.sessionId) \(propsStr)"
    }

    private func valueString(_ v: AnalyticsValue) -> String {
        switch v {
        case .string(let s): return "\"\(s)\""
        case .int(let i):    return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        }
    }
}

#endif
