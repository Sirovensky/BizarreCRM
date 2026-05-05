import Foundation

// §29.11 Battery — WebSocket ping cadence.
//
// Default 25 s matches the §29.11 budget (not the iOS-default 5 s, which
// would burn battery for no benefit on LTE radios). Connection-state
// upgrades pause pings entirely when Low Power Mode is on — the OS keeps
// the socket alive aggressively for shorter windows so per-app heartbeats
// add nothing on top.

/// Centralised cadence for WebSocket heartbeat pings.
///
/// Treat this as a token: WebSocket clients should read `interval(now:)`
/// rather than embedding their own constants. Returns a `TimeInterval`
/// suitable for `DispatchQueue.asyncAfter` / `Task.sleep`.
public enum WebSocketPingPolicy {

    /// Standard heartbeat — 25 s per §29.11.
    public static let standard: TimeInterval = 25

    /// Reduced cadence when the device is conserving power — 90 s.
    /// Long enough that idle radios stay parked; short enough that an
    /// LB doesn't cull the connection on a 120 s read timeout.
    public static let lowPowerMode: TimeInterval = 90

    /// Returns the appropriate interval for the current device state.
    ///
    /// `@MainActor` because it reads `LowPowerModeObserver.shared`.
    @MainActor
    public static func currentInterval() -> TimeInterval {
        LowPowerModeObserver.shared.isEnabled ? lowPowerMode : standard
    }
}
