import Foundation
import Observation
import Networking
import Core

// MARK: - BulkEditCoordinatorProtocol

/// Testable surface for `BulkEditCoordinator`.
public protocol BulkEditCoordinatorProtocol: AnyObject, Sendable {
    /// Execute a bulk action against the given ticket IDs.
    /// - Returns: Per-ticket outcomes aggregated from the server response.
    func execute(
        action: BulkAction,
        ticketIDs: [Int64]
    ) async -> [BulkTicketOutcome]
}

// MARK: - BulkEditCoordinator

/// Fans out bulk-edit operations to `POST /api/v1/tickets/bulk-action`.
///
/// The server already handles the loop internally; the coordinator submits
/// one request per action, parses the `affected` list, and synthesises
/// per-ticket outcome values so the result view can report successes and
/// failures.
///
/// Concurrency model:
/// - The class itself is `@MainActor` so `@Observable` progress updates
///   land on the main thread automatically.
/// - The actual network call is dispatched onto the cooperative thread pool
///   via a `Task` (the `execute` method is `async`).
/// - The server caps `ticket_ids` at 100; this coordinator enforces the
///   same limit client-side and will short-circuit with a failure outcome
///   for every ticket if the batch exceeds that ceiling.
@MainActor
@Observable
public final class BulkEditCoordinator: BulkEditCoordinatorProtocol {

    // MARK: - Constants

    private static let serverBatchLimit = 100

    // MARK: - Observable progress state

    /// True while a network request is in flight.
    public private(set) var isLoading: Bool = false

    /// 0…1 progress — updated as the coordinator resolves outcomes.
    public private(set) var progress: Double = 0

    // MARK: - Private

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Execute

    /// Execute a bulk action and return per-ticket outcome array.
    ///
    /// Strategy:
    ///  1. Validate batch size.
    ///  2. POST to `/api/v1/tickets/bulk-action`.
    ///  3. Diff the requested IDs against the server-returned `affected` array.
    ///     - IDs present in `affected` → `.succeeded`.
    ///     - IDs absent from `affected` → `.failed(message:)`.
    public func execute(
        action: BulkAction,
        ticketIDs: [Int64]
    ) async -> [BulkTicketOutcome] {
        guard !ticketIDs.isEmpty else { return [] }

        // Enforce server-side limit client-side for fast feedback.
        guard ticketIDs.count <= Self.serverBatchLimit else {
            let message = "Maximum \(Self.serverBatchLimit) tickets per batch."
            return ticketIDs.map { BulkTicketOutcome(id: $0, status: .failed(message: message)) }
        }

        isLoading = true
        progress = 0
        defer {
            isLoading = false
            progress = 1
        }

        let body = BulkActionRequest(
            ticketIds: ticketIDs,
            action: action.actionKey,
            value: action.value
        )

        do {
            let data: BulkActionData = try await api.post(
                "/api/v1/tickets/bulk-action",
                body: body,
                as: BulkActionData.self
            )

            progress = 0.9

            let succeededSet = Set(data.ticketIds)
            return ticketIDs.map { id in
                succeededSet.contains(id)
                    ? BulkTicketOutcome(id: id, status: .succeeded)
                    : BulkTicketOutcome(id: id, status: .failed(message: "Not in server response"))
            }

        } catch {
            AppLog.ui.error(
                "BulkEditCoordinator execute failed: \(error.localizedDescription, privacy: .public)"
            )
            let message = error.localizedDescription
            return ticketIDs.map { BulkTicketOutcome(id: $0, status: .failed(message: message)) }
        }
    }
}
