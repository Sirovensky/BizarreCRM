import Foundation
import Observation
import Core
import Networking

// §4.7 — TicketTimelineViewModel
// Loads GET /tickets/:id/events and exposes the sorted event list.
// If the server doesn't have the /events endpoint yet (404 or missing)
// it falls back to the embedded `history` array on TicketDetail.

public enum TimelineLoadState: Sendable {
    case idle
    case loading
    case loaded([TicketEvent])
    case failed(String)
}

@MainActor
@Observable
public final class TicketTimelineViewModel {

    // MARK: — State

    public private(set) var loadState: TimelineLoadState = .idle
    public var filterKind: TicketEvent.EventKind? = nil  // nil = all

    // MARK: — Derived

    public var events: [TicketEvent] {
        guard case .loaded(let all) = loadState else { return [] }
        if let kind = filterKind {
            return all.filter { $0.kind == kind }
        }
        return all
    }

    public var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    // MARK: — Dependencies

    @ObservationIgnored private let ticketId: Int64
    @ObservationIgnored private let api: APIClient
    /// Fallback events sourced from TicketDetail.history (already fetched).
    @ObservationIgnored private let fallbackHistory: [TicketDetail.TicketHistory]

    // MARK: — Init

    public init(
        ticketId: Int64,
        api: APIClient,
        fallbackHistory: [TicketDetail.TicketHistory] = []
    ) {
        self.ticketId = ticketId
        self.api = api
        self.fallbackHistory = fallbackHistory
    }

    // MARK: — Load

    public func load() async {
        guard !isLoading else { return }
        loadState = .loading

        do {
            let events = try await api.ticketEvents(id: ticketId)
            loadState = .loaded(events.sorted { $0.createdAt > $1.createdAt })
        } catch {
            // If the events endpoint isn't available (404 etc.), fall back
            // to the history entries already embedded in TicketDetail.
            if shouldFallback(error) {
                let synthetic = fallbackHistory.map(Self.toSyntheticEvent)
                    .sorted { $0.createdAt > $1.createdAt }
                loadState = .loaded(synthetic)
            } else {
                AppLog.ui.error("Timeline load failed: \(error.localizedDescription, privacy: .public)")
                loadState = .failed(AppError.from(error).errorDescription ?? error.localizedDescription)
            }
        }
    }

    public func retry() async {
        loadState = .idle
        await load()
    }

    // MARK: — Private

    private func shouldFallback(_ error: Error) -> Bool {
        if let transport = error as? APITransportError,
           case .httpStatus(let code, _) = transport,
           code == 404 {
            return true
        }
        return TicketOfflineQueue.isNetworkError(error)
    }

    /// Convert a TicketDetail.TicketHistory row to a synthetic TicketEvent
    /// for display in the timeline fallback path.
    private static func toSyntheticEvent(_ history: TicketDetail.TicketHistory) -> TicketEvent {
        // We can't use the memberwise init directly because TicketEvent is
        // Decodable-only (no public memberwise init). Build it via JSON.
        let json = """
        {
          "id": \(history.id),
          "created_at": "\(history.createdAt ?? "")",
          "actor_name": \(history.userName.map { "\"\($0)\"" } ?? "null"),
          "kind": "status_change",
          "message": "\(jsonEscape(history.stripped))"
        }
        """
        let data = json.data(using: .utf8) ?? Data()
        return (try? JSONDecoder().decode(TicketEvent.self, from: data))
            ?? TicketEvent(id: history.id, createdAt: history.createdAt ?? "", actorName: history.userName, kind: .unknown, message: history.stripped, diff: nil)
    }

    private static func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }
}

