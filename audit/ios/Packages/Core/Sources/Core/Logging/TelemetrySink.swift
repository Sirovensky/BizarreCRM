import Foundation

// §32 Logging strategy — TelemetrySink
// Phase 0 foundation; real implementation wired in Phase 11.

/// A structured telemetry event forwarded to the tenant's server.
public struct TelemetryEvent: Sendable, Codable {
    /// Machine-readable event name, e.g. `"pos_sale_complete"`.
    public let name: String
    /// ISO-8601 timestamp at event creation.
    public let timestamp: Date
    /// Redacted key→value properties.  Values must be JSON-serialisable primitives.
    public let properties: [String: TelemetryValue]

    public init(name: String, timestamp: Date = .now, properties: [String: TelemetryValue] = [:]) {
        self.name = name
        self.timestamp = timestamp
        self.properties = properties
    }
}

/// A JSON-safe telemetry property value.
public enum TelemetryValue: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(TelemetryValue.self, .init(
            codingPath: decoder.codingPath,
            debugDescription: "Expected Bool, Int, Double, or String"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        }
    }
}

/// Receives structured telemetry events and forwards them to the appropriate sink.
///
/// Implementations must be `Sendable`; the no-op default sink is provided for
/// Phase 0.  The real sink (posting to `POST /telemetry/events`) is wired in
/// Phase 11 via DI.
public protocol TelemetrySink: Sendable {
    func record(_ event: TelemetryEvent) async
}

/// No-op sink used until Phase 11 wires the real implementation.
public struct NoOpTelemetrySink: TelemetrySink {
    public init() {}
    public func record(_ event: TelemetryEvent) async { /* intentionally empty */ }
}
