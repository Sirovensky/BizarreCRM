import Foundation
import Observation
import Core
import Networking

// §4.9 — Bench workflow view model.
//
// Drives `BenchWorkflowView`. Loads current ticket detail, resolves available
// `BenchAction`s from the state machine, and calls the real
// PATCH /api/v1/tickets/:id/status endpoint via `changeTicketStatus`.
//
// Status-id resolution mirrors `TicketStatusTransitionViewModel`:
//  1. GET /api/v1/settings/statuses to fetch the server's status list.
//  2. Map the target `TicketStatus` display name → server status row id.
//
// No invented endpoints — all calls are documented in:
//   packages/server/src/routes/tickets.routes.ts  (line 2124)
//   ios/Packages/Networking/.../TicketStatusEndpoints.swift

@MainActor
@Observable
public final class BenchWorkflowViewModel {

    // MARK: - State

    public enum LoadState: Sendable {
        case idle
        case loading
        case loaded(TicketDetail)
        case failed(String)
    }

    public var loadState: LoadState = .idle
    public var isSubmitting: Bool = false
    public var errorMessage: String?
    /// The transition that was successfully committed; observers use this
    /// to refresh parent views or dismiss the bench screen.
    public var committedAction: BenchAction?

    // MARK: - Derived (updated when loadState changes)

    public var currentTicketStatus: TicketStatus? {
        guard case let .loaded(detail) = loadState,
              let name = detail.status?.name else { return nil }
        return TicketStatus.allCases.first {
            $0.rawValue.lowercased() == name.lowercased() ||
            $0.displayName.lowercased() == name.lowercased()
        }
    }

    public var availableActions: [BenchAction] {
        guard let status = currentTicketStatus else { return [] }
        return BenchAction.availableActions(for: status)
    }

    // MARK: - Private

    public let ticketId: Int64
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var serverStatuses: [TicketStatusRow] = []

    // MARK: - Init

    public init(ticketId: Int64, api: APIClient) {
        self.ticketId = ticketId
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        loadState = .loading
        errorMessage = nil
        do {
            async let detailTask = api.ticket(id: ticketId)
            async let statusesTask = api.listTicketStatuses()
            let (detail, statuses) = try await (detailTask, statusesTask)
            serverStatuses = statuses
            loadState = .loaded(detail)
        } catch {
            AppLog.ui.error(
                "BenchWorkflow load failed: \(error.localizedDescription, privacy: .public)"
            )
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Perform action

    /// Applies `action` by resolving the corresponding server status id
    /// and calling PATCH /api/v1/tickets/:id/status.
    public func perform(_ action: BenchAction) async {
        guard let currentStatus = currentTicketStatus else {
            errorMessage = "Ticket status is not yet loaded."
            return
        }
        guard let transition = action.transition(from: currentStatus) else {
            errorMessage = "\(action.displayName) is not allowed from \"\(currentStatus.displayName)\"."
            return
        }

        // Validate via state machine
        let result = TicketStateMachine.apply(transition, to: currentStatus)
        let targetStatus: TicketStatus
        switch result {
        case .success(let next):
            targetStatus = next
        case .failure(let err):
            errorMessage = err.errorDescription
            return
        }

        guard let statusId = resolveStatusId(for: targetStatus) else {
            errorMessage = "Server has no status matching \"\(targetStatus.displayName)\". Contact your admin."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        do {
            _ = try await api.changeTicketStatus(id: ticketId, statusId: statusId)
            committedAction = action
            // Refresh detail in background so the view updates after commit.
            await load()
        } catch {
            AppLog.ui.error(
                "BenchWorkflow action \(action.rawValue) failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Private helpers

    private func resolveStatusId(for target: TicketStatus) -> Int64? {
        serverStatuses.first {
            $0.name.lowercased() == target.displayName.lowercased() ||
            $0.name.lowercased() == target.rawValue.lowercased()
        }?.id
    }
}
