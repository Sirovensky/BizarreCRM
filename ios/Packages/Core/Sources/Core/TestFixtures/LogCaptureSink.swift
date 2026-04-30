#if DEBUG
import Foundation

// §31 Test-only logger seam — LogCaptureSink
//
// Problem: `AppLog` loggers are OS_log `Logger` instances; OS_log output goes to
// the unified logging system and cannot be inspected in-process during unit tests.
//
// Solution: A seam-based capture sink.  Production code that wants to remain
// testable accepts a `LogSink` protocol instead of calling `AppLog.*` directly.
// In tests, swap in a `LogCaptureSink`; in production use `OSLogSink`.
//
// Design goals:
//  - Zero allocation in the `OSLogSink` hot path (just forwards to Logger).
//  - `LogCaptureSink` is `@unchecked Sendable` via an internal lock — safe for
//    concurrent tests but intentionally NOT for production use.
//  - Simple API: `sink.captured` returns all logged entries; `sink.reset()` clears.
//
// Usage in tests:
// ```swift
// let sink = LogCaptureSink()
// myService.logSink = sink
// myService.doWork()
// XCTAssertTrue(sink.captured.contains { $0.message.contains("expected phrase") })
// ```

// MARK: - LogSink protocol

/// Abstraction over the log output channel.
///
/// Production code that wants unit-testable logging should accept a `LogSink`
/// dependency rather than hard-coding `AppLog.*` calls.
public protocol LogSink: Sendable {
    /// Emit a log message at the given level.
    ///
    /// - Parameters:
    ///   - level:    Severity level of the message.
    ///   - message:  The formatted log message string.
    ///   - category: The subsystem category (mirrors `AppLog` category names).
    func log(level: CaptureLogLevel, message: String, category: String)
}

// MARK: - CaptureLogLevel

/// Severity levels mirroring OSLog levels used in BizarreCRM.
public enum CaptureLogLevel: Int, Comparable, Sendable, CustomStringConvertible {
    case debug   = 0
    case info    = 1
    case notice  = 2
    case error   = 3
    case fault   = 4

    public static func < (lhs: CaptureLogLevel, rhs: CaptureLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .debug:  return "DEBUG"
        case .info:   return "INFO"
        case .notice: return "NOTICE"
        case .error:  return "ERROR"
        case .fault:  return "FAULT"
        }
    }
}

// MARK: - LogEntry

/// A single captured log entry.
public struct LogEntry: Sendable, CustomStringConvertible {
    public let level:    CaptureLogLevel
    public let message:  String
    public let category: String

    public var description: String {
        "[\(level)] [\(category)] \(message)"
    }
}

// MARK: - LogCaptureSink

/// An in-memory log sink for use in unit tests.
///
/// Thread-safe via `NSLock`; safe to use from concurrent test bodies.
/// **Never use in production** — this type is gated behind `#if DEBUG`.
///
/// Usage:
/// ```swift
/// let sink = LogCaptureSink()
/// subject.logSink = sink
/// subject.doWork()
///
/// // Assert
/// XCTAssertEqual(sink.captured.count, 1)
/// XCTAssertEqual(sink.captured[0].level, .error)
/// XCTAssertTrue(sink.captured[0].message.contains("expected"))
///
/// // Reset between test cases
/// sink.reset()
/// ```
public final class LogCaptureSink: LogSink, @unchecked Sendable {

    // MARK: — State

    private var _entries: [LogEntry] = []
    private let lock = NSLock()

    // MARK: — Init

    public init() {}

    // MARK: — LogSink

    public func log(level: CaptureLogLevel, message: String, category: String) {
        lock.lock()
        _entries.append(LogEntry(level: level, message: message, category: category))
        lock.unlock()
    }

    // MARK: — Public read access

    /// All captured log entries since the last `reset()`, in chronological order.
    public var captured: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    /// Entries matching a given minimum severity level.
    public func entries(atOrAbove level: CaptureLogLevel) -> [LogEntry] {
        captured.filter { $0.level >= level }
    }

    /// Entries matching a specific category string.
    public func entries(category: String) -> [LogEntry] {
        captured.filter { $0.category == category }
    }

    /// Convenience: returns `true` if any captured entry contains `substring`.
    public func contains(substring: String) -> Bool {
        captured.contains { $0.message.contains(substring) }
    }

    /// Convenience: returns `true` if any captured entry at `level` contains `substring`.
    public func contains(level: CaptureLogLevel, substring: String) -> Bool {
        captured.contains { $0.level == level && $0.message.contains(substring) }
    }

    // MARK: — Reset

    /// Clears all captured entries.  Call in `tearDown()` between test cases.
    public func reset() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
    }
}

// MARK: - NullLogSink

/// A sink that discards all messages.
///
/// Use as a default dependency value in production code that accepts a `LogSink`,
/// replacing it with `LogCaptureSink` only in tests.
public struct NullLogSink: LogSink {
    public init() {}
    public func log(level: CaptureLogLevel, message: String, category: String) {}
}
#endif
