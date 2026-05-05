import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - IdleState

public enum IdleState: Sendable, Equatable {
    case active
    case dimmed    // 50% opacity overlay after dimAfterSeconds
    case blackout  // fully black after blackoutAfterSeconds
}

// MARK: - KioskIdleMonitor

/// §55 Idle timer and burn-in monitor.
/// Tracks user activity and signals dim / blackout states.
@Observable
@MainActor
public final class KioskIdleMonitor {
    // MARK: - Public state

    public private(set) var idleState: IdleState = .active

    // MARK: - Config

    public var dimAfterSeconds: TimeInterval
    public var blackoutAfterSeconds: TimeInterval

    // MARK: - Private

    private var lastActivityTime: Date = Date()
    private var timer: Timer?
    private let tickInterval: TimeInterval = 5.0

    // MARK: - Init

    public init(dimAfterSeconds: TimeInterval = 120, blackoutAfterSeconds: TimeInterval = 300) {
        self.dimAfterSeconds = dimAfterSeconds
        self.blackoutAfterSeconds = blackoutAfterSeconds
    }

    // MARK: - Control

    public func start() {
        lastActivityTime = Date()
        idleState = .active
        scheduleTimer()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        idleState = .active
    }

    public func recordActivity() {
        lastActivityTime = Date()
        if idleState != .active {
            idleState = .active
        }
    }

    // MARK: - Private

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        applyElapsed(elapsed)
    }

    /// Internal entry point for unit tests that need to simulate arbitrary idle
    /// durations without waiting for real wall-clock time.
    func simulateElapsed(_ elapsed: TimeInterval) {
        applyElapsed(elapsed)
    }

    private func applyElapsed(_ elapsed: TimeInterval) {
        let newState: IdleState
        if elapsed >= blackoutAfterSeconds {
            newState = .blackout
        } else if elapsed >= dimAfterSeconds {
            newState = .dimmed
        } else {
            newState = .active
        }
        if newState != idleState {
            idleState = newState
        }
    }
}
