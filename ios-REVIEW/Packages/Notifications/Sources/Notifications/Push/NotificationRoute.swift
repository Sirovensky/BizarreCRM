import Foundation

// MARK: - NotificationRoute
//
// Structured destination extracted from an APNs push payload.
// The app-shell router (outside this package) switches on this enum to push
// the correct SwiftUI destination onto its NavigationPath or NavigationSplitView.
//
// Design contract:
// - Every case carries the minimum data needed to build the target screen.
// - The `from(userInfo:)` factory is the single parse point; never parse
//   `userInfo` dictionaries directly in the app shell.
// - Unknown / malformed payloads resolve to `.unknown` — never silently drop.

/// A type-safe deep-link destination derived from an APNs push notification payload.
public enum NotificationRoute: Sendable, Equatable {

    // MARK: - Feature destinations

    /// Navigate to a ticket detail screen.
    case ticket(id: Int64)

    /// Navigate to a customer detail screen.
    case customer(id: Int64)

    /// Navigate to an invoice detail screen.
    case invoice(id: Int64)

    /// Navigate to an estimate detail screen.
    case estimate(id: Int64)

    /// Navigate to an appointment detail screen.
    case appointment(id: Int64)

    /// Navigate to an SMS thread.
    case smsThread(id: Int64)

    /// Navigate to an SMS thread (alias — payload uses "thread").
    case thread(id: Int64)

    /// Navigate to an expense detail screen.
    case expense(id: Int64)

    /// Navigate to a lead detail screen.
    case lead(id: Int64)

    /// Navigate to the employee/staff profile.
    case employee(id: Int64)

    /// Navigate to the in-app notification detail.
    case notification(id: Int64)

    /// Payload was present but could not be mapped to a known entity type.
    /// The raw `entityType` string is preserved for diagnostic logging.
    case unknown(entityType: String)

    // MARK: - Factory

    /// Parse an APNs `userInfo` dictionary into a `NotificationRoute`.
    ///
    /// Resolution order:
    /// 1. Pre-formed `bizarrecrm://` URL in the `deepLink` key.
    /// 2. `entityType` + `entityId` fields.
    ///
    /// Returns `nil` when the payload carries no routing information at all
    /// (e.g. a marketing push with no `deepLink` and no `entityType`).
    public static func from(userInfo: [AnyHashable: Any]) -> NotificationRoute? {
        // 1. Pre-formed URL
        if let raw = userInfo["deepLink"] as? String,
           let url = URL(string: raw),
           url.scheme == "bizarrecrm",
           let host = url.host {
            let idString = url.pathComponents.dropFirst().first ?? ""
            let id = Int64(idString)
            return route(entityType: host.lowercased(), entityId: id)
        }

        // 2. entityType + entityId
        let entityTypeRaw = (userInfo["entityType"] as? String
                             ?? userInfo["entity_type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let entityType = entityTypeRaw, !entityType.isEmpty else {
            return nil
        }

        let entityIdRaw: Int64? = (userInfo["entityId"] as? Int64)
            ?? (userInfo["entity_id"] as? Int64)
            ?? (userInfo["entityId"] as? Int).map(Int64.init)
            ?? (userInfo["entity_id"] as? Int).map(Int64.init)
            ?? (userInfo["entityId"] as? String).flatMap(Int64.init)
            ?? (userInfo["entity_id"] as? String).flatMap(Int64.init)

        return route(entityType: entityType, entityId: entityIdRaw)
    }

    // MARK: - Private helpers

    private static func route(entityType: String, entityId: Int64?) -> NotificationRoute {
        switch entityType {
        case "ticket":
            return entityId.map { .ticket(id: $0) } ?? .unknown(entityType: entityType)
        case "customer":
            return entityId.map { .customer(id: $0) } ?? .unknown(entityType: entityType)
        case "invoice":
            return entityId.map { .invoice(id: $0) } ?? .unknown(entityType: entityType)
        case "estimate":
            return entityId.map { .estimate(id: $0) } ?? .unknown(entityType: entityType)
        case "appointment":
            return entityId.map { .appointment(id: $0) } ?? .unknown(entityType: entityType)
        case "sms":
            return entityId.map { .smsThread(id: $0) } ?? .unknown(entityType: entityType)
        case "thread":
            return entityId.map { .thread(id: $0) } ?? .unknown(entityType: entityType)
        case "expense":
            return entityId.map { .expense(id: $0) } ?? .unknown(entityType: entityType)
        case "lead":
            return entityId.map { .lead(id: $0) } ?? .unknown(entityType: entityType)
        case "employee":
            return entityId.map { .employee(id: $0) } ?? .unknown(entityType: entityType)
        case "notification":
            return entityId.map { .notification(id: $0) } ?? .unknown(entityType: entityType)
        default:
            return .unknown(entityType: entityType)
        }
    }
}
