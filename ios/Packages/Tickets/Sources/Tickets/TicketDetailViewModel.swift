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

    // §4.4 — delete + concurrent-edit states
    public var showDeleteConfirm: Bool = false
    public var isDeleting: Bool = false
    public var wasDeleted: Bool = false
    public var concurrentEditBanner: Bool = false   // 409 stale edit detected

    // §4.5 — action results
    public var convertedInvoiceId: Int64?
    public var duplicatedTicketId: Int64?
    public var actionErrorMessage: String?

    @ObservationIgnored public let repo: TicketRepository

    public init(repo: TicketRepository, ticketId: Int64) {
        self.repo = repo
        self.ticketId = ticketId
    }

    public func load() async {
        if case .loaded = state { /* soft-refresh keeps old data visible */ } else {
            state = .loading
        }
        concurrentEditBanner = false
        do {
            state = .loaded(try await repo.detail(id: ticketId))
        } catch {
            let msg = error.localizedDescription
            // 409 detection: server returns stale `updated_at` conflict
            if msg.contains("409") || msg.lowercased().contains("conflict") {
                concurrentEditBanner = true
            }
            AppLog.ui.error("Ticket detail load failed: \(msg, privacy: .public)")
            state = .failed(msg)
        }
    }

    // MARK: - §4.4 Delete

    public func deleteTicket() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await repo.delete(id: ticketId)
            wasDeleted = true
        } catch {
            AppLog.ui.error("Delete ticket \(self.ticketId) failed: \(error.localizedDescription, privacy: .public)")
            actionErrorMessage = error.localizedDescription
        }
    }

    // MARK: - §4.5 Convert to invoice

    public func convertToInvoice() async {
        do {
            let response = try await repo.convertToInvoice(id: ticketId)
            convertedInvoiceId = response.resolvedInvoiceId
        } catch {
            AppLog.ui.error("Convert ticket \(self.ticketId) to invoice failed: \(error.localizedDescription, privacy: .public)")
            actionErrorMessage = error.localizedDescription
        }
    }

    // MARK: - §4.5 Duplicate

    public func duplicateTicket() async {
        do {
            let response = try await repo.duplicate(id: ticketId)
            duplicatedTicketId = response.resolvedId
        } catch {
            AppLog.ui.error("Duplicate ticket \(self.ticketId) failed: \(error.localizedDescription, privacy: .public)")
            actionErrorMessage = error.localizedDescription
        }
    }
}
