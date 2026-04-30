import Foundation
import Observation
import Core
import Networking
import Sync

@MainActor
@Observable
public final class SmsListViewModel {
    public internal(set) var conversations: [SmsConversation] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    /// §91.1 — raw technical error description, for the "Show details" disclosure.
    /// Never display this directly; surface only inside a collapsed DisclosureGroup.
    public private(set) var rawErrorDetail: String?
    public var searchQuery: String = ""
    /// Exposed for `StalenessIndicator` chip in toolbar.
    public private(set) var lastSyncedAt: Date?
    /// Per-row action error shown as inline banner.
    public private(set) var actionError: String?

    // MARK: - §12.1 Filters
    public var filter: SmsListFilter = .init() {
        didSet { applyFilter() }
    }

    /// Conversations filtered + ordered per the active filter tab.
    public private(set) var filteredConversations: [SmsConversation] = []

    /// Tab-level unread counts for chip badges.
    public private(set) var tabCounts: [SmsListFilterTab: Int] = [:]

    @ObservationIgnored private let repo: SmsRepository
    @ObservationIgnored private let cachedRepo: SmsCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: SmsRepository) {
        self.repo = repo
        self.cachedRepo = repo as? SmsCachedRepository
    }

    // MARK: - Filter application

    private func applyFilter() {
        filteredConversations = filter.apply(to: conversations)
        // Recompute tab counts.
        var counts: [SmsListFilterTab: Int] = [:]
        for tab in SmsListFilterTab.allCases {
            let f = SmsListFilter(tab: tab, currentUserId: filter.currentUserId)
            counts[tab] = f.apply(to: conversations).count
        }
        tabCounts = counts
    }

    public func load() async {
        if conversations.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch(force: false)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(force: true)
    }

    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch(force: false)
        }
    }

    // MARK: - Actions

    /// Marks the thread as read; updates local conversation optimistically.
    public func markRead(phone: String) async {
        // Optimistic: zero the unread count immediately.
        conversations = conversations.map { c in
            guard c.convPhone == phone else { return c }
            return SmsConversation(
                convPhone: c.convPhone,
                lastMessageAt: c.lastMessageAt,
                lastMessage: c.lastMessage,
                lastDirection: c.lastDirection,
                messageCount: c.messageCount,
                unreadCount: 0,
                isFlagged: c.isFlagged,
                isPinned: c.isPinned,
                isArchived: c.isArchived,
                customer: c.customer,
                recentTicket: c.recentTicket
            )
        }
        do {
            try await repo.markRead(phone: phone)
        } catch {
            AppLog.ui.error("markRead failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
            // Revert on failure.
            await fetch(force: true)
        }
    }

    /// Toggles flag; updates local conversation optimistically.
    public func toggleFlag(phone: String) async {
        do {
            let newFlagged = try await repo.toggleFlag(phone: phone)
            conversations = conversations.map { c in
                guard c.convPhone == phone else { return c }
                return SmsConversation(
                    convPhone: c.convPhone,
                    lastMessageAt: c.lastMessageAt,
                    lastMessage: c.lastMessage,
                    lastDirection: c.lastDirection,
                    messageCount: c.messageCount,
                    unreadCount: c.unreadCount,
                    isFlagged: newFlagged,
                    isPinned: c.isPinned,
                    isArchived: c.isArchived,
                    customer: c.customer,
                    recentTicket: c.recentTicket
                )
            }
        } catch {
            AppLog.ui.error("toggleFlag failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Toggles pin; updates local conversation and re-sorts so pinned rows surface first.
    public func togglePin(phone: String) async {
        do {
            let newPinned = try await repo.togglePin(phone: phone)
            conversations = conversations.map { c in
                guard c.convPhone == phone else { return c }
                return SmsConversation(
                    convPhone: c.convPhone,
                    lastMessageAt: c.lastMessageAt,
                    lastMessage: c.lastMessage,
                    lastDirection: c.lastDirection,
                    messageCount: c.messageCount,
                    unreadCount: c.unreadCount,
                    isFlagged: c.isFlagged,
                    isPinned: newPinned,
                    isArchived: c.isArchived,
                    customer: c.customer,
                    recentTicket: c.recentTicket
                )
            }
            // Re-sort: pinned threads float to top (mirrors server sort in GET /conversations).
            conversations = conversations.sorted { a, b in
                if a.isPinned && !b.isPinned { return true }
                if !a.isPinned && b.isPinned { return false }
                return false
            }
        } catch {
            AppLog.ui.error("togglePin failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Toggles archive; removes conversation from list when archiving (mirrors server filter).
    public func toggleArchive(phone: String) async {
        do {
            let nowArchived = try await repo.toggleArchive(phone: phone)
            if nowArchived {
                // Remove from visible list — server excludes archived unless include_archived=1.
                conversations.removeAll { $0.convPhone == phone }
            } else {
                // Unarchived — reload so it reappears correctly sorted.
                await fetch(force: true)
            }
        } catch {
            AppLog.ui.error("toggleArchive failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Clears the inline action error banner.
    public func clearActionError() {
        actionError = nil
    }

    // MARK: - Private

    private func fetch(force: Bool) async {
        errorMessage = nil
        do {
            let keyword: String? = searchQuery.isEmpty ? nil : searchQuery
            if force, let cached = cachedRepo {
                conversations = try await cached.forceRefresh(keyword: keyword)
                lastSyncedAt = await cached.lastSyncedAt
            } else if let cached = cachedRepo {
                conversations = try await cached.listConversations(keyword: keyword)
                lastSyncedAt = await cached.lastSyncedAt
            } else {
                conversations = try await repo.listConversations(keyword: keyword)
            }
            applyFilter()
        } catch {
            handleFetchError(error)
        }
    }

    /// §91.1 §91.14 — Centralised error handler for the conversations fetch pipeline.
    ///
    /// - Wraps `DecodingError` (and any other raw error) in a friendly `SmsError` so
    ///   the UI never exposes internal field names or type details.
    /// - Logs the **raw** technical description to `AppLog.communications` (§4).
    /// - Fires a §32 telemetry event on decode failure (§6).
    private func handleFetchError(_ error: any Error) {
        // §4 — always log the raw error for diagnostics; never shown in UI.
        AppLog.communications.error(
            "SMS conversations fetch failed: \(error.localizedDescription, privacy: .public)"
        )

        let smsError: SmsError = .decodingConversations(underlying: error)
        if error is DecodingError {
            // §6 — §32 telemetry hook on decode failure.
            Analytics.track(
                .smsDecodeFailure,
                properties: ["error_type": .string("DecodingError")]
            )
            AppLog.communications.error(
                "SMS decode failure detail (§91.14): \(String(describing: error), privacy: .public)"
            )
        }

        // §1 — expose friendly message; technical payload hidden behind "Show details" in UI.
        errorMessage = smsError.errorDescription
        rawErrorDetail = String(describing: error)
    }
}
