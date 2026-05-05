import Foundation

// §71 Privacy-first analytics — event payload

// MARK: — AnalyticsValue

/// A JSON-safe analytics property value.
///
/// Uses `indirect enum` to mirror the spec; in practice values are not nested,
/// but `indirect` keeps the type signature compatible with recursive future use.
public indirect enum AnalyticsValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil()              { self = .null;                                   return }
        if let v = try? container.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? container.decode(Int.self)    { self = .int(v);    return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(
            AnalyticsValue.self,
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Expected Bool, Int, Double, String, or null")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }
}

// MARK: — AnalyticsEventPayload

/// An immutable, serialisable analytics event ready to be batched and POSTed.
///
/// - `properties` must already be scrubbed through `AnalyticsRedactor` before
///   this struct is created. Callers use `Analytics.track(...)` which scrubs
///   automatically.
/// - `sessionId` is an opaque UUID generated at session start — never a user ID.
/// - `tenantSlug` is the business identifier, safe to transmit.
public struct AnalyticsEventPayload: Codable, Sendable {

    public let event: AnalyticsEvent
    public let timestamp: Date
    /// Already-redacted properties. Keys that look like PII are dropped by `AnalyticsRedactor`.
    public let properties: [String: AnalyticsValue]
    /// Opaque session UUID — not tied to any user identity.
    public let sessionId: String
    /// Business identifier (tenant slug), e.g. `"acme-repair"`.
    public let tenantSlug: String
    public let appVersion: String
    /// Always `"iOS"`.
    public let platform: String

    public init(
        event: AnalyticsEvent,
        timestamp: Date = .now,
        properties: [String: AnalyticsValue] = [:],
        sessionId: String,
        tenantSlug: String,
        appVersion: String,
        platform: String = "iOS"
    ) {
        self.event = event
        self.timestamp = timestamp
        self.properties = properties
        self.sessionId = sessionId
        self.tenantSlug = tenantSlug
        self.appVersion = appVersion
        self.platform = platform
    }
}
