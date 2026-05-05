import Foundation
import UserNotifications
import Core

// MARK: - SnoozeDuration

/// User-selectable snooze durations for the picker sheet.
public enum SnoozeDuration: Sendable, Hashable {
    case minutes(Int)
    case tomorrowAt(hour: Int, minute: Int)
    case custom(minutes: Int)

    // MARK: - Standard presets

    public static let fifteenMinutes: SnoozeDuration = .minutes(15)
    public static let oneHour: SnoozeDuration = .minutes(60)
    public static let tomorrowMorning: SnoozeDuration = .tomorrowAt(hour: 9, minute: 0)

    // MARK: - Fire date

    /// Compute the absolute `Date` at which the snoozed notification fires.
    public func fireDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .minutes(let m), .custom(let m):
            return now.addingTimeInterval(TimeInterval(m * 60))
        case .tomorrowAt(let hour, let minute):
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.day = (comps.day ?? 0) + 1
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.date(from: comps) ?? now.addingTimeInterval(86_400)
        }
    }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .minutes(let m) where m < 60:
            return "\(m) min"
        case .minutes(let m):
            let h = m / 60
            return h == 1 ? "1 hour" : "\(h) hours"
        case .custom(let m):
            return "\(m) min (custom)"
        case .tomorrowAt(let h, let m):
            let label = h < 12 ? "\(h == 0 ? 12 : h):\(String(format: "%02d", m)) AM"
                                : "\(h == 12 ? 12 : h - 12):\(String(format: "%02d", m)) PM"
            return "Tomorrow \(label)"
        }
    }
}

// MARK: - SnoozedEntry

/// A pending snooze stored for display in `SnoozedNotificationsListView`.
public struct SnoozedEntry: Identifiable, Sendable, Equatable {
    public let id: String          // UNNotificationRequest identifier
    public let title: String
    public let body: String
    public let fireAt: Date
    public let category: EventCategory

    public init(id: String, title: String, body: String, fireAt: Date, category: EventCategory) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
        self.category = category
    }
}

// MARK: - SnoozeActionHandler

/// Handles the snooze notification action.
/// Extends Phase 6A `NotificationCategories.snooze` infrastructure.
/// Fires a local notification at `now + duration`.
/// All stored pending snoozes can be retrieved for `SnoozedNotificationsListView`.
public final class SnoozeActionHandler: Sendable {

    public static let shared = SnoozeActionHandler()

    // MARK: - Constants

    private let snoozeIDPrefix = "snooze."

    // MARK: - Init

    public init() {}

    // MARK: - Schedule

    /// Schedule a snoozed local notification from an existing `UNNotification`.
    /// - Parameters:
    ///   - notification: The notification to re-fire.
    ///   - duration: When to re-fire.
    ///   - now: Override for testing (default `Date()`).
    public func snooze(
        notification: UNNotification,
        duration: SnoozeDuration,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let fireDate = duration.fireDate(from: now, calendar: calendar)
        let delay = max(1, fireDate.timeIntervalSince(now))

        let content = notification.request.content.mutableCopy() as! UNMutableNotificationContent
        // Tag so we can filter in list view
        var info = content.userInfo
        info["snoozedCategory"] = content.categoryIdentifier
        info["snoozedTitle"] = content.title
        content.userInfo = info

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let requestID = snoozeIDPrefix + notification.request.identifier
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.ui.error("SnoozeActionHandler: schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schedule from raw parameters (used by `SnoozeActionHandler` when a push
    /// notification arrives without a live `UNNotification` object).
    public func scheduleSnooze(
        identifier: String,
        title: String,
        body: String,
        categoryID: String,
        duration: SnoozeDuration,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let fireDate = duration.fireDate(from: now, calendar: calendar)
        let delay = max(1, fireDate.timeIntervalSince(now))

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "snoozedCategory": categoryID,
            "snoozedTitle": title
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let requestID = snoozeIDPrefix + identifier
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.ui.error("SnoozeActionHandler: schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cancel

    /// Cancel a pending snooze by the original notification identifier.
    public func cancelSnooze(for originalIdentifier: String) {
        let id = snoozeIDPrefix + originalIdentifier
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - List pending snoozes

    /// Fetch all pending snoozed notifications.
    public func pendingSnoozes() async -> [SnoozedEntry] {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending
            .filter { $0.identifier.hasPrefix(snoozeIDPrefix) }
            .compactMap { request -> SnoozedEntry? in
                guard
                    let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
                    let nextDate = trigger.nextTriggerDate()
                else { return nil }

                let userInfo = request.content.userInfo
                let catRaw = userInfo["snoozedCategory"] as? String ?? ""
                let category = EventCategory(rawValue: catRaw) ?? .admin

                return SnoozedEntry(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    fireAt: nextDate,
                    category: category
                )
            }
            .sorted { $0.fireAt < $1.fireAt }
    }
}
