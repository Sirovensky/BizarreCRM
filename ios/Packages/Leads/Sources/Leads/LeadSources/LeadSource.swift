import Foundation

// MARK: - LeadSource

/// §9.7 — Canonical lead source enum.
/// Raw values match the server's `source` field strings.
public enum LeadSource: String, CaseIterable, Sendable, Identifiable, Hashable {
    case walkIn    = "walk_in"
    case phone     = "phone"
    case web       = "web"
    case referral  = "referral"
    case campaign  = "campaign"
    case other     = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .walkIn:   return "Walk-in"
        case .phone:    return "Phone"
        case .web:      return "Web"
        case .referral: return "Referral"
        case .campaign: return "Campaign"
        case .other:    return "Other"
        }
    }

    public var iconName: String {
        switch self {
        case .walkIn:   return "figure.walk"
        case .phone:    return "phone.fill"
        case .web:      return "globe"
        case .referral: return "person.2.fill"
        case .campaign: return "megaphone.fill"
        case .other:    return "questionmark.circle.fill"
        }
    }

    /// Maps a raw server string (case-insensitive) to a known source.
    public static func from(_ raw: String?) -> LeadSource {
        guard let r = raw?.lowercased().replacingOccurrences(of: "-", with: "_") else { return .other }
        return LeadSource(rawValue: r) ?? .other
    }
}
