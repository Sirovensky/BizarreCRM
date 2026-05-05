import Foundation
import Networking
import Core

// MARK: - Response containers

public struct PeerFeedbackListResponse: Decodable, Sendable {
    public let feedback: [PeerFeedback]
}

public struct PeerFeedbackItemResponse: Decodable, Sendable {
    public let feedback: PeerFeedback
}

// MARK: - PeerFeedbackRepository

public protocol PeerFeedbackRepository: Sendable {
    func listFeedback(employeeId: String) async throws -> [PeerFeedback]
    func submitFeedback(_ feedback: PeerFeedback) async throws -> PeerFeedback
    func requestFeedbackFromTeam(forEmployeeId: String, fromTeamIds: [String]) async throws
}

// MARK: - PeerFeedbackRepositoryImpl

public actor PeerFeedbackRepositoryImpl: PeerFeedbackRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listFeedback(employeeId: String) async throws -> [PeerFeedback] {
        try await api.get("/employees/\(employeeId)/peer-feedback",
                          as: PeerFeedbackListResponse.self).feedback
    }

    public func submitFeedback(_ feedback: PeerFeedback) async throws -> PeerFeedback {
        try await api.post("/employees/peer-feedback",
                           body: feedback,
                           as: PeerFeedbackItemResponse.self).feedback
    }

    public func requestFeedbackFromTeam(forEmployeeId: String, fromTeamIds: [String]) async throws {
        struct RequestBody: Encodable, Sendable {
            let employeeId: String
            let teamIds: [String]
            enum CodingKeys: String, CodingKey {
                case employeeId = "employee_id"
                case teamIds    = "team_ids"
            }
        }
        let body = RequestBody(employeeId: forEmployeeId, teamIds: fromTeamIds)
        _ = try await api.post("/employees/peer-feedback/request",
                               body: body,
                               as: PeerFeedbackListResponse.self)
    }
}
