import Foundation

/// §2 Session timeout — idle-based session expiry timer.
///
/// Usage:
/// ```swift
/// let timer = SessionTimer(idleTimeout: 15 * 60, onExpire: { await signOut() })
/// // On every UI interaction:
/// await timer.touch()
/// // In Settings flow:
/// await timer.pause()
/// await timer.resume()
/// ```
///
/// The timer fires `onWarning` when 80% of `idleTimeout` has elapsed
/// (e.g. at 12 min for a 15 min timeout), then `onExpire` at 100%.
public actor SessionTimer {

    // MARK: - Public state

    /// When false the timer is paused and will not expire.
    public private(set) var isRunning: Bool = false

    // MARK: - Configuration

    private let idleTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let onExpire: @Sendable () async -> Void
    private let onWarning: (@Sendable () async -> Void)?

    // MARK: - Internal state

    private var deadline: Date = .distantFuture
    private var warningSent: Bool = false
    private var runLoop: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - idleTimeout:  Seconds of inactivity before expiry. Default: 15 minutes.
    ///   - pollInterval: How often to check the deadline. Default 1 s; use a
    ///                   shorter value in tests with short timeouts.
    ///   - onWarning:    Called when 80% of the idle window has elapsed (optional).
    ///   - onExpire:     Called when the full idle window has elapsed.
    public init(
        idleTimeout: TimeInterval = 15 * 60,
        pollInterval: TimeInterval = 1.0,
        onWarning: (@Sendable () async -> Void)? = nil,
        onExpire: @Sendable @escaping () async -> Void
    ) {
        self.idleTimeout = idleTimeout
        self.pollInterval = pollInterval
        self.onWarning = onWarning
        self.onExpire = onExpire
    }

    // MARK: - Public API

    /// Start (or restart) the idle countdown.
    public func start() {
        isRunning = true
        resetDeadline()
        warningSent = false
        scheduleLoop()
    }

    /// Reset the idle countdown — call from any UI interaction.
    public func touch() {
        guard isRunning else { return }
        resetDeadline()
        warningSent = false
    }

    /// Pause the countdown.
    public func pause() {
        isRunning = false
        runLoop?.cancel()
        runLoop = nil
    }

    /// Resume after pause. The full `idleTimeout` is granted from now.
    public func resume() {
        guard !isRunning else { return }
        isRunning = true
        resetDeadline()
        warningSent = false
        scheduleLoop()
    }

    /// How many seconds remain before the session expires.
    /// Returns `idleTimeout` when paused (the full window would restart on resume).
    public func currentRemaining() -> TimeInterval {
        guard isRunning else { return idleTimeout }
        return max(0, deadline.timeIntervalSinceNow)
    }

    // MARK: - Private

    private func resetDeadline() {
        deadline = Date(timeIntervalSinceNow: idleTimeout)
    }

    private func scheduleLoop() {
        runLoop?.cancel()
        let intervalNS = UInt64(pollInterval * 1_000_000_000)
        runLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNS)
                guard !Task.isCancelled, let self else { return }

                let remaining = await self.currentRemaining()
                let didWarn   = await self.warningSent
                let threshold = await self.warningThreshold()

                if !didWarn && remaining <= threshold {
                    await self.triggerWarning()
                }

                if remaining <= 0 {
                    await self.triggerExpiry()
                    return
                }
            }
        }
    }

    private func warningThreshold() -> TimeInterval { idleTimeout * 0.2 }

    private func triggerWarning() async {
        guard let cb = onWarning, !warningSent else { return }
        warningSent = true
        await cb()
    }

    private func triggerExpiry() async {
        isRunning = false
        runLoop?.cancel()
        runLoop = nil
        await onExpire()
    }
}
