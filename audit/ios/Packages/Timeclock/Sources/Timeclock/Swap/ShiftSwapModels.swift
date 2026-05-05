import Foundation

// MARK: - ShiftSwapStatus

public enum ShiftSwapStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case offered
    case approved
    case declined
    case cancelled
}

// MARK: - ShiftSwapRequest

public struct ShiftSwapRequest: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let requesterId: Int64
    public let requesterShiftId: Int64
    public let targetEmployeeId: Int64?
    public let targetShiftId: Int64?
    public let status: ShiftSwapStatus
    public let note: String?
    public let createdAt: String

    public init(
        id: Int64,
        requesterId: Int64,
        requesterShiftId: Int64,
        targetEmployeeId: Int64? = nil,
        targetShiftId: Int64? = nil,
        status: ShiftSwapStatus = .pending,
        note: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.requesterId = requesterId
        self.requesterShiftId = requesterShiftId
        self.targetEmployeeId = targetEmployeeId
        self.targetShiftId = targetShiftId
        self.status = status
        self.note = note
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId        = "requester_id"
        case requesterShiftId   = "requester_shift_id"
        case targetEmployeeId   = "target_employee_id"
        case targetShiftId      = "target_shift_id"
        case status
        case note
        case createdAt          = "created_at"
    }
}

// MARK: - SwapRequestBody

public struct SwapRequestBody: Encodable, Sendable {
    public let requesterShiftId: Int64
    public let targetEmployeeId: Int64
    public let note: String?

    public init(requesterShiftId: Int64, targetEmployeeId: Int64, note: String? = nil) {
        self.requesterShiftId = requesterShiftId
        self.targetEmployeeId = targetEmployeeId
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case requesterShiftId  = "requester_shift_id"
        case targetEmployeeId  = "target_employee_id"
        case note
    }
}

// MARK: - SwapOfferBody

public struct SwapOfferBody: Encodable, Sendable {
    public let targetShiftId: Int64

    public init(targetShiftId: Int64) {
        self.targetShiftId = targetShiftId
    }

    enum CodingKeys: String, CodingKey {
        case targetShiftId = "target_shift_id"
    }
}

// MARK: - SwapApproveBody

public struct SwapApproveBody: Encodable, Sendable {
    public let approved: Bool

    public init(approved: Bool) {
        self.approved = approved
    }
}
