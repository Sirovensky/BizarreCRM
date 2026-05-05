import Foundation
import UserNotifications
import Core

// MARK: - §13.2 interruptionLevel mapping + Rich push NSE bridge

// MARK: - Interruption level mapping

/// Maps `NotificationEvent` to the correct `UNNotificationInterruptionLevel`
/// for iOS 15+ time-sensitive alerts.
///
/// Rules (§70 matrix):
/// - Critical events (`isCritical == true`) → `.timeSensitive` (we do NOT
///   request `.critical` entitlement; that requires Apple approval per §13.4).
/// - SLA breach / overdue invoice → `.timeSensitive` (bypasses Focus silence).
/// - All others → `.active` (standard delivery).
///
/// Applied by the Notification Service Extension (see `RichPushServiceExtension.swift`)
/// when it mutates the content.
public enum NotificationInterruptionLevelMapper {

    /// Returns the interruption level for a notification with the given server event type.
    @available(iOS 15.0, *)
    public static func level(for eventType: String) -> UNNotificationInterruptionLevel {
        switch eventType {
        // Time-sensitive: payment failure, security event, backup failure, stock-out
        case NotificationEvent.paymentDeclined.rawValue,
             NotificationEvent.outOfStock.rawValue,
             NotificationEvent.backupFailed.rawValue,
             NotificationEvent.securityEvent.rawValue,
             // SLA / overdue — bypass Focus silence
             NotificationEvent.invoiceOverdue.rawValue,
             NotificationEvent.cashRegisterShort.rawValue,
             NotificationEvent.integrationDisconnected.rawValue:
            return .timeSensitive

        // NOTE: Never `.critical` — that requires Apple Critical Alerts entitlement.
        // Reserve per §13.4: specific tenants that request it via Apple review.

        default:
            return .active
        }
    }

    /// Convenience: resolve level from `NotificationEvent`.
    @available(iOS 15.0, *)
    public static func level(for event: NotificationEvent) -> UNNotificationInterruptionLevel {
        level(for: event.rawValue)
    }
}

// MARK: - Rich push NSE bridge

/// Constants and helpers consumed by the Notification Service Extension target
/// (`BizarreCRMNotificationService`).
///
/// The NSE is a separate Xcode target (added to project.yml in a future tooling
/// pass — Agent 10 scope per §33). This file lives in the `Notifications` package
/// so the shared logic can be imported from both the main app AND the extension
/// without duplication.
///
/// Entitlement required in `BizarreCRM.entitlements`:
/// ```xml
/// <key>com.apple.developer.usernotifications.time-sensitive</key>
/// <true/>
/// ```
/// This is already present via Xcode capability; the NSE target inherits via
/// a separate `BizarreCRMNotificationService.entitlements` file.
///
/// ## NSE wiring (to be done when target added to project.yml):
/// ```swift
/// // In BizarreCRMNotificationService.swift (NSE target):
/// override func didReceive(_ request: UNNotificationRequest,
///     withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
///     guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
///         return handler(request.content)
///     }
///     Task {
///         let enriched = await RichPushEnricher.enrich(mutable, userInfo: request.content.userInfo)
///         handler(enriched)
///     }
/// }
/// ```
public enum RichPushEnricher {

    // MARK: - Public API

    /// Enrich mutable notification content:
    /// 1. Set `interruptionLevel` from event type.
    /// 2. Attach thumbnail attachment (customer avatar / ticket photo) if URL present.
    ///
    /// - Returns: enriched content (same object, mutated in place).
    @available(iOS 15.0, *)
    public static func enrich(
        _ content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) async -> UNMutableNotificationContent {
        // 1. interruptionLevel
        let eventType = userInfo["event_type"] as? String ?? ""
        content.interruptionLevel = NotificationInterruptionLevelMapper.level(for: eventType)

        // 2. Thumbnail attachment from `thumbnail_url`
        if let urlString = userInfo["thumbnail_url"] as? String,
           let url = URL(string: urlString) {
            content.attachments = (try? await fetchAttachment(from: url)) ?? []
        }

        return content
    }

    // MARK: - Private

    /// Download `url` to a temp file and wrap in `UNNotificationAttachment`.
    private static func fetchAttachment(from url: URL) async throws -> [UNNotificationAttachment] {
        let (data, _) = try await URLSession.shared.data(from: url)
        let ext: String
        switch url.pathExtension.lowercased() {
        case "png": ext = "png"
        case "gif": ext = "gif"
        default:    ext = "jpg"
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: tmpURL)
        let attachment = try UNNotificationAttachment(identifier: UUID().uuidString, url: tmpURL)
        return [attachment]
    }
}

// MARK: - Quiet-hours gate for push delivery

/// Checks whether the current time falls within the user's configured quiet
/// hours. Called by `NotificationHandler` before showing a foreground banner
/// (§70.3 / §13.2).
///
/// Does NOT suppress critical/timeSensitive events — those bypass quiet hours.
public struct QuietHoursGate {

    // MARK: - Keys (matches QuietHoursEditorView storage)

    private static let enabledKey    = "notifPrefs.quietHours.enabled"
    private static let startHourKey  = "notifPrefs.quietHours.startHour"
    private static let startMinKey   = "notifPrefs.quietHours.startMinute"
    private static let endHourKey    = "notifPrefs.quietHours.endHour"
    private static let endMinKey     = "notifPrefs.quietHours.endMinute"

    // MARK: - Public API

    /// Returns `true` when the current wall-clock time is inside quiet hours.
    /// Quiet hours that wrap midnight (e.g. 22:00–07:00) are handled correctly.
    public static func isQuiet(at date: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: enabledKey) else { return false }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startH = defaults.integer(forKey: startHourKey)
        let startM = defaults.integer(forKey: startMinKey)
        let endH   = defaults.integer(forKey: endHourKey)
        let endM   = defaults.integer(forKey: endMinKey)
        let startMinutes = startH * 60 + startM
        let endMinutes   = endH * 60 + endM

        if startMinutes <= endMinutes {
            // Same-day range, e.g. 09:00–17:00
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Overnight range, e.g. 22:00–07:00
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }

    /// Returns `true` when the notification should be suppressed due to quiet hours
    /// (is quiet AND event is not critical).
    @available(iOS 15.0, *)
    public static func shouldSuppress(
        eventType: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard isQuiet(defaults: defaults) else { return false }
        let level = NotificationInterruptionLevelMapper.level(for: eventType)
        return level != .timeSensitive
    }
}
