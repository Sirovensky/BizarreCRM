import Foundation

// §32 Telemetry Sovereignty Guardrails
// Zero third-party egress — events route exclusively to the tenant's own server.

// MARK: - TelemetryCategory

/// Top-level grouping for sovereignty telemetry events.
///
/// Categories are stable string identifiers; adding a new case is a non-breaking change.
public enum TelemetryCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case appLifecycle  = "app_lifecycle"
    case navigation    = "navigation"
    case auth          = "auth"
    case domain        = "domain"
    case hardware      = "hardware"
    case performance   = "performance"
    case error         = "error"
    case security      = "security"
    case sync          = "sync"
}

// MARK: - TelemetryRecord

/// An immutable, strongly-typed sovereignty telemetry event.
///
/// Properties are plain `[String: String]` so no custom codec is required and
/// values are easy to redact before the event leaves the device.
///
/// - Note: Do NOT embed raw PII in `properties`. Pass all values through
///   `TelemetryRedactor.scrub(_:)` before creating a `TelemetryRecord`.
///
/// The file is named `TelemetryEvent.swift` to satisfy §32 naming requirements.
/// The concrete type is `TelemetryRecord` because `TelemetryEvent` is reserved
/// by the phase-0 stub in `Logging/TelemetrySink.swift`.
public struct TelemetryRecord: Codable, Sendable, Hashable {

    // MARK: - Properties

    /// Broad grouping, used for routing and dashboards.
    public let category: TelemetryCategory

    /// Machine-readable event name, e.g. `"ticket.created"`.
    /// Must not contain user-identifying text.
    public let name: String

    /// Redacted key→value metadata.
    /// All values MUST pass through `TelemetryRedactor.scrub(_:)` before being
    /// stored here; callers are responsible for this precondition.
    public let properties: [String: String]

    /// Wall-clock time at event creation (UTC).
    public let timestamp: Date

    // MARK: - Init

    public init(
        category: TelemetryCategory,
        name: String,
        properties: [String: String] = [:],
        timestamp: Date = .now
    ) {
        self.category   = category
        self.name       = name
        self.properties = properties
        self.timestamp  = timestamp
    }

    // MARK: - Codable (custom date strategy)

    private enum CodingKeys: String, CodingKey {
        case category, name, properties, timestamp
    }

    public init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        category     = try c.decode(TelemetryCategory.self, forKey: .category)
        name         = try c.decode(String.self,            forKey: .name)
        properties   = try c.decode([String: String].self,  forKey: .properties)
        let iso      = try c.decode(String.self,            forKey: .timestamp)
        guard let date = ISO8601DateFormatter().date(from: iso) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp, in: c,
                debugDescription: "Expected ISO-8601 date string"
            )
        }
        timestamp = date
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(category,                             forKey: .category)
        try c.encode(name,                                 forKey: .name)
        try c.encode(properties,                           forKey: .properties)
        try c.encode(ISO8601DateFormatter().string(from: timestamp), forKey: .timestamp)
    }
}
