import Foundation

// MARK: - SilentPushPayloadType

/// Typed envelope for a decoded silent push (`content-available: 1`) payload.
///
/// The server always sends:
/// ```json
/// {
///   "aps": { "content-available": 1 },
///   "kind": "<value>",
///   "messageId": "<uuid>",        // dedup key
///   "entityId": "<server-id>",    // optional
///   "scope": "<tenant-or-global>",// optional
///   "expiresAt": "<iso8601>",     // optional TTL
///   "meta": { ... }               // optional k/v bag
/// }
/// ```
///
/// Use `SilentPushPayloadType.decode(from:)` to build a typed value from the
/// raw `userInfo` dictionary delivered by APNs.
public enum SilentPushPayloadType: Sendable {

    // MARK: - Cases

    /// Full incremental sync — re-pull all dirty entities.
    case cacheInvalidate(SilentPushEnvelope)

    /// Refresh a specific named entity (ticket, customer, invoice, …).
    case dataRefresh(SilentPushEnvelope)

    /// Server requests the device to perform a specific remote action.
    case remoteCommand(SilentPushEnvelope)

    /// A dead-letter sync op was written; surface in Dead Letter Viewer.
    case deadLetter(SilentPushEnvelope)

    /// An SMS thread has a new message.
    case smsMessage(SilentPushEnvelope)

    /// Inventory quantity changed for a product.
    case inventoryUpdate(SilentPushEnvelope)

    /// An appointment was created or updated.
    case appointmentUpdate(SilentPushEnvelope)

    /// A kind string the client does not recognise — includes raw `kind`.
    case unknown(kind: String, envelope: SilentPushEnvelope)

    // MARK: - Envelope accessor

    /// The underlying envelope for any case.
    public var envelope: SilentPushEnvelope {
        switch self {
        case .cacheInvalidate(let e),
             .dataRefresh(let e),
             .remoteCommand(let e),
             .deadLetter(let e),
             .smsMessage(let e),
             .inventoryUpdate(let e),
             .appointmentUpdate(let e):
            return e
        case .unknown(_, let e):
            return e
        }
    }

    // MARK: - Decoding

    /// Decode a `SilentPushPayloadType` from the raw APNs `userInfo` dictionary.
    ///
    /// Returns `nil` when the push is not a silent push
    /// (i.e., `aps.content-available` is absent or not `1`).
    public static func decode(from userInfo: [AnyHashable: Any]) -> SilentPushPayloadType? {
        guard
            let aps = userInfo["aps"] as? [String: Any],
            (aps["content-available"] as? Int) == 1
        else { return nil }

        let envelope = SilentPushEnvelope(userInfo: userInfo)
        let kindRaw  = (userInfo["kind"] as? String) ?? "cacheInvalidate"

        switch kindRaw {
        case "sync", "cacheInvalidate":
            return .cacheInvalidate(envelope)
        case "ticket", "customer", "invoice", "dataRefresh":
            return .dataRefresh(envelope)
        case "remoteCommand":
            return .remoteCommand(envelope)
        case "deadletter", "deadLetter":
            return .deadLetter(envelope)
        case "sms":
            return .smsMessage(envelope)
        case "inventory":
            return .inventoryUpdate(envelope)
        case "appointment":
            return .appointmentUpdate(envelope)
        default:
            return .unknown(kind: kindRaw, envelope: envelope)
        }
    }
}

// MARK: - SilentPushEnvelope

/// Immutable value that carries all fields from the raw silent push `userInfo`.
///
/// All properties are optional; callers should handle absent fields gracefully
/// rather than crashing. `messageId` is the canonical dedup key — a UUID string
/// set by the server. When the server does not include it, a stable hash of the
/// payload is used as a fallback so the `SilentPushDeduplicator` still functions.
public struct SilentPushEnvelope: Sendable, Equatable {

    // MARK: - Properties

    /// Deduplication key. Prefer server-supplied `messageId`; falls back to
    /// a hash of `kind + entityId + timestamp` rounded to 1 second.
    public let messageId: String

    /// Raw `kind` string from the payload.
    public let kind: String

    /// Optional server-side entity identifier (ticket ID, customer ID, …).
    public let entityId: String?

    /// Optional tenant or broadcast scope hint.
    public let scope: String?

    /// Optional server-set TTL. Messages received after this date are dropped.
    public let expiresAt: Date?

    /// Additional free-form metadata from the server.
    public let meta: [String: String]

    /// Wall-clock time at which the envelope was decoded.
    public let receivedAt: Date

    // MARK: - Init (public — for tests)

    public init(
        messageId: String,
        kind: String,
        entityId: String? = nil,
        scope: String? = nil,
        expiresAt: Date? = nil,
        meta: [String: String] = [:],
        receivedAt: Date = .now
    ) {
        self.messageId  = messageId
        self.kind       = kind
        self.entityId   = entityId
        self.scope      = scope
        self.expiresAt  = expiresAt
        self.meta       = meta
        self.receivedAt = receivedAt
    }

    // MARK: - Internal decoding init

    init(userInfo: [AnyHashable: Any], receivedAt: Date = .now) {
        let kind     = (userInfo["kind"] as? String) ?? "unknown"
        let entityId = (userInfo["entityId"] as? String) ?? (userInfo["entity_id"] as? String)
        let scope    = userInfo["scope"] as? String

        var expiresAt: Date?
        if let iso = userInfo["expiresAt"] as? String {
            expiresAt = ISO8601DateFormatter().date(from: iso)
        }

        var meta: [String: String] = [:]
        if let rawMeta = userInfo["meta"] as? [String: String] {
            meta = rawMeta
        }

        // Prefer server-supplied messageId; synthesise fallback if absent.
        let messageId: String
        if let serverID = userInfo["messageId"] as? String, !serverID.isEmpty {
            messageId = serverID
        } else {
            // Fallback: hash of kind + entityId + second-resolution timestamp
            let ts = Int(receivedAt.timeIntervalSince1970)
            let raw = "\(kind)|\(entityId ?? "")|\(ts)"
            messageId = String(raw.hashValue)
        }

        self.messageId  = messageId
        self.kind       = kind
        self.entityId   = entityId
        self.scope      = scope
        self.expiresAt  = expiresAt
        self.meta       = meta
        self.receivedAt = receivedAt
    }

    // MARK: - TTL check

    /// Returns `true` when the envelope has a server-set expiry that has passed.
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < receivedAt
    }
}
