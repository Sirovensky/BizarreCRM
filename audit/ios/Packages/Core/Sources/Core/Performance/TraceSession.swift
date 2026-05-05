import Foundation
import OSLog

// §29 Performance instrumentation — actor-backed in-flight signpost tracker.
//
// `TraceSession` serialises access to a dictionary of in-flight measurements
// so that concurrent `begin` / `end` calls from any Task are safe in Swift 6.

/// An `actor` that tracks in-flight performance intervals.
///
/// Each call to ``begin(_:)`` records a start instant and returns a token.
/// The matching ``end(_:token:)`` call finalises the interval, emits the
/// signpost, and returns the elapsed time in milliseconds.
///
/// ```swift
/// let session = TraceSession()
/// let token = await session.begin(.launchTTI)
/// // … async work …
/// let ms = await session.end(.launchTTI, token: token)
/// ```
public actor TraceSession {

    // MARK: - Types

    /// Opaque token identifying a single in-flight interval.
    public struct Token: Hashable, Sendable {
        let id: UUID
        let signpostID: OSSignpostID

        init(signpostID: OSSignpostID) {
            self.id = UUID()
            self.signpostID = signpostID
        }

        public static func == (lhs: Token, rhs: Token) -> Bool {
            lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Stored state

    /// In-flight intervals: token → (operation, start instant).
    private var inflight: [Token: (PerformanceOperation, ContinuousClock.Instant)] = [:]

    // MARK: - Lifecycle

    public init() {}

    // MARK: - Public API

    /// Begins a new performance interval for `operation`.
    ///
    /// - Parameter operation: The operation being instrumented.
    /// - Returns: A `Token` that must be passed to the matching ``end(_:token:)`` call.
    public func begin(_ operation: PerformanceOperation) -> Token {
        let signpostID = PerformanceMeasurement.begin(operation)
        let token = Token(signpostID: signpostID)
        inflight[token] = (operation, ContinuousClock().now)
        return token
    }

    /// Ends the interval identified by `token`.
    ///
    /// If `token` is not found (e.g. already ended or never begun) the method
    /// is a no-op and returns `nil`.
    ///
    /// - Parameters:
    ///   - operation: Must match the operation passed to ``begin(_:)``.
    ///   - token: The token returned by the matching ``begin(_:)`` call.
    /// - Returns: Elapsed time in milliseconds, or `nil` if the token was unknown.
    @discardableResult
    public func end(_ operation: PerformanceOperation, token: Token) -> Double? {
        guard let (_, startedAt) = inflight.removeValue(forKey: token) else {
            AppLog.perf.warning(
                "[TraceSession] end called with unknown token for \(operation.rawValue, privacy: .public)"
            )
            return nil
        }
        let elapsedMs = PerformanceMeasurement.end(operation, id: token.signpostID, startedAt: startedAt)
        BudgetGuard.check(operation, elapsedMs: elapsedMs)
        return elapsedMs
    }

    /// Returns the number of currently in-flight intervals.
    ///
    /// Useful for assertions in tests.
    public var inflightCount: Int { inflight.count }
}
