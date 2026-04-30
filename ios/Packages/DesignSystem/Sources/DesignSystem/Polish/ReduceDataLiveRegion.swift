import SwiftUI
import Combine

// §26 / §67 — ReduceDataLiveRegion
// "Reduce Data" (Settings → Accessibility → Per-App Settings → Low Data Mode,
// or iOS Low Power Mode implications) means live-region announcements can fire
// very frequently when data refreshes are rapid (e.g. ticket-count badge ticking
// up from a push-notification stream).
//
// This modifier:
//   1. Observes `UIAccessibility.isVoiceOverRunning` — only posts announcements
//      when VoiceOver is active (avoids useless work).
//   2. Throttles `UIAccessibility.post(notification: .announcement, argument:)`
//      to at most once per `interval` (default 2 s) so rapid updates don't spam
//      the user with announcements.
//   3. Applies an additional 5-second throttle when `isReduceMotionEnabled` is
//      true (used as a proxy signal for "prefer quieter UI") or when the device
//      is in Low Power Mode.
//
// This is a live-region throttle, not an Announcements gate — the view still
// updates its content every time; only the VoiceOver spoken announcement is
// rate-limited.

// MARK: - ReduceDataLiveRegionModifier

/// Posts a VoiceOver `announcement` notification at most once per `interval`,
/// throttled further when the device is in Low Power Mode or Reduce Motion is on.
///
/// The view's visual content updates immediately on every `value` change.
///
/// **Usage:**
/// ```swift
/// Text("Open tickets: \(openCount)")
///     .reduceDataLiveRegion(announcement: "Open tickets: \(openCount)", value: openCount)
/// ```
public struct ReduceDataLiveRegionModifier<V: Equatable>: ViewModifier {

    // MARK: - Configuration

    /// The string VoiceOver speaks when the throttle allows.
    public let announcement: String
    /// The value whose change triggers a (throttled) announcement.
    public let value: V
    /// Base minimum interval between announcements.
    public let baseInterval: TimeInterval
    /// Multiplied onto `baseInterval` when in low-power / reduce-motion mode.
    public let quietMultiplier: TimeInterval

    // MARK: - State

    @State private var lastAnnouncedAt: Date = .distantPast
    @State private var isLowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isReduceMotion: Bool = UIAccessibility.isReduceMotionEnabled

    // MARK: - Init

    public init(
        announcement: String,
        value: V,
        baseInterval: TimeInterval = 2.0,
        quietMultiplier: TimeInterval = 2.5
    ) {
        self.announcement = announcement
        self.value = value
        self.baseInterval = baseInterval
        self.quietMultiplier = quietMultiplier
    }

    // MARK: - Computed

    private var effectiveInterval: TimeInterval {
        (isLowPower || isReduceMotion) ? baseInterval * quietMultiplier : baseInterval
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, _ in
                postAnnouncementIfAllowed()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSProcessInfoPowerStateDidChange
                )
            ) { _ in
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIAccessibility.reduceMotionStatusDidChangeNotification
                )
            ) { _ in
                isReduceMotion = UIAccessibility.isReduceMotionEnabled
            }
    }

    // MARK: - Private

    private func postAnnouncementIfAllowed() {
        guard UIAccessibility.isVoiceOverRunning else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnnouncedAt) >= effectiveInterval else { return }

        lastAnnouncedAt = now
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

// MARK: - View extension

public extension View {

    /// Attaches a throttled VoiceOver live-region announcement to this view.
    ///
    /// The announcement fires at most once per `baseInterval` (default 2 s),
    /// stretched to `baseInterval × quietMultiplier` when Low Power Mode or
    /// Reduce Motion is enabled. No announcement is posted when VoiceOver is
    /// not running — the check is free.
    ///
    /// - Parameters:
    ///   - announcement: Text VoiceOver will speak.
    ///   - value: Equatable value — a change triggers the (throttled) post.
    ///   - baseInterval: Minimum seconds between announcements. Default: 2.0.
    ///   - quietMultiplier: Multiplier applied in low-power / reduce-motion mode. Default: 2.5.
    func reduceDataLiveRegion<V: Equatable>(
        announcement: String,
        value: V,
        baseInterval: TimeInterval = 2.0,
        quietMultiplier: TimeInterval = 2.5
    ) -> some View {
        modifier(
            ReduceDataLiveRegionModifier(
                announcement: announcement,
                value: value,
                baseInterval: baseInterval,
                quietMultiplier: quietMultiplier
            )
        )
    }
}
