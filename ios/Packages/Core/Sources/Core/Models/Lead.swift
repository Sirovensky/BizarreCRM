import Foundation

// MARK: - Lead

/// Canonical domain model for a sales / service lead.
/// Wire DTO: Networking/Endpoints/LeadsEndpoints.swift (Lead, LeadDetail).
public struct Lead: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let orderId: String?
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let status: LeadStatus
    public let source: LeadSource?
    public let leadScore: Int?
    public let assignedUserId: Int64?
    public let convertedCustomerId: Int64?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        orderId: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        status: LeadStatus = .new,
        source: LeadSource? = nil,
        leadScore: Int? = nil,
        assignedUserId: Int64? = nil,
        convertedCustomerId: Int64? = nil,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.orderId = orderId
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.status = status
        self.source = source
        self.leadScore = leadScore
        self.assignedUserId = assignedUserId
        self.convertedCustomerId = convertedCustomerId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (orderId ?? "Lead #\(id)") : parts.joined(separator: " ")
    }
}

// MARK: - LeadStatus

public enum LeadStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case new
    case contacted
    case qualified
    case proposalSent = "proposal_sent"
    case negotiating
    case won
    case lost
    case nurturing

    public var displayName: String {
        switch self {
        case .new:          return "New"
        case .contacted:    return "Contacted"
        case .qualified:    return "Qualified"
        case .proposalSent: return "Proposal Sent"
        case .negotiating:  return "Negotiating"
        case .won:          return "Won"
        case .lost:         return "Lost"
        case .nurturing:    return "Nurturing"
        }
    }
}

// MARK: - LeadSource

public enum LeadSource: String, Codable, CaseIterable, Hashable, Sendable {
    case walkin = "walk_in"
    case website
    case referral
    case phone
    case email
    case socialMedia = "social_media"
    case advertisement
    case other

    public var displayName: String {
        switch self {
        case .walkin:        return "Walk-In"
        case .website:       return "Website"
        case .referral:      return "Referral"
        case .phone:         return "Phone"
        case .email:         return "Email"
        case .socialMedia:   return "Social Media"
        case .advertisement: return "Advertisement"
        case .other:         return "Other"
        }
    }
}
