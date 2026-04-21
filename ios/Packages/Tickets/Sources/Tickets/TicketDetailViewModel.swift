import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class TicketDetailViewModel {
    public enum State: Sendable {
        case loading
        case loaded(TicketDetail)
        case failed(String)
    }

    public var state: State = .loading
    public let ticketId: Int64

    @ObservationIgnored public let repo: TicketRepository

    public init(repo: TicketRepository, ticketId: Int64) {
        self.repo = repo
        self.ticketId = ticketId
    }

    public func load() async {
        if case .loaded = state { /* soft-refresh keeps old data visible */ } else {
            state = .loading
        }
        do {
            state = .loaded(try await repo.detail(id: ticketId))
        } catch {
            AppLog.ui.error("Ticket detail load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
