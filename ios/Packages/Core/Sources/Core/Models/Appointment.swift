import Foundation

// MARK: - Appointment

/// Canonical domain model for a scheduled appointment.
/// Wire DTO: Networking/Endpoints/AppointmentsEndpoints.swift (Appointment).
public struct Appointment: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let leadId: Int64?
    public let customerId: Int64?
    public let assignedUserId: Int64?
    public let title: String?
    public let notes: String?
    public let status: AppointmentStatus
    public let location: String?
    public let startTime: Date
    public let endTime: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        leadId: Int64? = nil,
        customerId: Int64? = nil,
        assignedUserId: Int64? = nil,
        title: String? = nil,
        notes: String? = nil,
        status: AppointmentStatus = .scheduled,
        location: String? = nil,
        startTime: Date,
        endTime: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.leadId = leadId
        self.customerId = customerId
        self.assignedUserId = assignedUserId
        self.title = title
        self.notes = notes
        self.status = status
        self.location = location
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayTitle: String { title?.isEmpty == false ? title! : "Appointment #\(id)" }

    public var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
}

// MARK: - AppointmentStatus

public enum AppointmentStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case scheduled
    case confirmed
    case checkedIn = "checked_in"
    case completed
    case noShow = "no_show"
    case cancelled

    public var displayName: String {
        switch self {
        case .scheduled:  return "Scheduled"
        case .confirmed:  return "Confirmed"
        case .checkedIn:  return "Checked In"
        case .completed:  return "Completed"
        case .noShow:     return "No Show"
        case .cancelled:  return "Cancelled"
        }
    }
}
