import Foundation
import UserNotifications
import Core

// MARK: - DigestTime

/// A wall-clock time (hour + minute) for daily digest delivery.
public struct DigestTime: Sendable, Codable, Equatable {
    public let hour: Int     // 0–23
    public let minute: Int   // 0–59

    public init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    public static let defaultMorning = DigestTime(hour: 9, minute: 0)

    public var displayString: String {
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}

// MARK: - DigestPolicy

/// Per-category include/exclude for daily digest.
/// Immutable — always copy-on-write via `includingCategory` / `excludingCategory`.
public struct DigestPolicy: Sendable, Equatable {
    public let sendTime: DigestTime
    public let includedCategories: Set<EventCategory>
    public let isEnabled: Bool

    public init(
        sendTime: DigestTime = .defaultMorning,
        includedCategories: Set<EventCategory> = Set(EventCategory.allCases),
        isEnabled: Bool = true
    ) {
        self.sendTime = sendTime
        self.includedCategories = includedCategories
        self.isEnabled = isEnabled
    }

    public func includingCategory(_ cat: EventCategory) -> DigestPolicy {
        DigestPolicy(
            sendTime: sendTime,
            includedCategories: includedCategories.union([cat]),
            isEnabled: isEnabled
        )
    }

    public func excludingCategory(_ cat: EventCategory) -> DigestPolicy {
        DigestPolicy(
            sendTime: sendTime,
            includedCategories: includedCategories.subtracting([cat]),
            isEnabled: isEnabled
        )
    }

    public func withSendTime(_ time: DigestTime) -> DigestPolicy {
        DigestPolicy(sendTime: time, includedCategories: includedCategories, isEnabled: isEnabled)
    }

    public func withEnabled(_ enabled: Bool) -> DigestPolicy {
        DigestPolicy(sendTime: sendTime, includedCategories: includedCategories, isEnabled: enabled)
    }
}

// MARK: - NotificationDigestScheduler

/// Schedules a daily digest local notification at the user-configured time.
/// Pure time-calculation logic is fully unit-testable via `nextFireDate(from:calendar:)`.
///
/// The server sends the digest push with the actual content. The local
/// notification is a fallback reminder ("Check your morning digest in BizarreCRM").
public final class NotificationDigestScheduler: Sendable {

    public static let shared = NotificationDigestScheduler()

    // MARK: - Constants

    private let digestRequestID = "bizarre.digest.daily"

    // MARK: - Init

    public init() {}

    // MARK: - Next fire date (pure, testable)

    /// Compute the next digest fire date given a policy, reference date, and calendar.
    /// Always returns a future date.
    public func nextFireDate(
        from now: Date = Date(),
        policy: DigestPolicy,
        calendar: Calendar = .current
    ) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        comps.hour = policy.sendTime.hour
        comps.minute = policy.sendTime.minute
        comps.second = 0

        guard var candidate = calendar.date(from: comps) else {
            return now.addingTimeInterval(86_400)
        }

        // If the configured time has already passed today, fire tomorrow
        if candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    // MARK: - Schedule

    /// Schedule (or re-schedule) the daily digest local notification.
    public func schedule(policy: DigestPolicy, now: Date = Date(), calendar: Calendar = .current) async {
        guard policy.isEnabled else {
            await cancel()
            return
        }

        let fireDate = nextFireDate(from: now, policy: policy, calendar: calendar)
        let delay = max(1, fireDate.timeIntervalSince(now))

        let content = UNMutableNotificationContent()
        content.title = "Morning Digest"
        content.body = "Your daily BizarreCRM summary is ready."
        content.categoryIdentifier = "bizarre.digest"
        content.interruptionLevel = .passive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: digestRequestID, content: content, trigger: trigger)

        do {
            // Remove old schedule before adding new
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [digestRequestID])
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.ui.error("DigestScheduler: schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cancel

    public func cancel() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [digestRequestID])
    }

    // MARK: - Status

    public func isScheduled() async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == digestRequestID }
    }
}
