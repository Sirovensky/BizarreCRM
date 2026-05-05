import Foundation
import Networking

// MARK: - Response containers

public struct PTOListResponse: Decodable, Sendable {
    public let requests: [PTORequest]
}

public struct PTOResponse: Decodable, Sendable {
    public let request: PTORequest
}

// MARK: - Request bodies

public struct CreatePTORequest: Encodable, Sendable {
    public let employeeId: String
    public let type: PTOType
    public let startDate: Date
    public let endDate: Date
    public let reason: String

    public init(employeeId: String, type: PTOType, startDate: Date, endDate: Date, reason: String) {
        self.employeeId = employeeId
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case type, reason
        case employeeId = "employee_id"
        case startDate  = "start_date"
        case endDate    = "end_date"
    }
}

public struct ReviewPTORequest: Encodable, Sendable {
    public let status: PTOStatus
    public let reviewedBy: String

    public init(status: PTOStatus, reviewedBy: String) {
        self.status = status
        self.reviewedBy = reviewedBy
    }

    enum CodingKeys: String, CodingKey {
        case status
        case reviewedBy = "reviewed_by"
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func listPTORequests(employeeId: String? = nil, status: PTOStatus? = nil) async throws -> [PTORequest] {
        var query: [URLQueryItem] = []
        if let eid = employeeId { query.append(.init(name: "employee_id", value: eid)) }
        if let s = status { query.append(.init(name: "status", value: s.rawValue)) }
        return try await get("/employees/pto",
                             query: query.isEmpty ? nil : query,
                             as: PTOListResponse.self).requests
    }

    func createPTORequest(_ req: CreatePTORequest) async throws -> PTORequest {
        try await post("/employees/pto", body: req, as: PTOResponse.self).request
    }

    func reviewPTORequest(id: String, _ req: ReviewPTORequest) async throws -> PTORequest {
        try await patch("/employees/pto/\(id)/review", body: req, as: PTOResponse.self).request
    }

    func deletePTORequest(id: String) async throws {
        try await delete("/employees/pto/\(id)")
    }
}
