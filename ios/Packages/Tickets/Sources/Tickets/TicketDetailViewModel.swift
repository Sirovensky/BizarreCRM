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

    // §4 — specific error state variants for targeted UI
    public var deletedOnServerBanner: Bool = false  // 404 after initial load
    public var permissionDeniedToast: Bool = false  // 403 on action

    // §4.13 — Network error overlay: when a background refresh fails but cached
    // data is still visible we surface a glass retry pill rather than wiping the
    // content. `networkErrorMessage` non-nil = pill visible.
    public var networkErrorMessage: String? = nil

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
        let hasCachedData: Bool
        if case .loaded = state { hasCachedData = true } else { hasCachedData = false }
        if !hasCachedData { state = .loading }
        concurrentEditBanner = false
        do {
            state = .loaded(try await repo.detail(id: ticketId))
            // Clear server-error banners on successful refresh
            deletedOnServerBanner = false
            networkErrorMessage = nil
        } catch {
            let appError = AppError.from(error)
            AppLog.ui.error("Ticket detail load failed: \(error.localizedDescription, privacy: .public)")
            switch appError {
            case .notFound:
                // §4 — ticket was deleted on the server while viewing
                deletedOnServerBanner = true
                // Keep cached data visible; don't overwrite to .failed
                if case .loading = state { state = .failed("Ticket no longer exists.") }
            case .forbidden:
                permissionDeniedToast = true
                if case .loading = state { state = .failed("You don't have permission to view this ticket.") }
            case .conflict:
                // §4 — 409 stale edit detected
                concurrentEditBanner = true
            default:
                if hasCachedData {
                    // §4.13 — Keep cached content visible; show glass retry pill overlay.
                    networkErrorMessage = AppError.from(error).errorDescription
                        ?? error.localizedDescription
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
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
