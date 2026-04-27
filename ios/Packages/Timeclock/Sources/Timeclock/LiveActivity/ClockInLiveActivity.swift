import Foundation
#if canImport(ActivityKit)
import ActivityKit

// MARK: - ClockInLiveActivity
//
// §14.3 Live Activity — "Clocked in since 9:14 AM" on Lock Screen until clock-out.
//
// Requires `NSSupportsLiveActivities` in Info.plist (set in write-info-plist.sh).
// Entitlement: no additional entitlement needed on iOS 16.1+; Live Activities are
// controlled via `NSSupportsLiveActivities` key only.
//
// Architecture:
//   ClockInAttributes   — the static portion (employee name)
//   ClockInAttributes.ContentState — the dynamic portion (clock-in time, elapsed)
//
// The Live Activity is started by `ClockInLiveActivityManager.start(employee:clockInDate:)`
// when the timeclock state transitions to `.active`.
// It is ended by `ClockInLiveActivityManager.end()` on clock-out.

// MARK: - Attributes

public struct ClockInAttributes: ActivityAttributes, Sendable {
    public typealias ContentState = ClockState

    public struct ClockState: Codable, Hashable, Sendable {
        /// ISO-8601 string of the clock-in moment.
        public let clockInDate: Date
        /// Running elapsed seconds; update periodically for the dynamic island.
        public let elapsedSeconds: Int

        public init(clockInDate: Date, elapsedSeconds: Int) {
            self.clockInDate = clockInDate
            self.elapsedSeconds = elapsedSeconds
        }
    }

    /// Employee display name shown in the compact leading slot.
    public let employeeName: String

    public init(employeeName: String) {
        self.employeeName = employeeName
    }
}

// MARK: - Manager

@MainActor
public final class ClockInLiveActivityManager {
    private var activity: Activity<ClockInAttributes>?

    public static let shared = ClockInLiveActivityManager()
    private init() {}

    /// Start a Live Activity when the employee clocks in.
    public func start(employeeName: String, clockInDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ClockInAttributes(employeeName: employeeName)
        let state = ClockInAttributes.ClockState(
            clockInDate: clockInDate,
            elapsedSeconds: 0
        )
        let content = ActivityContent(
            state: state,
            staleDate: Calendar.current.date(byAdding: .hour, value: 12, to: clockInDate)
        )
        do {
            activity = try Activity<ClockInAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activities unavailable (e.g. iPhone in Low Power Mode or simulator).
            // Non-fatal — the app continues normally.
        }
    }

    /// Update elapsed time on the Live Activity (call every 30s from `ClockInOutTile`).
    public func tick(clockInDate: Date) async {
        guard let activity else { return }
        let elapsed = Int(Date().timeIntervalSince(clockInDate))
        let newState = ClockInAttributes.ClockState(
            clockInDate: clockInDate,
            elapsedSeconds: elapsed
        )
        await activity.update(using: newState)
    }

    /// End the Live Activity when the employee clocks out.
    public func end(clockInDate: Date) async {
        guard let activity else { return }
        let finalState = ClockInAttributes.ClockState(
            clockInDate: clockInDate,
            elapsedSeconds: Int(Date().timeIntervalSince(clockInDate))
        )
        await activity.end(using: finalState, dismissalPolicy: .immediate)
        self.activity = nil
    }
}

#endif // canImport(ActivityKit)
