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
    /// §4.13 — Transient network failure on a refresh of an already-loaded
    /// ticket. Keep the cached `.loaded(detail)` visible and surface a glass
    /// retry pill so the user can pull fresh data without losing context.
    public var networkErrorBanner: Bool = false

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
        let hadCachedDetail: Bool
        if case .loaded = state {
            // soft-refresh keeps old data visible
            hadCachedDetail = true
        } else {
            state = .loading
            hadCachedDetail = false
        }
        concurrentEditBanner = false
        do {
            state = .loaded(try await repo.detail(id: ticketId))
            // Clear server-error banners on successful refresh
            deletedOnServerBanner = false
            networkErrorBanner = false
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
            case .network, .offline:
                // §4.13 — Network error on detail. If we already had cached
                // data on screen, leave it there and show a retry pill so the
                // user keeps reading while reachability comes back. Only fall
                // through to a hard `.failed` when there's no cache to show.
                if hadCachedDetail {
                    networkErrorBanner = true
                } else {
                    state = .failed(error.localizedDescription)
                }
            default:
                state = .failed(error.localizedDescription)
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
            handleActionError(error)
        }
    }

    // MARK: - §4.5 Convert to invoice

    public func convertToInvoice() async {
        do {
            let response = try await repo.convertToInvoice(id: ticketId)
            convertedInvoiceId = response.resolvedInvoiceId
        } catch {
            AppLog.ui.error("Convert ticket \(self.ticketId) to invoice failed: \(error.localizedDescription, privacy: .public)")
            handleActionError(error)
        }
    }

    /// §4.13 — Centralized error funnel for action paths so any 403 surfaces
    /// the "Ask your admin to enable this." inline toast instead of a generic
    /// alert. Other errors fall through to `actionErrorMessage` for the
    /// existing alert dialog.
    private func handleActionError(_ error: Error) {
        let appError = AppError.from(error)
        if case .forbidden = appError {
            permissionDeniedToast = true
        } else {
            actionErrorMessage = error.localizedDescription
        }
    }

    // MARK: - §4.1 / §4.5 Pin / unpin

    /// §4.1 — Optimistic override of the server's `is_pinned` so the toolbar
    /// icon flips instantly while the PATCH is in flight. `nil` means "no
    /// override — defer to the loaded detail's value".
    public var pinnedOverride: Bool?

    /// True when the ticket should currently render as pinned (override wins).
    public var isPinned: Bool {
        if let pinnedOverride { return pinnedOverride }
        if case .loaded(let detail) = state { return detail.isPinned ?? false }
        return false
    }

    /// Toggle the pinned state of this ticket via `PATCH /tickets/:id { pinned }`.
    /// Optimistically flips a local override so the toolbar icon updates
    /// immediately; on failure surfaces the standard action error toast (or
    /// permission-denied toast on 403) and reloads to recover server truth.
    public func togglePin(api: APIClient) async {
        guard case .loaded = state else { return }
        let newValue = !isPinned
        pinnedOverride = newValue
        do {
            try await api.setTicketPinned(ticketId: ticketId, pinned: newValue)
            // Drop the override and refresh from server so subsequent loads
            // reflect the real value.
            await load()
            pinnedOverride = nil
        } catch {
            AppLog.ui.error("Toggle pin ticket \(self.ticketId) failed: \(error.localizedDescription, privacy: .public)")
            pinnedOverride = nil
            handleActionError(error)
        }
    }

    // MARK: - §4.5 Duplicate

    public func duplicateTicket() async {
        do {
            let response = try await repo.duplicate(id: ticketId)
            duplicatedTicketId = response.resolvedId
        } catch {
            AppLog.ui.error("Duplicate ticket \(self.ticketId) failed: \(error.localizedDescription, privacy: .public)")
            handleActionError(error)
        }
    }
}
