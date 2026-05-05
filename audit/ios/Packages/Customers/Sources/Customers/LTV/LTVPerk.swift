import Foundation

// MARK: - LTVPerkKind

/// The kind of benefit a tier perk provides.
public enum LTVPerkKind: Sendable, Equatable, Codable {
    /// Automatic discount in whole percent (e.g. `10` → 10 %).
    case discount(percent: Int)
    /// Customer is placed at this position in the priority queue (`1` = top).
    case priorityQueue(position: Int)
    /// Extra warranty months beyond the standard period.
    case warrantyMonths(Int)
    /// Free-form benefit described by text.
    case custom(String)

    // MARK: Codable

    private enum Tag: String, Codable {
        case discount, priorityQueue, warrantyMonths, custom
    }

    private enum CodingKeys: String, CodingKey {
        case tag, value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        switch tag {
        case .discount:
            let pct = try c.decode(Int.self, forKey: .value)
            self = .discount(percent: pct)
        case .priorityQueue:
            let pos = try c.decode(Int.self, forKey: .value)
            self = .priorityQueue(position: pos)
        case .warrantyMonths:
            let m = try c.decode(Int.self, forKey: .value)
            self = .warrantyMonths(m)
        case .custom:
            let s = try c.decode(String.self, forKey: .value)
            self = .custom(s)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .discount(let pct):
            try c.encode(Tag.discount, forKey: .tag)
            try c.encode(pct, forKey: .value)
        case .priorityQueue(let pos):
            try c.encode(Tag.priorityQueue, forKey: .tag)
            try c.encode(pos, forKey: .value)
        case .warrantyMonths(let m):
            try c.encode(Tag.warrantyMonths, forKey: .tag)
            try c.encode(m, forKey: .value)
        case .custom(let s):
            try c.encode(Tag.custom, forKey: .tag)
            try c.encode(s, forKey: .value)
        }
    }
}

// MARK: - LTVPerk

/// A single perk that applies to customers at or above a given `LTVTier`.
public struct LTVPerk: Sendable, Identifiable, Equatable, Codable {
    public let id: String
    public let tier: LTVTier
    public let kind: LTVPerkKind
    public let description: String

    public init(id: String, tier: LTVTier, kind: LTVPerkKind, description: String) {
        self.id          = id
        self.tier        = tier
        self.kind        = kind
        self.description = description
    }
}

// MARK: - Built-in defaults

public extension LTVPerk {

    /// A sensible default set of perks.
    static let defaults: [LTVPerk] = [
        LTVPerk(id: "bronze-discount",   tier: .bronze,   kind: .discount(percent: 0),       description: "Standard pricing"),
        LTVPerk(id: "silver-discount",   tier: .silver,   kind: .discount(percent: 5),        description: "5% loyalty discount"),
        LTVPerk(id: "silver-warranty",   tier: .silver,   kind: .warrantyMonths(1),            description: "+1 month warranty"),
        LTVPerk(id: "gold-discount",     tier: .gold,     kind: .discount(percent: 10),       description: "10% loyalty discount"),
        LTVPerk(id: "gold-priority",     tier: .gold,     kind: .priorityQueue(position: 2),  description: "Priority queue"),
        LTVPerk(id: "gold-warranty",     tier: .gold,     kind: .warrantyMonths(3),            description: "+3 months warranty"),
        LTVPerk(id: "platinum-discount", tier: .platinum, kind: .discount(percent: 15),       description: "15% loyalty discount"),
        LTVPerk(id: "platinum-priority", tier: .platinum, kind: .priorityQueue(position: 1),  description: "Top priority queue"),
        LTVPerk(id: "platinum-warranty", tier: .platinum, kind: .warrantyMonths(6),            description: "+6 months warranty"),
    ]
}
