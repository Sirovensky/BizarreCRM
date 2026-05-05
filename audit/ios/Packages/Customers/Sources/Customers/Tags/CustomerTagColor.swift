import Foundation
import SwiftUI
import DesignSystem

// MARK: - §5.7 CustomerTagColor — tenant-defined color palette for tags

/// A color swatch a tenant can assign to any tag string.
///
/// Stored as a hex string so it round-trips through JSON cleanly.
/// The `systemName` is a display fallback when hex is absent.
public struct CustomerTagColor: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    /// Tag string this color is bound to (case-insensitive match).
    public var name: String
    /// Hex string, e.g. `"#FF6B35"`. Nil ↔ use `defaultColor`.
    public var hex: String?
    /// Optional SF Symbol name used as a visual indicator beside the tag chip.
    public var symbolName: String?

    public init(name: String, hex: String? = nil, symbolName: String? = nil) {
        self.name = name
        self.hex = hex
        self.symbolName = symbolName
    }

    /// Resolved SwiftUI `Color` for this tag.
    public var color: Color {
        guard let hex else { return .bizarreOnSurfaceMuted }
        return Color(hex: hex) ?? .bizarreOnSurfaceMuted
    }

    /// Default palette of common tag colors matching the brand surface ramp.
    public static let defaultPalette: [CustomerTagColor] = [
        CustomerTagColor(name: "vip",          hex: "#FFD700", symbolName: "star.fill"),
        CustomerTagColor(name: "corporate",     hex: "#4A90D9", symbolName: "building.2.fill"),
        CustomerTagColor(name: "recurring",     hex: "#27AE60", symbolName: "arrow.clockwise"),
        CustomerTagColor(name: "late-payer",    hex: "#E74C3C", symbolName: "exclamationmark.triangle.fill"),
        CustomerTagColor(name: "wholesale",     hex: "#8E44AD", symbolName: "shippingbox.fill"),
        CustomerTagColor(name: "new-customer",  hex: "#1ABC9C", symbolName: "person.badge.plus"),
        CustomerTagColor(name: "loyalty",       hex: "#F39C12", symbolName: "heart.fill"),
        CustomerTagColor(name: "do-not-contact",hex: "#95A5A6", symbolName: "nosign"),
    ]
}

// MARK: - Auto-tag rule (§5.7 — auto-tags applied by rules)

/// A rule that applies a tag automatically when a condition is met.
///
/// Example: `{ condition: .ltvOver(1000), tag: "gold" }`
///
/// Server evaluates these rules server-side; iOS surfaces them read-only
/// in the Settings → Customer Tags admin page.
public struct CustomerAutoTagRule: Codable, Sendable, Identifiable {
    public var id: String
    public var tag: String
    public var condition: AutoTagCondition

    public enum AutoTagCondition: Codable, Sendable {
        case ltvOver(Int)           // lifetime value in cents
        case overdueInvoiceCount(Int)
        case daysSinceLastVisit(Int)
        case ticketCount(Int)
        case custom(String)         // free-text description for server-defined conditions

        enum CodingKeys: String, CodingKey { case type, value }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type_ = try c.decode(String.self, forKey: .type)
            switch type_ {
            case "ltv_over":
                self = .ltvOver(try c.decode(Int.self, forKey: .value))
            case "overdue_invoice_count":
                self = .overdueInvoiceCount(try c.decode(Int.self, forKey: .value))
            case "days_since_last_visit":
                self = .daysSinceLastVisit(try c.decode(Int.self, forKey: .value))
            case "ticket_count":
                self = .ticketCount(try c.decode(Int.self, forKey: .value))
            default:
                self = .custom(try c.decode(String.self, forKey: .value))
            }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .ltvOver(let v):
                try c.encode("ltv_over", forKey: .type); try c.encode(v, forKey: .value)
            case .overdueInvoiceCount(let v):
                try c.encode("overdue_invoice_count", forKey: .type); try c.encode(v, forKey: .value)
            case .daysSinceLastVisit(let v):
                try c.encode("days_since_last_visit", forKey: .type); try c.encode(v, forKey: .value)
            case .ticketCount(let v):
                try c.encode("ticket_count", forKey: .type); try c.encode(v, forKey: .value)
            case .custom(let s):
                try c.encode("custom", forKey: .type); try c.encode(s, forKey: .value)
            }
        }
    }

    /// Human-readable description for the rule condition.
    public var conditionDescription: String {
        switch condition {
        case .ltvOver(let cents):
            let dollars = cents / 100
            return "LTV > $\(dollars)"
        case .overdueInvoiceCount(let n):
            return "\(n)+ overdue invoice\(n == 1 ? "" : "s")"
        case .daysSinceLastVisit(let d):
            return "No visit in \(d)+ days"
        case .ticketCount(let n):
            return "\(n)+ total tickets"
        case .custom(let desc):
            return desc
        }
    }

    public init(id: String, tag: String, condition: AutoTagCondition) {
        self.id = id
        self.tag = tag
        self.condition = condition
    }
}

// MARK: - Color hex init helper

private extension Color {
    init?(hex: String) {
        let stripped = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard stripped.count == 6,
              let value = UInt64(stripped, radix: 16)
        else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
