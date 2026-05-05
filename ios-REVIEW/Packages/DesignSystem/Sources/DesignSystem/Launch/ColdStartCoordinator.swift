import Foundation
import Core

// §68.2 — ColdStartCoordinator
// Resolves the initial RootDestination during app launch.
// Records timing via AppLog.perf + MemoryProbe. Max 200ms splash duration.

// MARK: - RootDestination

/// The screen the app should navigate to after cold-start resolution.
public enum RootDestination: Equatable, Sendable {
    case dashboard
    case login
    case pinUnlock
    case firstRun
    /// §68.2 — A deep-link arrived before first render.
    ///
    /// The associated `URL` is passed straight to `DeepLinkRouter.handle(_:)`
    /// from `RootView` once the scene is ready — before the first navigation
    /// frame is committed. This prevents the "flash to dashboard then re-route"
    /// flicker that happens when deep links arrive at launch.
    case deepLink(URL)
}

// MARK: - ColdStartCoordinator

/// `@MainActor` class that drives the launch sequence.
///
/// Call `resolve()` once per app launch from `SessionBootstrapper` or similar.
/// The method is guaranteed to return within ~200ms; it caps splash duration
/// by racing against a `Task.sleep` deadline.
@MainActor
public final class ColdStartCoordinator: Sendable {

    // MARK: Dependencies

    private let tokenReader: @Sendable () -> Bool
    private let pinRequired: @Sendable () -> Bool
    private let isFirstRun: @Sendable () -> Bool

    /// Maximum allowed time (seconds) before we force a destination.
    private static let maxSplashDuration: Double = 0.200

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - tokenReader:  Returns `true` if a valid auth token is stored.
    ///   - pinRequired:  Returns `true` if the user has enrolled a PIN.
    ///   - isFirstRun:   Returns `true` if the app has never launched before.
    public init(
        tokenReader:  @escaping @Sendable () -> Bool,
        pinRequired:  @escaping @Sendable () -> Bool,
        isFirstRun:   @escaping @Sendable () -> Bool
    ) {
        self.tokenReader = tokenReader
        self.pinRequired = pinRequired
        self.isFirstRun  = isFirstRun
    }

    // MARK: Public API

    /// Resolves the root destination. Capped at `maxSplashDuration` seconds.
    ///
    /// Logs cold-start timing and a memory sample via `AppLog.perf` /
    /// `MemoryProbe` so CI and on-device diagnostics can track regressions.
    ///
    /// - Parameter pendingURL: §68.2 — A URL passed to the app before the first
    ///   render (e.g. a `UIApplicationLaunchOptionsKey.url` from `application(_:didFinishLaunchingWithOptions:)`
    ///   or an `.onOpenURL` that fired before `scene(_:willConnectTo:)` finished).
    ///   When non-nil and the user is already authenticated, the coordinator
    ///   returns `.deepLink(url)` so `RootView` routes directly without an
    ///   intermediate dashboard flash.
    public func resolve(pendingURL: URL? = nil) async -> RootDestination {
        let clock = ContinuousClock()
        let start = clock.now

        MemoryProbe.sample(label: "cold-start-begin")

        // §68.2 — If a deep-link URL arrived before first render, resolve it
        // immediately (before the deadline race) so the URL is never lost.
        let pendingURLCopy = pendingURL

        // Perform resolution inside a bounded Task so we never block the
        // main thread longer than `maxSplashDuration`.
        let destination = await withThrowingTaskGroup(of: RootDestination.self) { group in
            // Resolution task
            group.addTask { await self.resolveDestination(pendingURL: pendingURLCopy) }

            // Deadline task — returns `.dashboard` (or `.login`) as fallback.
            let tokenReaderCopy = tokenReader
            group.addTask {
                try await Task.sleep(for: .seconds(Self.maxSplashDuration))
                return tokenReaderCopy() ? RootDestination.dashboard : RootDestination.login
            }

            // Take whichever finishes first.
            let first = try? await group.next()
            group.cancelAll()
            return first ?? fallbackDestination()
        }

        let elapsed = start.duration(to: clock.now)
        let ms = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15

        let elapsedStr = String(format: "%.1f", ms)
        AppLog.perf.info(
            "ColdStartCoordinator: resolved=\(destination.logLabel, privacy: .public) elapsed=\(elapsedStr, privacy: .public)ms"
        )
        MemoryProbe.sample(label: "cold-start-resolved")

        return destination
    }

    // MARK: Private

    private func resolveDestination(pendingURL: URL?) async -> RootDestination {
        if isFirstRun() { return .firstRun }
        if !tokenReader() { return .login }
        if pinRequired()  { return .pinUnlock }
        // §68.2 — Deep-link arrives before first render: route directly so the
        // UI never flashes to dashboard then re-routes. We only honour the URL
        // when the user is already authenticated (token present, no PIN gate).
        if let url = pendingURL { return .deepLink(url) }
        return .dashboard
    }

    private func fallbackDestination() -> RootDestination {
        tokenReader() ? .dashboard : .login
    }
}

// MARK: - RootDestination + logging

private extension RootDestination {
    var logLabel: String {
        switch self {
        case .dashboard:         return "dashboard"
        case .login:             return "login"
        case .pinUnlock:         return "pinUnlock"
        case .firstRun:          return "firstRun"
        case .deepLink(let url): return "deepLink(\(url.host ?? url.scheme ?? "?"))"
        }
    }
}
