import Foundation
import Networking

// MARK: - §12.10 Call Log Repository Protocol

/// Repository protocol for the Calls tab call-log list.
/// Thin layer over `APIClient.listCalls` so the ViewModel can be tested without a live network.
public protocol CallLogRepository: Sendable {
    /// Fetch the paginated call log. Returns an empty array on server 404 (feature not deployed).
    func listCalls(pageSize: Int) async throws -> [CallLogEntry]
    /// Initiate a click-to-call to `to`. Body: `{ to, customer_id? }`.
    /// Server: POST /api/v1/voice/call. Returns the call ID assigned server-side.
    func initiateCall(to phoneNumber: String, customerId: Int64?) async throws -> Int64
    /// Hang up an active call. Server: POST /api/v1/voice/call/:id/hangup.
    func hangupCall(id: Int64) async throws
}

// MARK: - Live implementation

public actor CallLogRepositoryImpl: CallLogRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listCalls(pageSize: Int = 50) async throws -> [CallLogEntry] {
        try await api.listCalls(pageSize: pageSize)
    }

    public func initiateCall(to phoneNumber: String, customerId: Int64?) async throws -> Int64 {
        try await api.initiateVoiceCall(to: phoneNumber, customerId: customerId)
    }

    public func hangupCall(id: Int64) async throws {
        try await api.hangupVoiceCall(id: id)
    }
}
