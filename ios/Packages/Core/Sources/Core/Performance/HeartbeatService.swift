import Foundation

// §32.9 Heartbeat — liveness ping to tenant server every 5 minutes while
// the app is in the foreground. Server uses these to compute daily/monthly
// active users without relying on third-party analytics SDKs.
//
// Wiring (AppServices.restoreSession or scene phase handler):
// ```swift
// HeartbeatService.shared.start(post: { data in
//     try await apiClient.post("/heartbeat", body: data, as: EmptyPayload.self)
// })
// ```
// Stop on logout / scene backgrounded:
// ```swift
// HeartbeatService.shared.stop()
// ```

// MARK: - HeartbeatService

/// Sends a liveness `POST /heartbeat` to the tenant server every 5 minutes
/// while the app is foregrounded.
///
/// - **Sovereignty:** payload goes to `APIClient.baseURL` only; no third-party.
/// - **Privacy:** no PII in the payload — just app metadata + opaque session ID.
/// - **Foreground only:** timer suspended on background / logout; resumed on next `start()`.
public actor HeartbeatService {

    // MARK: — Singleton

    public static let shared = HeartbeatService()

    // MARK: — Configuration

    /// Interval between heartbeat pings.
    public static let interval: TimeInterval = 5 * 60 // 5 minutes

    // MARK: — Internals

    private var task: Task<Void, Never>?
    private var post: (@Sendable (HeartbeatPayload) async throws -> Void)?

    // MARK: — Init

    /// Private production init — use `HeartbeatService.shared` at app level.
    /// Tests use the `@testable` accessor to create isolated instances.
    init() {}

    // MARK: — Lifecycle

    /// Start the heartbeat loop. Calling `start` while already running is a no-op
    /// (the existing loop continues uninterrupted).
    ///
    /// - Parameter post: Closure that delivers each `HeartbeatPayload` to the server.
    ///   Inject via `APIClient.post("/heartbeat", body:, as:)` from `AppServices`.
    public func start(post: @escaping @Sendable (HeartbeatPayload) async throws -> Void) {
        // If already running with the same closure, leave it running.
        guard task == nil else { return }
        self.post = post
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    /// Stop the heartbeat loop. Call on logout or scene backgrounded.
    public func stop() {
        task?.cancel()
        task = nil
        post = nil
    }

    // MARK: — Private loop

    private func loop() async {
        // Fire immediately on start (records "app opened" effectively).
        await ping()
        // Then fire every `interval` seconds until cancelled.
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(HeartbeatService.interval * 1_000_000_000))
            } catch {
                // Task.sleep throws on cancellation — exit cleanly.
                break
            }
            guard !Task.isCancelled else { break }
            await ping()
        }
    }

    private func ping() async {
        guard let post else { return }
        let payload = HeartbeatPayload()
        do {
            try await post(payload)
            AppLog.perf.debug("Heartbeat sent (§32.9)")
        } catch {
            // Fire-and-forget; log but never crash.
            AppLog.perf.info("Heartbeat failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - HeartbeatPayload

/// Minimal liveness payload — no PII; server computes DAU/MAU from session counts.
public struct HeartbeatPayload: Codable, Sendable {
    /// Monotonically-increasing UTC timestamp. Server uses this to detect
    /// clock skew between device and server.
    public let timestamp: String

    /// App version from bundle (e.g. "1.2.3"). Lets server compute version distribution.
    public let appVersion: String

    /// iOS version (e.g. "18.3.1"). Useful for deprecation planning.
    public let osVersion: String

    public init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp  = formatter.string(from: Date())
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        self.osVersion  = ProcessInfo.processInfo.operatingSystemVersionString
    }
}
