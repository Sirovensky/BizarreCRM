import Foundation
import Networking

// MARK: - Request / Response

public struct TicketSplitRequest: Encodable, Sendable {
    public let deviceLineIds: [Int64]

    enum CodingKeys: String, CodingKey {
        case deviceLineIds = "deviceLineIds"
    }
}

public struct TicketSplitResponse: Decodable, Sendable {
    public let originalTicketId: Int64
    public let newTicketIds: [String]

    enum CodingKeys: String, CodingKey {
        case originalTicketId = "originalTicketId"
        case newTicketIds = "newTicketIds"
    }
}

// MARK: - ViewModel

@Observable
@MainActor
public final class TicketSplitViewModel: Sendable {

    public enum State: Sendable {
        case idle
        case loading
        case loaded
        case splitting
        case success(originalId: Int64, newIds: [String])
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var ticket: TicketDetail?
    /// Device IDs selected for the new ticket.
    public var selectedDeviceIds: Set<Int64> = []

    private let ticketId: Int64
    private let repo: TicketRepository
    private let api: APIClient

    public var selectedCount: Int { selectedDeviceIds.count }
    public var canSplit: Bool { !selectedDeviceIds.isEmpty && selectedDeviceIds.count < (ticket?.devices.count ?? 0) }

    public init(ticketId: Int64, repo: TicketRepository, api: APIClient) {
        self.ticketId = ticketId
        self.repo = repo
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        state = .loading
        do {
            ticket = try await repo.detail(id: ticketId)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Selection

    public func toggleDevice(_ id: Int64) {
        if selectedDeviceIds.contains(id) {
            selectedDeviceIds.remove(id)
        } else {
            selectedDeviceIds.insert(id)
        }
    }

    public func isSelected(_ id: Int64) -> Bool {
        selectedDeviceIds.contains(id)
    }

    // MARK: - Split

    public func split() async {
        guard canSplit else { return }
        state = .splitting
        do {
            let body = TicketSplitRequest(deviceLineIds: Array(selectedDeviceIds))
            let response = try await api.post(
                "/api/v1/tickets/\(ticketId)/split",
                body: body,
                as: TicketSplitResponse.self
            )
            state = .success(originalId: response.originalTicketId, newIds: response.newTicketIds)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
