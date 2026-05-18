import Foundation
import Core
import Networking

// MARK: - Supporting types

public struct MergeFieldPreference: Sendable, Hashable {
    public enum Winner: String, Sendable, Hashable, Codable {
        case primary, secondary
    }
    public let field: String
    public var winner: Winner

    public init(field: String, winner: Winner = .primary) {
        self.field = field
        self.winner = winner
    }
}

public struct MergeRequest: Encodable, Sendable {
    public let primaryId: Int64
    public let secondaryId: Int64
    public let fieldPreferences: [String: String]

    enum CodingKeys: String, CodingKey {
        case primaryId = "primaryId"
        case secondaryId = "secondaryId"
        case fieldPreferences = "fieldPreferences"
    }
}

public struct MergeResponse: Decodable, Sendable {
    public let mergedTicketId: Int64
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case mergedTicketId = "mergedTicketId"
        case message
    }
}

// MARK: - ViewModel

@Observable
@MainActor
public final class TicketMergeViewModel: Sendable {

    public enum State: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case merging
        case success(mergedId: Int64)
        case failed(String)
    }

    // Primary (base) ticket
    public var primaryTicket: TicketDetail?
    // Secondary (to be merged in) ticket
    public var secondaryTicket: TicketDetail?
    // Field-level winner preferences
    public var preferences: [MergeFieldPreference] = []

    public private(set) var state: State = .idle
    public private(set) var candidateResults: [TicketSummary] = []
    public var candidateSearchQuery: String = "" {
        didSet { scheduleSearch() }
    }

    private let primaryId: Int64
    private let repo: TicketRepository
    private let api: APIClient
    private var searchTask: Task<Void, Never>?

    public init(primaryId: Int64, repo: TicketRepository, api: APIClient) {
        self.primaryId = primaryId
        self.repo = repo
        self.api = api
    }

    // MARK: - Load primary

    public func loadPrimary() async {
        state = .loading
        do {
            let detail = try await repo.detail(id: primaryId)
            primaryTicket = detail
            buildDefaultPreferences()
            state = .loaded
        } catch let e where AppError.isCancellation(e) {
            return  // BUGHUNT-2026-05-18: nav cancel — leave .loading; reopen re-fires
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Candidate search

    public func selectCandidate(_ ticket: TicketSummary) async {
        state = .loading
        do {
            let detail = try await repo.detail(id: ticket.id)
            secondaryTicket = detail
            buildDefaultPreferences()
            state = .loaded
        } catch let e where AppError.isCancellation(e) {
            return  // BUGHUNT-2026-05-18: row-tap canceled by a faster tap on another candidate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = candidateSearchQuery
        guard !q.isEmpty else { candidateResults = []; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(q)
        }
    }

    private func performSearch(_ keyword: String) async {
        do {
            candidateResults = try await repo.list(
                filter: .all,
                keyword: keyword
            ).filter { $0.id != primaryId }
        } catch {
            candidateResults = []
        }
    }

    // MARK: - Merge

    public func merge() async {
        guard let sec = secondaryTicket else { return }
        // BUGHUNT-2026-05-17: merge is destructive — the secondary ticket is
        // folded into primary server-side. Re-entry during `.merging` or
        // after `.success` could fire a second POST whose outcome depends on
        // server state (404 on the missing secondary, or worse, a different
        // row picked up if IDs were reused). Self-guard at the VM layer.
        if case .merging = state { return }
        if case .success = state { return }
        state = .merging
        do {
            let prefs = preferences.reduce(into: [String: String]()) { dict, pref in
                dict[pref.field] = pref.winner.rawValue
            }
            let req = MergeRequest(
                primaryId: primaryId,
                secondaryId: sec.id,
                fieldPreferences: prefs
            )
            let response = try await api.post(
                "/api/v1/tickets/merge",
                body: req,
                as: MergeResponse.self
            )
            state = .success(mergedId: response.mergedTicketId)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: a `.failed("cancelled")` toast on a merge
            // tempted a re-tap that — if the server had already accepted the
            // original POST — would attempt a second merge against a missing
            // secondary. Reset to `.loaded`; the caller should pop and refresh.
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Field preference helpers

    public func setWinner(_ winner: MergeFieldPreference.Winner, forField field: String) {
        if let idx = preferences.firstIndex(where: { $0.field == field }) {
            preferences[idx] = MergeFieldPreference(field: field, winner: winner)
        }
    }

    private func buildDefaultPreferences() {
        // Build diff-able fields based on available tickets
        let fields = ["status", "assignedUser", "notes", "devices"]
        preferences = fields.map { MergeFieldPreference(field: $0, winner: .primary) }
    }
}
