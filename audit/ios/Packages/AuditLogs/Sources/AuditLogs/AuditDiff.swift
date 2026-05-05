import Foundation

/// Before/after snapshot carried by an audit entry.
public struct AuditDiff: Codable, Sendable, Hashable {
    public let before: [String: AuditDiffValue]
    public let after: [String: AuditDiffValue]

    public init(before: [String: AuditDiffValue], after: [String: AuditDiffValue]) {
        self.before = before
        self.after = after
    }
}

/// A recursive JSON value that can appear in a diff snapshot.
public indirect enum AuditDiffValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([AuditDiffValue])
    case object([String: AuditDiffValue])

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([AuditDiffValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: AuditDiffValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown AuditDiffValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):   try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Stable string representation used for diff comparison.
    public var displayString: String {
        switch self {
        case .null:           return "null"
        case .bool(let b):   return b ? "true" : "false"
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .string(let s): return "\"\(s)\""
        case .array(let a):  return "[\(a.map(\.displayString).joined(separator: ", "))]"
        case .object(let o): return "{\(o.sorted(by: { $0.key < $1.key }).map { "\"\($0.key)\": \($0.value.displayString)" }.joined(separator: ", "))}"
        }
    }
}
